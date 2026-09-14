///|
// #region counter
#warnings("-unused_value")
priv enum Cmd {
  Add(Int)
} derive(Eq, Debug)

///|
#warnings("-unused_value")
priv enum Ev {
  Added(Int)
} derive(Eq, Debug, ToJson, FromJson)

///|
let counter : @strata.Decider[Cmd, Ev, Int, Unit] = @strata.Decider(
  category="counter",
  initial=0,
  decide=(cmd, _s, _env) => {
    match cmd {
      Add(n) => [Added(n)]
    }
  },
  evolve=(s, e) => {
    match e {
      Added(n) => s + n
    }
  },
)

///|
let total : @strata.Projection[Ev, Int] = @strata.Projection(initial=0, apply=(
  v,
  e,
) => {
  match e {
    Added(n) => v + n
  }
})

///|
let ctx : @strata.Context = @strata.Context(actor=@strata.Actor("user:test"))
// #endregion counter

///|
test "clocks" {
  let fixed = @runtime.Clock::parse_fixed("2026-09-13T00:00:00Z")
  inspect(fixed.now().to_iso8601(), content="2026-09-13T00:00:00.000Z")
  fixed.advance(@strata.Duration::seconds(1))
  inspect(fixed.now().to_iso8601(), content="2026-09-13T00:00:00.000Z")
  let manual = @runtime.Clock::manual(@strata.Instant(0))
  manual.advance(@strata.Duration::seconds(2))
  inspect(manual.now(), content="1970-01-01T00:00:02.000Z")
  assert_true(
    @runtime.Clock::system().now() > @strata.Instant(1_600_000_000_000L),
  )
}

///|
test "id generators" {
  let seq = @runtime.IdGenerator::sequential()
  inspect(seq.reserve(now=@strata.Instant(0)).at(0), content="evt-0001")
  inspect(seq.reserve(now=@strata.Instant(0)).at(1), content="evt-0003")
  let ulid = @runtime.IdGenerator::ulid()
  let a = ulid.reserve(now=@strata.Instant(1_000)).at(0)
  let b = ulid.reserve(now=@strata.Instant(1_000)).at(0)
  assert_true(a.is_ulid())
  assert_true(b > a)
}

///|
test "retry and snapshot policies" {
  inspect(@runtime.Retry::on_conflict(max=3).max(), content="3")
  inspect(@runtime.Retry::none().max(), content="0")
  inspect(
    @runtime.SnapshotPolicy::every(200, version=3).interval(),
    content="200",
  )
  inspect(@runtime.SnapshotPolicy::never().interval(), content="0")
}

///|
async test "read pages in global order and decodes" {
  let rt = @testing.runtime()
  let h = rt.handler(counter)
  h.execute("c1", Add(1), ctx~) |> ignore
  h.execute("c2", Add(2), ctx~) |> ignore
  h.execute("c1", Add(3), ctx~) |> ignore
  let page = rt.read(@strata.Selection::category("counter"), limit=2)
  inspect(page.events.length(), content="2")
  debug_inspect(page.next, content="Some(Position(2))")
  let rest = rt.read(
    @strata.Selection::category("counter"),
    after=page.next.unwrap(),
  )
  let events : Array[@strata.Recorded[Ev]] = rest.decode()
  debug_inspect(events.map(r => r.event), content="[Added(3)]")
  debug_inspect(rest.next, content="None")
}

///|
async test "fold over a selection" {
  let rt = @testing.runtime()
  let h = rt.handler(counter)
  h.execute("c1", Add(1), ctx~) |> ignore
  h.execute("c2", Add(2), ctx~) |> ignore
  inspect(rt.fold(total, @strata.Selection::category("counter")), content="3")
  inspect(
    rt.fold(total, @strata.Selection::stream(@strata.StreamId("counter-c2"))),
    content="2",
  )
}

///|
async test "retry re-decides only on append conflicts" {
  let rt = @testing.runtime()
  let plain = rt.handler(counter)
  let retrying = rt.handler(counter, retry=@runtime.Retry::on_conflict(max=3))
  plain.execute("c1", Add(1), ctx~) |> ignore
  // A stale client expectation is a conflict for the caller, not something retry hides.
  let conflict = try {
    retrying.execute("c1", Add(1), ctx~, expected=Exact(0)) |> ignore
    false
  } catch {
    @strata.StreamConflict(..) => true
    e => raise e
  }
  assert_true(conflict)
}

///|
async test "idempotency: a different command under the same key is a conflict" {
  let rt = @testing.runtime()
  let h = rt.handler(counter)
  h.execute("c1", Add(1), ctx~, idempotency_key="k") |> ignore
  let reused = try {
    h.execute("c1", Add(2), ctx~, idempotency_key="k") |> ignore
    false
  } catch {
    @strata.KeyReused(..) => true
    e => raise e
  }
  assert_true(reused)
  let ctx_key = ctx.with_idempotency_key("k2")
  let a = h.execute("c1", Add(5), ctx=ctx_key)
  let b = h.execute("c1", Add(5), ctx=ctx_key)
  assert_true(b.deduplicated)
  assert_eq(a.version, b.version)
}

///|
// #region inline
async test "inline projections are written with the append" {
  let rt = @testing.runtime()
  let h = rt.handler(counter, inline=[@runtime.inline(total, into="totals")])
  h.execute("c1", Add(1), ctx~) |> ignore
  h.execute("c1", Add(2), ctx~) |> ignore
  debug_inspect(
    rt.views().get(table="totals", key="c1"),
    content="Some(Number(3))",
  )
}
// #endregion inline

///|
// #region projector
async test "projectors chase the log and wait_for returns after the position" {
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
  let projector = rt.projector("totals", view, into="views")
  @async.with_task_group(g => {
    projector.start(g)
    let out = h.execute("c1", Add(4), ctx~)
    projector.wait_for(out.position, timeout=@strata.Duration::seconds(5))
    debug_inspect(
      rt.views().get(table="views", key="view"),
      content="Some(Number(4))",
    )
    g.return_immediately(())
  })
  inspect(projector.position(), content="1")
}
// #endregion projector

///|
// #region reactor
async test "reactors receive decoded events and checkpoint" {
  let rt = @testing.runtime()
  let h = rt.handler(counter)
  let seen : Array[(Int, String)] = []
  let reactor = rt.reactor(
    "echo",
    source=@strata.Selection::category("counter"),
    (r : @strata.Recorded[Ev]) => {
      match r.event {
        Added(n) => seen.push((n, r.caused().idempotency_key.unwrap()))
      }
    },
  )
  h.execute("c1", Add(7), ctx~) |> ignore
  reactor.catch_up()
  debug_inspect(seen, content="[(7, \"evt-0001\")]")
  inspect(reactor.position(), content="1")
  debug_inspect(rt.store().load_checkpoint("echo"), content="Some(Position(1))")
}
// #endregion reactor

///|
// #region state-at
async test "state_at replays a stream up to the event's version" {
  let rt = @testing.runtime()
  let h = rt.handler(counter)
  let first = h.execute("c1", Add(1), ctx~)
  h.execute("c1", Add(10), ctx~) |> ignore
  inspect(rt.state_at(counter, first.events[0]), content="1")
}
// #endregion state-at
