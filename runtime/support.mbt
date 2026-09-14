///|
/// Raised when a command targets a stream whose state is terminal.
pub(all) suberror StreamTerminal {
  Terminal(stream~ : @strata.StreamId)
} derive(Eq, Debug)

///|
/// Raised by `Projector::wait_for` when the position is not reached in time.
pub(all) suberror WaitTimeout {
  WaitTimeout(waiting_for~ : @strata.Position, reached~ : @strata.Position)
} derive(Eq, Debug)

///|
/// The source of `Env.now`. Injectable so replays and tests are deterministic.
pub struct Clock {
  priv now : () -> @strata.Instant
  priv advance : (@strata.Duration) -> Unit
}

///|
/// The wall clock of the host.
pub fn Clock::system() -> Clock {
  { now: () => @strata.Instant(@async.now()), advance: _ => (), }
}

///|
/// A clock that always returns `at`.
pub fn Clock::fixed(at : @strata.Instant) -> Clock {
  { now: () => at, advance: _ => (), }
}

///|
/// `Clock::fixed` from an ISO-8601 string.
pub fn Clock::parse_fixed(
  iso8601 : String,
) -> Clock raise @strata.InvalidInstant {
  Clock::fixed(@strata.Instant::parse(iso8601))
}

///|
/// A clock that starts at `at` and moves only when `advance` is called.
pub fn Clock::manual(at : @strata.Instant) -> Clock {
  let current : Ref[@strata.Instant] = { val: at, }
  { now: () => current.val, advance: by => current.val = current.val.add(by), }
}

///|
/// The current instant.
pub fn Clock::now(self : Clock) -> @strata.Instant {
  (self.now)()
}

///|
/// Moves a manual clock forward (no effect on other clocks).
pub fn Clock::advance(self : Clock, by : @strata.Duration) -> Unit {
  (self.advance)(by)
}

///|
/// Reserves the event ids for one decision.
pub struct IdGenerator {
  priv reserve : (@strata.Instant) -> @strata.IdBatch
}

///|
/// Monotonic ULIDs (production).
pub fn IdGenerator::ulid() -> IdGenerator {
  let last_batch : Ref[@strata.IdBatch?] = { val: None, }
  let last_issued : Ref[@strata.EventId?] = { val: None, }
  {
    reserve: now => {
      match last_batch.val {
        Some(batch) =>
          if batch.high_water() >= 0 {
            last_issued.val = Some(batch.at(batch.high_water()))
          }
        None => ()
      }
      let random = @env.rand(10).unwrap_or(Bytes::make(10, b'\x01'))
      let mut id = @strata.EventId::ulid(timestamp=now, random~)
      match last_issued.val {
        Some(used) => if id <= used { id = used.increment() }
        None => ()
      }
      let batch = @strata.IdBatch::from(id)
      last_batch.val = Some(batch)
      batch
    },
  }
}

///|
/// `evt-0001`, `evt-0002`, ... across decisions (tests).
pub fn IdGenerator::sequential(prefix? : String = "evt-") -> IdGenerator {
  let next_start : Ref[Int] = { val: 0, }
  let last : Ref[@strata.IdBatch?] = { val: None, }
  {
    reserve: _now => {
      match last.val {
        Some(batch) => next_start.val = next_start.val + batch.high_water() + 1
        None => ()
      }
      let batch = @strata.IdBatch::deterministic(prefix~).offset(next_start.val)
      last.val = Some(batch)
      batch
    },
  }
}

///|
/// A batch for a decision taken at `now`.
pub fn IdGenerator::reserve(
  self : IdGenerator,
  now~ : @strata.Instant,
) -> @strata.IdBatch {
  (self.reserve)(now)
}

///|
/// When to re-run a command after an `AppendConflict`. Domain errors are never
/// retried: the check is `error is AppendConflict`.
pub struct Retry {
  priv max : Int
  priv backoff : @strata.Duration
}

///|
/// Never retry.
pub fn Retry::none() -> Retry {
  { max: 0, backoff: @strata.Duration::millis(0), }
}

///|
/// Retry up to `max` times on conflict, sleeping `backoff` between attempts.
pub fn Retry::on_conflict(
  max~ : Int,
  backoff? : @strata.Duration = @strata.Duration::millis(0),
) -> Retry {
  { max, backoff, }
}

///|
/// The maximum number of retries.
pub fn Retry::max(self : Retry) -> Int {
  self.max
}

///|
/// The pause between attempts.
pub fn Retry::backoff(self : Retry) -> @strata.Duration {
  self.backoff
}

///|
/// When to write snapshots. Snapshots are a cache, never the truth; `version`
/// stamps the state format so one number change invalidates them.
pub struct SnapshotPolicy {
  priv every : Int
  priv version : Int
}

///|
/// Snapshot every `every` events.
pub fn SnapshotPolicy::every(every : Int, version~ : Int) -> SnapshotPolicy {
  { every, version, }
}

///|
/// Never snapshot.
pub fn SnapshotPolicy::never() -> SnapshotPolicy {
  { every: 0, version: 0, }
}

///|
/// The snapshot interval in events (0 = never).
pub fn SnapshotPolicy::interval(self : SnapshotPolicy) -> Int {
  self.every
}

///|
/// The snapshot format version.
pub fn SnapshotPolicy::version(self : SnapshotPolicy) -> Int {
  self.version
}

