///|
/// A read model updated in the same transaction as the append.
pub struct InlineProjection[E] {
  priv table : String
  priv apply : (Json?, @strata.Recorded[E]) -> Json raise @strata.DecodeError
}

///|
/// Wraps a projection for inline use: the row in view table `into` is folded
/// forward on every append. The row key is the stream's entity id, prefixed
/// with `<tenant>/` when the stream has a tenant, so tenants never share rows.
pub fn[E, V : ToJson + @json.FromJson] inline(
  projection : @strata.Projection[E, V],
  into~ : String,
) -> InlineProjection[E] {
  {
    table: into,
    apply: (prev, recorded) => {
      let view : V = match prev {
        None => projection.initial()
        Some(json) =>
          json_of(
            json,
            event_type=recorded.event_type,
            position=Some(recorded.position),
          )
      }
      Json(projection.apply(view, recorded.event))
    },
  }
}

///|
/// The view table this projection writes to.
pub fn[E] InlineProjection::table(self : InlineProjection[E]) -> String {
  self.table
}

///|
/// Executes commands of one stream-based decider:
/// reserve ids, read the stream, fold, `decide` and `advise`, append with the
/// version that was read.
pub struct CommandHandler[C, E, S, N] {
  priv runtime : Runtime
  priv decider : @strata.Decider[C, E, S, N]
  priv retry : Retry
  priv snapshot : SnapshotPolicy
  priv inline : Array[InlineProjection[E]]
}

///|
/// Builds a command handler for a decider.
#warnings("-unused_trait_bound")
pub fn[C, E : ToJson + @json.FromJson, S : ToJson + @json.FromJson, N] Runtime::handler(
  self : Runtime,
  decider : @strata.Decider[C, E, S, N],
  retry? : Retry = Retry::none(),
  snapshot? : SnapshotPolicy = SnapshotPolicy::never(),
  inline? : Array[InlineProjection[E]] = [],
) -> CommandHandler[C, E, S, N] {
  { runtime: self, decider, retry, snapshot, inline, }
}

///|
/// The stream a given entity id maps to.
pub fn[C, E, S, N] CommandHandler::stream_id(
  self : CommandHandler[C, E, S, N],
  id : String,
  tenant? : String,
) -> @strata.StreamId {
  @strata.StreamId::of(category=self.decider.category(), id~, tenant?)
}

///|
/// Executes a command against stream `id`.
///
/// - Raises the decider's own rejection (a user `suberror`) unchanged.
/// - Raises `AppendConflict` when another writer got there first, unless
///   `retry` says to read again and re-decide.
/// - Raises `StreamTerminal` when the folded state is terminal.
/// - `expected` adds the client's expectation on top of the version read.
/// - The idempotency key (argument wins over `ctx.idempotency_key`) makes a
///   repeated command return the original outcome with `deduplicated = true`;
///   a different command under the same key raises `IdempotencyConflict`.
pub async fn[C, E : ToJson + @json.FromJson, S : ToJson + @json.FromJson, N] CommandHandler::execute(
  self : CommandHandler[C, E, S, N],
  id : String,
  cmd : C,
  ctx~ : @strata.Context,
  expected? : @strata.ExpectedVersion = Any,
  idempotency_key? : String,
) -> @strata.Outcome[E, N] {
  let key = match idempotency_key {
    Some(k) => Some(k)
    None => ctx.idempotency_key
  }
  let mut left = self.retry.max()
  while true {
    try {
      return CommandHandler::attempt(self, id, cmd, ctx~, expected~, key~)
    } catch {
      err =>
        if left > 0 && is_append_conflict(err) {
          left -= 1
          let ms = self.retry.backoff().to_millis().to_int()
          if ms > 0 {
            @async.sleep(ms)
          }
        } else {
          raise err
        }
    }
  } nobreak {
    CommandHandler::attempt(self, id, cmd, ctx~, expected~, key~)
  }
}

