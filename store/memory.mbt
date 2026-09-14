///|
/// The default, in-memory `ViewStore`.
pub struct MemoryViewStore {
  priv tables : Map[String, Map[String, Json]]
  priv checkpoints : Map[String, @strata.Position]
}

///|
/// Builds an empty view store.
pub fn MemoryViewStore::MemoryViewStore() -> MemoryViewStore {
  { tables: Map([]), checkpoints: Map([]), }
}

///|
pub impl ViewStore for MemoryViewStore with fn commit(
  self,
  writes~,
  checkpoint?,
) {
  for write in writes {
    match write.value {
      Some(value) =>
        ViewStore::put(self, table=write.table, key=write.key, value)
      None => ViewStore::delete(self, table=write.table, key=write.key)
    }
  }
  match checkpoint {
    Some(cp) => self.checkpoints[cp.name] = cp.position
    None => ()
  }
}

///|
pub impl ViewStore for MemoryViewStore with fn checkpoint(self, name) {
  self.checkpoints.get(name)
}

///|
pub impl ViewStore for MemoryViewStore with fn get(self, table~, key~) {
  match self.tables.get(table) {
    None => None
    Some(rows) => rows.get(key)
  }
}

///|
pub impl ViewStore for MemoryViewStore with fn put(self, table~, key~, value) {
  if self.tables.contains(table) == false {
    self.tables[table] = Map([])
  }
  self.tables[table][key] = value
}

///|
pub impl ViewStore for MemoryViewStore with fn delete(self, table~, key~) {
  match self.tables.get(table) {
    None => ()
    Some(rows) => rows.remove(key)
  }
}

///|
pub impl ViewStore for MemoryViewStore with fn keys(self, table~) {
  match self.tables.get(table) {
    None => []
    Some(rows) => {
      let keys : Array[String] = []
      rows.each((k, _) => keys.push(k))
      keys
    }
  }
}

///|
pub impl ViewStore for MemoryViewStore with fn swap(self, from~, to~) {
  let moved = match self.tables.get(from) {
    Some(rows) => rows
    None => Map([])
  }
  self.tables[to] = moved
  self.tables.remove(from)
}

///|
/// The default, in-memory `KeyStore`.
pub struct MemoryKeyStore {
  priv keys : Map[String, Bytes]
  priv sealed_subjects : Set[String]
  priv destroyed_subjects : Set[String]
  priv unseals : Array[(String, String)]
}

///|
/// Builds an empty key store.
pub fn MemoryKeyStore::MemoryKeyStore() -> MemoryKeyStore {
  {
    keys: Map([]),
    sealed_subjects: Set([]),
    destroyed_subjects: Set([]),
    unseals: [],
  }
}

///|
pub impl KeyStore for MemoryKeyStore with fn key_for(self, subject) {
  if self.destroyed_subjects.contains(subject) {
    raise KeyDestroyed(subject~)
  }
  if self.sealed_subjects.contains(subject) {
    raise KeySealed(subject~)
  }
  match self.keys.get(subject) {
    Some(key) => key
    None => {
      let key = Bytes::make(16, b'\x01')
      self.keys[subject] = key
      key
    }
  }
}

///|
pub impl KeyStore for MemoryKeyStore with fn destroy(self, subject) {
  self.keys.remove(subject)
  self.sealed_subjects.remove(subject)
  self.destroyed_subjects.add(subject)
}

///|
pub impl KeyStore for MemoryKeyStore with fn seal(self, subject) {
  if self.destroyed_subjects.contains(subject) {
    raise KeyDestroyed(subject~)
  }
  self.sealed_subjects.add(subject)
}

///|
pub impl KeyStore for MemoryKeyStore with fn unseal(self, subject, capability~) {
  if self.destroyed_subjects.contains(subject) {
    raise KeyDestroyed(subject~)
  }
  match self.keys.get(subject) {
    None => raise KeyMissing(subject~)
    Some(key) => {
      self.unseals.push((subject, capability))
      key
    }
  }
}

