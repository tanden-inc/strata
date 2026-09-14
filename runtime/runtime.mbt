///|
/// The async shell around the pure core: it owns the store, the codec, the
/// clock and the id generator, and turns deciders into command handlers,
/// selections into reads and folds, and projections into projectors.
pub struct Runtime {
  priv store : &@store.EventStore
  priv codec : @codec.JsonCodec
  priv clock : Clock
  priv ids : IdGenerator
  priv keys : &@store.KeyStore
}

///|
/// Builds a runtime over any `EventStore`. Defaults: a codec at schema
/// version 1 with the flat tag style, the system clock, ULID ids, and an
/// in-memory key store.
pub fn[St : @store.EventStore] Runtime::Runtime(
  store : St,
  codec? : @codec.JsonCodec = @codec.JsonCodec(),
  clock? : Clock = Clock::system(),
  ids? : IdGenerator = IdGenerator::ulid(),
  keys? : &@store.KeyStore = @store.MemoryKeyStore() as &@store.KeyStore,
) -> Runtime {
  { store: store as &@store.EventStore, codec, clock, ids, keys, }
}

///|
/// The event store.
pub fn Runtime::store(self : Runtime) -> &@store.EventStore {
  self.store
}

///|
/// The store's view store (inline and projected read models live here).
pub fn Runtime::views(self : Runtime) -> &@store.ViewStore {
  self.store.views()
}

///|
/// The codec.
pub fn Runtime::codec(self : Runtime) -> @codec.JsonCodec {
  self.codec
}

///|
/// The clock.
pub fn Runtime::clock(self : Runtime) -> Clock {
  self.clock
}

///|
/// The key store.
pub fn Runtime::keys(self : Runtime) -> &@store.KeyStore {
  self.keys
}

///|
/// A page of events matching a selection, strictly after `after`.
pub async fn Runtime::read(
  self : Runtime,
  selection : @strata.Selection,
  after? : @strata.Position,
  limit? : Int = 100,
) -> Page {
  let events = match after {
    Some(p) => @store.EventStore::read(self.store, selection, after=p, limit~)
    None => @store.EventStore::read(self.store, selection, limit~)
  }
  let next = if events.length() == limit {
    match events.last() {
      Some(e) => Some(e.position)
      None => None
    }
  } else {
    None
  }
  Page(events~, next~, codec=self.codec)
}

///|
/// Folds a selection into a view.
pub async fn[E : @json.FromJson, V] Runtime::fold(
  self : Runtime,
  projection : @strata.Projection[E, V],
  selection : @strata.Selection,
) -> V {
  let stored = read_all(self.store, selection, @strata.start)
  let decoded : Array[@strata.Recorded[E]] = self.codec.decode_all(stored)
  projection.fold(decoded.map(r => r.event).iter())
}

///|
/// Folds a selection into keyed rows.
pub async fn[E : @json.FromJson, K : Eq + Hash, R] Runtime::fold_keyed(
  self : Runtime,
  projection : @strata.KeyedProjection[E, K, R],
  selection : @strata.Selection,
) -> Map[K, R] {
  let stored = read_all(self.store, selection, @strata.start)
  let decoded : Array[@strata.Recorded[E]] = self.codec.decode_all(stored)
  projection.fold(decoded.iter())
}

///|
/// Folds every source of a multi-source projection, merged in global order.
pub async fn[V] Runtime::fold_multi(
  self : Runtime,
  projection : @strata.MultiProjection[V],
) -> V {
  let stored = read_all(self.store, projection.selection(), @strata.start)
  let mut view = projection.initial()
  for event in stored {
    if is_system_event_type(event.event_type) ||
      self.codec.is_deprecated(event.event_type) {
      continue
    }
    let (event_type, data) = self.codec.upgrade(
      event_type=event.event_type,
      schema=event.schema,
      event.data,
    )
    if self.codec.is_deprecated(event_type) {
      continue
    }
    let upgraded = @strata.StoredEvent(
      id=event.id,
      position=event.position,
      stream=event.stream,
      version=event.version,
      event_type~,
      schema=self.codec.schema_version(),
      data~,
      tags=event.tags,
      meta=event.meta,
      recorded_at=event.recorded_at,
    )
    view = projection.apply_stored(view, upgraded)
  }
  view
}