///|
async fn[C, E : ToJson + @json.FromJson, S : ToJson + @json.FromJson, N] CommandHandler::attempt(
  self : CommandHandler[C, E, S, N],
  id : String,
  cmd : C,
  ctx~ : @strata.Context,
  expected~ : @strata.ExpectedVersion,
  key~ : String?,
) -> @strata.Outcome[E, N] {
  let stream = stream_id_of(
    category=self.decider.category(),
    id~,
    tenant=ctx.tenant,
  )
  let (state, version) = match ctx.tenant {
    Some(t) => CommandHandler::load(self, id, tenant=t)
    None => CommandHandler::load(self, id)
  }
  check_expected(stream, expected, version)
  let store = self.runtime.store
  let codec = self.runtime.codec
  match key {
    Some(k) => {
      let existing = @store.EventStore::find_idempotent(store, key=k, stream~)
      if existing.is_empty() == false {
        let first = existing[0]
        let prefix = @store.EventStore::read_stream(store, stream).filter(e => {
          e.version < first.version
        })
        let before = codec.decode_all(prefix)
        let state_before = self.decider.replay(before.map(r => r.event).iter())
        let env = env_of(
          ctx,
          first.recorded_at,
          @strata.IdBatch::from(first.id),
        )
        let decision = self.decider.run(cmd, state_before, env) catch {
          _ => raise @strata.KeyReused(key=k, stream=Some(stream))
        }
        let produced = encode_events(
          codec,
          decision.events,
          e => self.decider.tags_of(e),
          env.ids,
          metadata_of(ctx, key),
        )
        if same_payloads(produced, existing) {
          return replay_outcome(codec, existing, decision.notices)
        } else {
          raise @strata.KeyReused(key=k, stream=Some(stream))
        }
      }
    }
    None => ()
  }
  if self.decider.is_terminal(state) {
    raise Terminal(stream~)
  }
  let now = self.runtime.clock.now()
  let ids = self.runtime.ids.reserve(now~)
  let env = env_of(ctx, now, ids)
  let decision = self.decider.run(cmd, state, env)
  if decision.events.is_empty() {
    let position = match last_stream_event(store, stream) {
      Some(e) => e.position
      None => @strata.start
    }
    return @strata.Outcome(
      events=[],
      notices=decision.notices,
      version~,
      position~,
    )
  }
  let meta = metadata_of(ctx, key)
  let events = encode_events(
    codec,
    decision.events,
    e => self.decider.tags_of(e),
    ids,
    meta,
  )
  let mut recorded_version = version
  let inline_writes : Array[@store.ViewWrite] = []
  let row_key = view_row_key(id, ctx.tenant)
  for proj in self.inline {
    let mut prev = @store.ViewStore::get(
      @store.EventStore::views(store),
      table=proj.table,
      key=row_key,
    )
    recorded_version = version
    let mut i = 0
    for event in decision.events {
      recorded_version += 1
      let encoded = codec.encode(event)
      let recorded = @strata.Recorded(
        id=ids.at(i),
        position=@strata.start,
        stream~,
        version=recorded_version,
        event_type=encoded.event_type,
        event~,
        tags=self.decider.tags_of(event),
        recorded_at=now,
        meta~,
      )
      prev = Some((proj.apply)(prev, recorded))
      i += 1
    }
    inline_writes.push(
      @store.ViewWrite(table=proj.table, key=row_key, value=prev),
    )
  }
  let result = @store.EventStore::append(
    store,
    stream~,
    condition=@strata.Stream(stream, Exact(version)),
    events~,
    recorded_at=now,
    inline=inline_writes,
  )
  let interval = self.snapshot.interval()
  if interval > 0 && result.version % interval == 0 {
    let new_state = self.decider.replay_from(state, decision.events.iter())
    @store.EventStore::save_snapshot(
      store,
      @store.Stream(stream, version=self.snapshot.version()),
      @store.SnapshotRecord(
        position=result.position,
        version=result.version,
        state=Json(new_state),
      ),
    )
  }
  @strata.Outcome(
    events=codec.decode_all(result.events),
    notices=decision.notices,
    version=result.version,
    position=result.position,
  )
}