///|
/// The unseal audit trail: `(subject, capability)` pairs, in order.
pub fn MemoryKeyStore::unseals(
  self : MemoryKeyStore,
) -> Array[(String, String)] {
  self.unseals
}

///|
/// A subscription over a `MemoryStore`, woken by appends.
pub struct MemorySubscription {
  priv store : MemoryStore
  priv selection : @strata.Selection
  priv mut position : @strata.Position
  priv mut closed : Bool
}

///|
pub impl Subscription for MemorySubscription with fn next(self, timeout?) {
  if self.closed {
    return []
  }
  fn collect(sub : MemorySubscription) -> Array[@strata.StoredEvent] {
    let out : Array[@strata.StoredEvent] = []
    for event in sub.store.log {
      if event.position.0 > sub.position.0 &&
        sub.selection.matches(event_type=event.event_type, tags=event.tags) {
        out.push(event)
      }
    }
    match out.last() {
      Some(last) => sub.position = last.position
      None => ()
    }
    out
  }

  let available = collect(self)
  if available.is_empty() == false {
    return available
  }
  async fn wait_for_batch(
    sub : MemorySubscription,
  ) -> Array[@strata.StoredEvent] {
    while true {
      sub.store.appended.wait()
      if sub.closed {
        return []
      }
      let batch = collect(sub)
      if batch.is_empty() == false {
        return batch
      }
    } nobreak {
      []
    }
  }

  match timeout {
    None => wait_for_batch(self)
    Some(duration) =>
      @async.with_timeout(duration.to_millis().to_int(), () => {
        wait_for_batch(self)
      }) catch {
        @async.TimeoutError => []
        err => raise err
      }
  }
}

///|
pub impl Subscription for MemorySubscription with fn position(self) {
  self.position
}

///|
pub impl Subscription for MemorySubscription with fn close(self) {
  self.closed = true
  self.store.appended.broadcast()
}

///|
/// The default `EventStore`: a single in-process log. Used for tests, for
/// `Preview`-style tooling, and as the reference for the contract suite.
pub struct MemoryStore {
  priv log : Array[@strata.StoredEvent]
  priv checkpoints : Map[String, @strata.Position]
  priv snapshots : Map[SnapshotKey, SnapshotRecord]
  priv view_store : MemoryViewStore
  priv appended : @cond_var.Cond
}

///|
/// Builds an empty store.
pub fn MemoryStore::MemoryStore() -> MemoryStore {
  let checkpoints : Map[String, @strata.Position] = Map([])
  {
    log: [],
    checkpoints,
    snapshots: Map([]),
    view_store: { tables: Map([]), checkpoints, },
    appended: @cond_var.Cond(),
  }
}

///|
/// The number of events in the log.
pub fn MemoryStore::length(self : MemoryStore) -> Int {
  self.log.length()
}

///|
fn system_tags(stream : @strata.StreamId) -> Array[@strata.Tag] {
  let tags : Array[@strata.Tag] = [
    @strata.Tag::kv(key="$stream", value=stream.0),
    @strata.Tag::kv(key="$category", value=stream.category()),
  ]
  match stream.tenant() {
    Some(tenant) => tags.push(@strata.Tag::kv(key="$tenant", value=tenant))
    None => ()
  }
  tags
}

///|
fn stream_version(
  log : Array[@strata.StoredEvent],
  stream : @strata.StreamId,
) -> Int {
  log.count_if(event => event.stream == stream)
}