///|
/// A page of stored events plus the codec that can decode them.
pub struct Page {
  /// The events, in global position order.
  events : Array[@strata.StoredEvent]
  /// The cursor for the next page, or `None` at the end.
  next : @strata.Position?
  priv codec : @codec.JsonCodec
}

///|
/// Builds a page.
pub fn Page::Page(
  events~ : Array[@strata.StoredEvent],
  next~ : @strata.Position?,
  codec~ : @codec.JsonCodec,
) -> Page {
  { events, next, codec, }
}

///|
/// Decodes the page where the event type is known; deprecated types are
/// skipped. Usage: `let h : Array[Recorded[LedgerEvent]] = page.decode()`.
pub fn[E : @json.FromJson] Page::decode(
  self : Page,
) -> Array[@strata.Recorded[E]] raise @strata.DecodeError {
  self.codec.decode_all(self.events)
}

///|
fn is_system_event_type(event_type : String) -> Bool {
  match event_type.get_char(0) {
    Some('$') => true
    _ => false
  }
}

///|
fn view_row_key(id : String, tenant : String?) -> String {
  match tenant {
    Some(t) => "\{t}/\{id}"
    None => id
  }
}

///|
fn stream_id_of(
  category~ : String,
  id~ : String,
  tenant~ : String?,
) -> @strata.StreamId {
  match tenant {
    Some(t) => @strata.StreamId::of(category~, id~, tenant=t)
    None => @strata.StreamId::of(category~, id~)
  }
}

///|
fn env_of(
  ctx : @strata.Context,
  now : @strata.Instant,
  ids : @strata.IdBatch,
) -> @strata.Env {
  match ctx.tenant {
    Some(t) =>
      @strata.Env(actor=ctx.actor, now~, tenant=t, ids~, extra=ctx.extra)
    None => @strata.Env(actor=ctx.actor, now~, ids~, extra=ctx.extra)
  }
}

///|
fn metadata_of(ctx : @strata.Context, key : String?) -> @strata.Metadata {
  let ctx = match key {
    Some(k) => ctx.with_idempotency_key(k)
    None => ctx
  }
  ctx.to_metadata()
}

///|
fn check_expected(
  stream : @strata.StreamId,
  expected : @strata.ExpectedVersion,
  actual : Int,
) -> Unit raise @strata.AppendConflict {
  match expected {
    Any => ()
    NoStream =>
      if actual != 0 {
        raise @strata.StreamConflict(stream~, expected=NoStream, actual~)
      }
    Exact(n) =>
      if actual != n {
        raise @strata.StreamConflict(stream~, expected=Exact(n), actual~)
      }
  }
}

///|
fn is_append_conflict(err : Error) -> Bool {
  match err {
    @strata.StreamConflict(..) | @strata.BoundaryConflict(..) => true
    _ => false
  }
}

///|
fn[T : @json.FromJson] json_of(
  json : Json,
  event_type~ : String,
  position~ : @strata.Position?,
) -> T raise @strata.DecodeError {
  @json.from_json(json) catch {
    @json.JsonDecodeError((_, reason)) =>
      raise @strata.DecodeError(event_type~, position~, reason~)
  }
}

///|
async fn read_all(
  store : &@store.EventStore,
  selection : @strata.Selection,
  after : @strata.Position,
) -> Array[@strata.StoredEvent] {
  let out : Array[@strata.StoredEvent] = []
  let mut cursor = after
  while true {
    let page = @store.EventStore::read(
      store,
      selection,
      after=cursor,
      limit=100,
    )
    if page.is_empty() {
      break
    }
    out.append(page[:])
    cursor = page[page.length() - 1].position
    if page.length() < 100 {
      break
    }
  }
  out
}

///|
async fn last_stream_event(
  store : &@store.EventStore,
  stream : @strata.StreamId,
) -> @strata.StoredEvent? {
  @store.EventStore::read_stream(store, stream).last()
}

///|
fn same_payloads(
  produced : Array[@strata.NewEvent],
  stored : Array[@strata.StoredEvent],
) -> Bool {
  if produced.length() != stored.length() {
    return false
  }
  for i in 0..<produced.length() {
    if produced[i].event_type != stored[i].event_type ||
      produced[i].data != stored[i].data {
      return false
    }
  }
  true
}

///|
fn[E : ToJson] encode_events(
  codec : @codec.JsonCodec,
  events : Array[E],
  tags_of : (E) -> Array[@strata.Tag],
  ids : @strata.IdBatch,
  meta : @strata.Metadata,
) -> Array[@strata.NewEvent] raise {
  let out : Array[@strata.NewEvent] = []
  let mut i = 0
  for event in events {
    let encoded = codec.encode(event)
    out.push(
      @strata.NewEvent(
        id=ids.at(i),
        event_type=encoded.event_type,
        schema=encoded.schema,
        data=encoded.data,
        tags=tags_of(event),
        meta~,
      ),
    )
    i += 1
  }
  out
}

///|
fn[E : @json.FromJson, N] replay_outcome(
  codec : @codec.JsonCodec,
  stored : Array[@strata.StoredEvent],
  notices : Array[N],
) -> @strata.Outcome[E, N] raise @strata.DecodeError {
  let last = stored[stored.length() - 1]
  @strata.Outcome(
    events=codec.decode_all(stored),
    notices~,
    version=last.version,
    position=last.position,
    deduplicated=true,
  )
}