///|
/// The current state and version of a stream (snapshot plus tail).
pub async fn[C, E : @json.FromJson, S : @json.FromJson, N] CommandHandler::load(
  self : CommandHandler[C, E, S, N],
  id : String,
  tenant? : String,
) -> (S, Int) {
  let stream = stream_id_of(category=self.decider.category(), id~, tenant~)
  let store = self.runtime.store
  let codec = self.runtime.codec
  let interval = self.snapshot.interval()
  if interval > 0 {
    match
      @store.EventStore::load_snapshot(
        store,
        @store.Stream(stream, version=self.snapshot.version()),
      ) {
      Some(record) => {
        let snap : S = json_of(
          record.state,
          event_type="",
          position=Some(record.position),
        )
        let tail = @store.EventStore::read_stream(
          store,
          stream,
          from_version=record.version + 1,
        )
        let decoded = codec.decode_all(tail)
        let last = match tail.last() {
          Some(e) => e.version
          None => record.version
        }
        return (
          self.decider.replay_from(snap, decoded.map(r => r.event).iter()),
          last,
        )
      }
      None => ()
    }
  }
  let stored = @store.EventStore::read_stream(store, stream)
  let decoded = codec.decode_all(stored)
  let version = match stored.last() {
    Some(e) => e.version
    None => 0
  }
  (self.decider.replay(decoded.map(r => r.event).iter()), version)
}

///|
/// Executes commands of a DCB decider: reserve ids, note the head, read the
/// scope, fold within the scope, `decide` and `advise`, append under
/// `Dcb(selection, after=head)`.
pub struct DcbHandler[C, E, S, N] {
  priv runtime : Runtime
  priv decider : @strata.DcbDecider[C, E, S, N]
  priv retry : Retry
  priv snapshot : SnapshotPolicy
}

///|
/// Builds a DCB handler.
#warnings("-unused_trait_bound")
pub fn[C, E : ToJson + @json.FromJson, S : ToJson + @json.FromJson, N] Runtime::dcb_handler(
  self : Runtime,
  decider : @strata.DcbDecider[C, E, S, N],
  retry? : Retry = Retry::none(),
  snapshot? : SnapshotPolicy = SnapshotPolicy::never(),
) -> DcbHandler[C, E, S, N] {
  { runtime: self, decider, retry, snapshot, }
}

///|
/// Executes a command. Raises the decider's rejection, `AppendConflict`
/// (`BoundaryConflict`) or `IdempotencyConflict`.
pub async fn[C, E : ToJson + @json.FromJson, S : ToJson + @json.FromJson, N] DcbHandler::execute(
  self : DcbHandler[C, E, S, N],
  cmd : C,
  ctx~ : @strata.Context,
  idempotency_key? : String,
) -> @strata.Outcome[E, N] {
  let key = match idempotency_key {
    Some(k) => Some(k)
    None => ctx.idempotency_key
  }
  let mut left = self.retry.max()
  while true {
    try {
      return DcbHandler::attempt(self, cmd, ctx~, key~)
    } catch {
      err =>
        if left > 0 && is_append_conflict(err) {
          left -= 1
          let ms = self.retry.backoff().to_millis().to_int()
          if ms > 0 {
            @async.sleep(ms)
          }
        } else {
          raise err
        }
    }
  } nobreak {
    DcbHandler::attempt(self, cmd, ctx~, key~)
  }
}

