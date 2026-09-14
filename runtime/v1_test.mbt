///|
/// A store wrapper with hooks, for injecting conflicts and concurrent writes.
priv struct HookedStore {
  inner : @store.MemoryStore
  before_append : Ref[(() -> Unit raise)?]
  on_read : Ref[(async () -> Unit)?]
  appends : Ref[Int]
}

///|
fn hooked() -> HookedStore {
  {
    inner: @store.MemoryStore(),
    before_append: { val: None, },
    on_read: { val: None, },
    appends: { val: 0, },
  }
}

///|
impl @store.EventStore for HookedStore with fn append(
  self,
  stream~,
  condition~,
  events~,
  recorded_at~,
  inline?,
) {
  self.appends.val += 1
  match self.before_append.val {
    Some(hook) => {
      self.before_append.val = None
      hook()
    }
    None => ()
  }
  self.inner.append(stream~, condition~, events~, recorded_at~, inline?)
}

///|
impl @store.EventStore for HookedStore with fn read(
  self,
  selection,
  after?,
  limit?,
) {
  match self.on_read.val {
    Some(hook) => {
      self.on_read.val = None
      hook()
    }
    None => ()
  }
  self.inner.read(selection, after?, limit?)
}

///|
impl @store.EventStore for HookedStore with fn read_stream(
  self,
  stream,
  from_version?,
) {
  self.inner.read_stream(stream, from_version?)
}

///|
impl @store.EventStore for HookedStore with fn head(self) {
  self.inner.head()
}

///|
impl @store.EventStore for HookedStore with fn find_idempotent(
  self,
  key~,
  stream?,
) {
  self.inner.find_idempotent(key~, stream?)
}

///|
impl @store.EventStore for HookedStore with fn subscribe(self, selection, from~) {
  self.inner.subscribe(selection, from~)
}

///|
impl @store.EventStore for HookedStore with fn load_checkpoint(self, name) {
  self.inner.load_checkpoint(name)
}

///|
impl @store.EventStore for HookedStore with fn save_checkpoint(
  self,
  name,
  position,
) {
  self.inner.save_checkpoint(name, position)
}

///|
impl @store.EventStore for HookedStore with fn load_snapshot(self, key) {
  self.inner.load_snapshot(key)
}

///|
impl @store.EventStore for HookedStore with fn save_snapshot(self, key, record) {
  self.inner.save_snapshot(key, record)
}

///|
impl @store.EventStore for HookedStore with fn views(self) {
  self.inner.views()
}

///|
fn runtime_over(store : HookedStore) -> @runtime.Runtime {
  @runtime.Runtime(
    store,
    clock=@runtime.Clock::fixed(@strata.Instant(0)),
    ids=@runtime.IdGenerator::sequential(),
  )
}

///|
/// A decider that emits two events per command.
let pair : @strata.Decider[Int, Ev, Int, Unit] = @strata.Decider(
  category="pair",
  initial=0,
  decide=(n, _s, _env) => [Added(n), Added(n)],
  evolve=(s, e) => {
    match e {
      Added(n) => s + n
    }
  },
)

///|
priv enum TallyCmd {
  Bump(code~ : String, by~ : Int)
}

///|
priv enum TallyEv {
  Bumped(code~ : String, by~ : Int)
} derive(ToJson, FromJson)

///|
fn tally_tag(code : String) -> @strata.Tag {
  @strata.Tag("code:\{code}")
}

///|
/// A DCB decider over one tag per command.
let tally : @strata.DcbDecider[TallyCmd, TallyEv, Int, Unit] = @strata.DcbDecider(
  category="tally",
  stream=cmd => {
    match cmd {
      Bump(code~, ..) => code
    }
  },
  scope=cmd => {
    match cmd {
      Bump(code~, ..) => @strata.Selection::tags([tally_tag(code)])
    }
  },
  tags=e => {
    match e {
      Bumped(code~, ..) => [tally_tag(code)]
    }
  },
  initial=0,
  decide=(cmd, _s, _env, _scope) => {
    match cmd {
      Bump(code~, by~) => [Bumped(code~, by~)]
    }
  },
  evolve=(s, e, scope) => {
    match e {
      Bumped(code~, by~) => if scope.owns(tally_tag(code)) { s + by } else { s }
    }
  },
)

///|
async test "event ids never overlap across decisions" {
  let rt = @testing.runtime()
  let h = rt.handler(pair)
  let a = h.execute("p1", 1, ctx~)
  let b = h.execute("p1", 2, ctx~)
  debug_inspect(
    a.events.map(r => r.id) + b.events.map(r => r.id),
    content=(
      #|[
      #|  EventId("evt-0001"),
      #|  EventId("evt-0002"),
      #|  EventId("evt-0003"),
      #|  EventId("evt-0004"),
      #|]
    ),
  )
}