///|
pub impl EventStore for MemoryStore with fn append(
  self,
  stream~,
  condition~,
  events~,
  recorded_at~,
  inline?,
) {
  let actual = stream_version(self.log, stream)
  match condition {
    Stream(expected_stream, expected) => {
      let actual = stream_version(self.log, expected_stream)
      match expected {
        Any => ()
        NoStream =>
          if actual != 0 {
            raise @strata.StreamConflict(
              stream=expected_stream,
              expected=NoStream,
              actual~,
            )
          }
        Exact(n) =>
          if actual != n {
            raise @strata.StreamConflict(
              stream=expected_stream,
              expected=Exact(n),
              actual~,
            )
          }
      }
    }
    Dcb(selection~, after~) =>
      for event in self.log {
        if selection.matches(event_type=event.event_type, tags=event.tags) {
          let conflict = match after {
            None => true
            Some(bound) => event.position.0 > bound.0
          }
          if conflict {
            raise @strata.BoundaryConflict(
              selection~,
              after~,
              at=event.position,
            )
          }
        }
      }
  }
  let sys = system_tags(stream)
  let stored : Array[@strata.StoredEvent] = []
  let mut version = actual
  let base = self.log.length()
  for event in events {
    version += 1
    let position = @strata.Position((base + stored.length() + 1).to_int64())
    let tags = event.tags.copy()
    tags.append(sys[:])
    stored.push(
      @strata.StoredEvent(
        id=event.id,
        position~,
        stream~,
        version~,
        event_type=event.event_type,
        schema=event.schema,
        data=event.data,
        tags~,
        meta=event.meta,
        recorded_at~,
      ),
    )
  }
  self.log.append(stored[:])
  for write in inline.unwrap_or([]) {
    match write.value {
      Some(value) =>
        ViewStore::put(self.view_store, table=write.table, key=write.key, value)
      None =>
        ViewStore::delete(self.view_store, table=write.table, key=write.key)
    }
  }
  self.appended.broadcast()
  let position = match stored.last() {
    Some(event) => event.position
    None =>
      match self.log.last() {
        Some(event) => event.position
        None => @strata.start
      }
  }
  AppendResult(events=stored, version~, position~)
}

///|
pub impl EventStore for MemoryStore with fn read(
  self,
  selection,
  after?,
  limit?,
) {
  let after = after.unwrap_or(@strata.start)
  let out : Array[@strata.StoredEvent] = []
  for event in self.log {
    if event.position.0 > after.0 &&
      selection.matches(event_type=event.event_type, tags=event.tags) {
      out.push(event)
      match limit {
        Some(n) if out.length() >= n => break
        _ => ()
      }
    }
  }
  out
}

///|
pub impl EventStore for MemoryStore with fn read_stream(
  self,
  stream,
  from_version?,
) {
  let from = from_version.unwrap_or(1)
  self.log.filter(event => event.stream == stream && event.version >= from)
}

///|
pub impl EventStore for MemoryStore with fn head(self) {
  match self.log.last() {
    Some(event) => event.position
    None => @strata.start
  }
}

///|
pub impl EventStore for MemoryStore with fn find_idempotent(self, key~, stream?) {
  self.log.filter(event => {
    let keyed = event.meta.idempotency_key == Some(key)
    let scoped = match stream {
      None => true
      Some(s) => event.stream == s
    }
    keyed && scoped
  })
}

///|
pub impl EventStore for MemoryStore with fn subscribe(self, selection, from~) {
  { store: self, selection, position: from, closed: false, } as &Subscription
}

///|
pub impl EventStore for MemoryStore with fn load_checkpoint(self, name) {
  self.checkpoints.get(name)
}

///|
pub impl EventStore for MemoryStore with fn save_checkpoint(
  self,
  name,
  position,
) {
  self.checkpoints[name] = position
}

///|
pub impl EventStore for MemoryStore with fn load_snapshot(self, key) {
  self.snapshots.get(key)
}

///|
pub impl EventStore for MemoryStore with fn save_snapshot(self, key, record) {
  self.snapshots[key] = record
}

///|
pub impl EventStore for MemoryStore with fn views(self) {
  self.view_store as &ViewStore
}