///|
async fn[C, E : ToJson + @json.FromJson, S : ToJson + @json.FromJson, N] DcbHandler::attempt(
  self : DcbHandler[C, E, S, N],
  cmd : C,
  ctx~ : @strata.Context,
  key~ : String?,
) -> @strata.Outcome[E, N] {
  let stream = stream_id_of(
    category=self.decider.category(),
    id=self.decider.stream_of(cmd),
    tenant=ctx.tenant,
  )
  let store = self.runtime.store
  let codec = self.runtime.codec
  let scope = self.decider.scope_of(cmd)
  let head = @store.EventStore::head(store)
  let state = if self.snapshot.interval() > 0 {
    match
      @store.EventStore::load_snapshot(
        store,
        @store.Dcb(scope.selection(), version=self.snapshot.version()),
      ) {
      Some(record) => {
        let snap : S = json_of(
          record.state,
          event_type="",
          position=Some(record.position),
        )
        let tail = read_all(store, scope.selection(), record.position)
        let decoded = codec.decode_all(tail)
        self.decider.replay_from(scope, snap, decoded.map(r => r.event).iter())
      }
      None => {
        let (s, _) = DcbHandler::fold_scope(self, cmd)
        s
      }
    }
  } else {
    let (s, _) = DcbHandler::fold_scope(self, cmd)
    s
  }
  match key {
    Some(k) => {
      let existing = @store.EventStore::find_idempotent(store, key=k, stream~)
      if existing.is_empty() == false {
        let first = existing[0]
        let env = env_of(
          ctx,
          first.recorded_at,
          @strata.IdBatch::from(first.id),
        )
        let before = @store.EventStore::read(
          store,
          scope.selection(),
          after=@strata.start,
        ).filter(e => e.position.0 < first.position.0)
        let decoded = codec.decode_all(before)
        let state_before = self.decider.replay(
          scope,
          decoded.map(r => r.event).iter(),
        )
        let decision = self.decider.run(cmd, state_before, env, scope) catch {
          _ => raise @strata.KeyReused(key=k, stream=Some(stream))
        }
        let produced = encode_events(
          codec,
          decision.events,
          e => self.decider.tags_of(e),
          env.ids,
          metadata_of(ctx, key),
        )
        if same_payloads(produced, existing) {
          return replay_outcome(codec, existing, decision.notices)
        } else {
          raise @strata.KeyReused(key=k, stream=Some(stream))
        }
      }
    }
    None => ()
  }
  let now = self.runtime.clock.now()
  let ids = self.runtime.ids.reserve(now~)
  let env = env_of(ctx, now, ids)
  let decision = self.decider.run(cmd, state, env, scope)
  if decision.events.is_empty() {
    return @strata.Outcome(
      events=[],
      notices=decision.notices,
      version=0,
      position=head,
    )
  }
  let events = encode_events(
    codec,
    decision.events,
    e => self.decider.tags_of(e),
    ids,
    metadata_of(ctx, key),
  )
  let result = @store.EventStore::append(
    store,
    stream~,
    condition=@strata.Dcb(selection=scope.selection(), after=Some(head)),
    events~,
    recorded_at=now,
  )
  let interval = self.snapshot.interval()
  if interval > 0 && result.version % interval == 0 {
    let new_state = self.decider.replay_from(
      scope,
      state,
      decision.events.iter(),
    )
    @store.EventStore::save_snapshot(
      store,
      @store.Dcb(scope.selection(), version=self.snapshot.version()),
      @store.SnapshotRecord(
        position=result.position,
        version=result.version,
        state=Json(new_state),
      ),
    )
  }
  @strata.Outcome(
    events=codec.decode_all(result.events),
    notices=decision.notices,
    version=result.version,
    position=result.position,
  )
}

///|
async fn[C, E : @json.FromJson, S, N] DcbHandler::fold_scope(
  self : DcbHandler[C, E, S, N],
  cmd : C,
) -> (S, @strata.Position) {
  let store = self.runtime.store
  let codec = self.runtime.codec
  let scope = self.decider.scope_of(cmd)
  let head = @store.EventStore::head(store)
  let stored = read_all(store, scope.selection(), @strata.start)
  let decoded = codec.decode_all(stored)
  (self.decider.replay(scope, decoded.map(r => r.event).iter()), head)
}

///|
/// The state a command would decide over (its scope folded now).
pub async fn[C, E : @json.FromJson, S, N] DcbHandler::load(
  self : DcbHandler[C, E, S, N],
  cmd : C,
) -> (S, @strata.Position) {
  DcbHandler::fold_scope(self, cmd)
}