///|
/// Folds one stream on read and returns the view with the stream version
/// (use it as an ETag).
pub async fn[E : @json.FromJson, V] Runtime::live(
  self : Runtime,
  projection : @strata.Projection[E, V],
  category~ : String,
  id~ : String,
  tenant? : String,
) -> (V, Int) {
  let stream = stream_id_of(category~, id~, tenant~)
  let stored = @store.EventStore::read_stream(self.store, stream)
  let decoded : Array[@strata.Recorded[E]] = self.codec.decode_all(stored)
  let view = projection.fold(decoded.map(r => r.event).iter())
  let version = match stored.last() {
    Some(e) => e.version
    None => 0
  }
  (view, version)
}

///|
/// A live feed of events matching a selection, after `from`.
pub async fn Runtime::subscribe(
  self : Runtime,
  selection : @strata.Selection,
  from~ : @strata.Position,
) -> &@store.Subscription {
  @store.EventStore::subscribe(self.store, selection, from~)
}

///|
/// The writer's state as it stood when `at` was recorded: a replay of
/// `at.stream` up to `at.version`. Deterministic; never uses a snapshot newer
/// than `at.version`; deprecated events are skipped.
pub async fn[C, E : @json.FromJson, S, N, X] Runtime::state_at(
  self : Runtime,
  decider : @strata.Decider[C, E, S, N],
  at : @strata.Recorded[X],
) -> S {
  let stored = @store.EventStore::read_stream(self.store, at.stream).filter(e => {
    e.version <= at.version
  })
  let decoded : Array[@strata.Recorded[E]] = self.codec.decode_all(stored)
  decider.replay(decoded.map(r => r.event).iter())
}

///|
/// Destroys the per-subject key of a stream: shredded fields become
/// `<redacted>`, a `$strata.forgotten` marker is appended, projectors are told.
pub async fn Runtime::forget(
  self : Runtime,
  category~ : String,
  id~ : String,
  tenant? : String,
) -> Unit {
  let stream = stream_id_of(category~, id~, tenant~)
  @store.KeyStore::destroy(self.keys, stream.0)
  let now = self.clock.now()
  let event_id = self.ids.reserve(now~).at(0)
  let marker = @strata.NewEvent(
    id=event_id,
    event_type="$strata.forgotten",
    schema=self.codec.schema_version(),
    data=Json::string("$strata.forgotten"),
    meta=@strata.Metadata(),
  )
  @store.EventStore::append(
    self.store,
    stream~,
    condition=@strata.Stream(stream, Any),
    events=[marker],
    recorded_at=now,
  )
  |> ignore
}

///|
/// Reads sealed metadata with a capability; the unseal itself is recorded.
pub async fn Runtime::unseal(
  self : Runtime,
  event : @strata.StoredEvent,
  capability~ : String,
) -> @strata.Metadata {
  try
    @store.KeyStore::unseal(self.keys, event.stream.0, capability~) |> ignore
  catch {
    @store.KeyMissing(_) => ()
    e => raise e
  }
  let now = self.clock.now()
  let event_id = self.ids.reserve(now~).at(0)
  let marker = @strata.NewEvent(
    id=event_id,
    event_type="$strata.unsealed",
    schema=self.codec.schema_version(),
    data=Json::string("$strata.unsealed"),
    meta=@strata.Metadata(),
  )
  @store.EventStore::append(
    self.store,
    stream=event.stream,
    condition=@strata.Stream(event.stream, Any),
    events=[marker],
    recorded_at=now,
  )
  |> ignore
  event.meta
}