///|
test "id generators start the next batch after the ids actually taken" {
  let seq = @runtime.IdGenerator::sequential()
  let first = seq.reserve(now=@strata.Instant(0))
  first.at(0) |> ignore
  first.at(1) |> ignore
  inspect(seq.reserve(now=@strata.Instant(0)).at(0), content="evt-0003")
  let ulid = @runtime.IdGenerator::ulid()
  let batch = ulid.reserve(now=@strata.Instant(1_000))
  let used = batch.at(1)
  assert_true(ulid.reserve(now=@strata.Instant(1_000)).at(0) > used)
  // an earlier timestamp never produces a smaller id than one already handed out
  assert_true(ulid.reserve(now=@strata.Instant(500)).at(0) > used)
}

///|
async test "retry re-reads and re-decides after a conflict, then succeeds" {
  let store = hooked()
  let stream = @strata.StreamId("counter-c1")
  store.before_append.val = Some(() => {
    raise @strata.StreamConflict(stream~, expected=Exact(0), actual=1)
  })
  let rt = runtime_over(store)
  let h = rt.handler(counter, retry=@runtime.Retry::on_conflict(max=2))
  let out = h.execute("c1", Add(4), ctx~)
  inspect(out.version, content="1")
  inspect(store.appends.val, content="2")
  // without retry the same conflict surfaces
  store.before_append.val = Some(() => {
    raise @strata.StreamConflict(stream~, expected=Exact(0), actual=1)
  })
  let plain = rt.handler(counter)
  let raised = try {
    plain.execute("c1", Add(1), ctx~) |> ignore
    false
  } catch {
    @strata.StreamConflict(..) => true
    e => raise e
  }
  assert_true(raised)
}

///|
async test "snapshots are written by the policy and used on load" {
  let rt = @testing.runtime()
  let h = rt.handler(
    counter,
    snapshot=@runtime.SnapshotPolicy::every(2, version=3),
  )
  h.execute("c1", Add(1), ctx~) |> ignore
  h.execute("c1", Add(2), ctx~) |> ignore
  h.execute("c1", Add(3), ctx~) |> ignore
  let snapshot = rt
    .store()
    .load_snapshot(Stream(@strata.StreamId("counter-c1"), version=3))
  assert_true(snapshot is Some(_))
  let record = snapshot.unwrap()
  assert_true(record.version >= 2 && record.version <= 3)
  debug_inspect(h.load("c1"), content="(6, 3)")
  // a different snapshot version is a different key
  debug_inspect(
    rt.store().load_snapshot(Stream(@strata.StreamId("counter-c1"), version=4)),
    content="None",
  )
}

///|
async test "the DCB boundary holds on the snapshot path" {
  let store = hooked()
  let rt = runtime_over(store)
  let codes = rt.dcb_handler(
    tally,
    snapshot=@runtime.SnapshotPolicy::every(1, version=1),
  )
  codes.execute(Bump(code="X", by=1), ctx~) |> ignore
  // A competing in-scope write lands while the handler reads its tail.
  let inner = store.inner
  store.on_read.val = Some(() => {
    let stream = @strata.StreamId("tally-X")
    inner.append(
      stream~,
      condition=Stream(stream, Any),
      events=[
        @strata.NewEvent(
          id=@strata.EventId("race"),
          event_type="Bumped",
          schema=1,
          data=Json(TallyEv::Bumped(code="X", by=100)),
          tags=[tally_tag("X")],
          meta=@strata.Metadata(),
        ),
      ],
      recorded_at=@strata.Instant(0),
    )
    |> ignore
  })
  let conflicted = try {
    codes.execute(Bump(code="X", by=2), ctx~) |> ignore
    false
  } catch {
    @strata.BoundaryConflict(..) => true
    e => raise e
  }
  assert_true(conflicted)
}

///|
async test "forget keeps the stream readable and writable" {
  let rt = @testing.runtime()
  let h = rt.handler(counter)
  h.execute("c1", Add(1), ctx~) |> ignore
  rt.forget(category="counter", id="c1")
  let (state, _) = h.load("c1")
  inspect(state, content="1")
  let (view, _) = rt.live(total, category="counter", id="c1")
  inspect(view, content="1")
  let page = rt.read(@strata.Selection::stream(@strata.StreamId("counter-c1")))
  let events : Array[@strata.Recorded[Ev]] = page.decode()
  inspect(events.length(), content="1")
  let (after, _) = {
    h.execute("c1", Add(2), ctx~) |> ignore
    h.load("c1")
  }
  inspect(after, content="3")
}

///|
async test "unseal returns the metadata and leaves a record in the stream" {
  let rt = @testing.runtime()
  let h = rt.handler(counter)
  h.execute("c1", Add(1), ctx~) |> ignore
  let stored = rt.store().read_stream(@strata.StreamId("counter-c1"))[0]
  let meta = rt.unseal(stored, capability="auditor")
  debug_inspect(meta.actor, content="Some(Actor(\"user:test\"))")
  let log = rt.store().read_stream(@strata.StreamId("counter-c1"))
  inspect(log.length(), content="2")
  inspect(log[1].event_type, content="$strata.unsealed")
  let (state, _) = h.load("c1")
  inspect(state, content="1")
}

///|
async test "inline projections and reads keep tenants apart" {
  let rt = @testing.runtime()
  let h = rt.handler(counter, inline=[@runtime.inline(total, into="totals")])
  let t1 = @strata.Context(actor=@strata.Actor("user:test"), tenant="t1")
  let t2 = @strata.Context(actor=@strata.Actor("user:test"), tenant="t2")
  let out = h.execute("c1", Add(1), ctx=t1)
  inspect(
    out.events[0].stream,
    content="t1/account-c1".replace(old="account", new="counter"),
  )
  h.execute("c1", Add(5), ctx=t2) |> ignore
  debug_inspect(
    rt.views().get(table="totals", key="t1/c1"),
    content="Some(Number(1))",
  )
  debug_inspect(
    rt.views().get(table="totals", key="t2/c1"),
    content="Some(Number(5))",
  )
  debug_inspect(rt.views().get(table="totals", key="c1"), content="None")
  inspect(
    rt.read(@strata.Selection::category("counter", tenant="t1")).events.length(),
    content="1",
  )
  inspect(
    rt.read(@strata.Selection::category("counter")).events.length(),
    content="2",
  )
  debug_inspect(
    rt.live(total, category="counter", id="c1", tenant="t2"),
    content="(5, 1)",
  )
  debug_inspect(h.load("c1", tenant="t1"), content="(1, 1)")
}

///|
async test "reactors retry a bounded number of times, then dead-letter" {
  let rt = @testing.runtime()
  let h = rt.handler(counter)
  let attempts : Ref[Int] = { val: 0, }
  let dead : Array[String] = []
  let reactor = rt.reactor(
    "bad",
    source=@strata.Selection::category("counter"),
    retry=Immediate,
    max_retry=2,
    on_failure=(stored, _err) => dead.push(stored.id.0),
    (_r : @strata.Recorded[Ev]) => {
      attempts.val += 1
      @async.pause() // yield so a timeout can interrupt an unbounded retry loop
      fail("handler always fails")
    },
  )
  h.execute("c1", Add(1), ctx~) |> ignore
  // bounded: an unbounded retry loop would hang here, so cap the wait
  @async.with_timeout(2_000, () => reactor.catch_up())
  inspect(attempts.val, content="3")
  debug_inspect(dead, content="[\"evt-0001\"]")
  inspect(reactor.position(), content="1")
  // without a dead-letter hook the failure is raised
  let loud = rt.reactor(
    "loud",
    source=@strata.Selection::category("counter"),
    retry=Immediate,
    max_retry=0,
    (_r : @strata.Recorded[Ev]) => {
      @async.pause()
      fail("handler always fails")
    },
  )
  let raised = try {
    @async.with_timeout(2_000, () => loud.catch_up())
    false
  } catch {
    Failure(_) => true
    e => raise e
  }
  assert_true(raised)
  inspect(loud.position(), content="0")
}

///|
async test "projectors rebuild into a fresh table and fold_multi agrees" {
  let rt = @testing.runtime()
  let h = rt.handler(counter)
  let view = @strata.MultiProjection(initial=0)
  view.source(@strata.Selection::category("counter"), (
    v,
    r : @strata.Recorded[Ev],
  ) => {
    match r.event {
      Added(n) => v + n
    }
  })
  h.execute("c1", Add(2), ctx~) |> ignore
  h.execute("c2", Add(3), ctx~) |> ignore
  let projector = rt.projector("totals", view, into="views")
  projector.catch_up()
  debug_inspect(
    rt.views().get(table="views", key="view"),
    content="Some(Number(5))",
  )
  rt.views().put(table="views", key="view", 999)
  projector.rebuild()
  debug_inspect(
    rt.views().get(table="views", key="view"),
    content="Some(Number(5))",
  )
  inspect(rt.fold_multi(view), content="5")
  debug_inspect(
    rt.store().load_checkpoint("totals"),
    content="Some(Position(2))",
  )
}

///|
async test "reading nothing" {
  let rt = @testing.runtime()
  let h = rt.handler(counter)
  h.execute("c1", Add(2), ctx~) |> ignore
  inspect(rt.read(@strata.Selection::none()).events.length(), content="0")
}
