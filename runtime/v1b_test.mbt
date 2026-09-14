///|
async test "event ids stay unique across many decisions of mixed size" {
  let rt = @testing.runtime()
  let singles = rt.handler(counter)
  let pairs = rt.handler(pair)
  let ids : Array[String] = []
  for round in 0..<4 {
    for r in singles.execute("s\{round}", Add(1), ctx~).events {
      ids.push(r.id.0)
    }
    for r in pairs.execute("p\{round}", 1, ctx~).events {
      ids.push(r.id.0)
    }
  }
  let seen : Set[String] = Set([])
  for id in ids {
    assert_false(seen.contains(id), msg="duplicate id \{id} in \{Repr(ids)}")
    seen.add(id)
  }
  inspect(ids.length(), content="12")
  inspect(ids[11], content="evt-0012")
}

///|
test "sequential ids never repeat, even after a decision that took no ids" {
  let seq = @runtime.IdGenerator::sequential()
  let a = seq.reserve(now=@strata.Instant(0))
  inspect(a.at(0), content="evt-0001")
  let b = seq.reserve(now=@strata.Instant(0))
  inspect(b.at(0), content="evt-0002")
  let c = seq.reserve(now=@strata.Instant(0))
  inspect(c.at(0), content="evt-0003")
  inspect(c.at(1), content="evt-0004")
  let _unused = seq.reserve(now=@strata.Instant(0))
  inspect(seq.reserve(now=@strata.Instant(0)).at(0), content="evt-0005")
}

///|
test "ulids stay monotonic across an empty batch and a backwards clock" {
  let ulid = @runtime.IdGenerator::ulid()
  let first = ulid.reserve(now=@strata.Instant(1_000))
  let used = first.at(1)
  let _empty = ulid.reserve(now=@strata.Instant(1_000))
  let later = ulid.reserve(now=@strata.Instant(500)).at(0)
  assert_true(later > used, msg="\{later} should follow \{used}")
}

///|
async test "cancelling a reactor is not a handler failure" {
  let rt = @testing.runtime()
  let h = rt.handler(counter)
  let dead : Array[String] = []
  let attempts : Ref[Int] = { val: 0, }
  let reactor = rt.reactor(
    "slow",
    source=@strata.Selection::category("counter"),
    retry=Immediate,
    max_retry=3,
    on_failure=(stored, _err) => dead.push(stored.id.0),
    (_r : @strata.Recorded[Ev]) => {
      attempts.val += 1
      @async.sleep(60_000)
    },
  )
  h.execute("c1", Add(1), ctx~) |> ignore
  @async.with_task_group(g => {
    reactor.start(g)
    @async.sleep(50)
    g.return_immediately(())
  })
  inspect(attempts.val, content="1")
  debug_inspect(dead, content="[]")
  inspect(reactor.position(), content="0")
}

///|
async test "reactor retry honours the configured delays" {
  let rt = @testing.runtime()
  let h = rt.handler(counter)
  h.execute("c1", Add(1), ctx~) |> ignore
  let failing = (_r : @strata.Recorded[Ev]) => {
    @async.pause()
    fail("always")
  }
  let slow = rt.reactor(
    "exp",
    source=@strata.Selection::category("counter"),
    retry=ExponentialDelay(initial=200, factor=2.0, maximum=1_000),
    max_retry=2,
    on_failure=(_s, _e) => (),
    failing,
  )
  let started = @async.now()
  slow.catch_up()
  let elapsed = @async.now() - started
  assert_true(
    elapsed >= 550L,
    msg="expected >= 200 + 400 ms of backoff, got \{elapsed}",
  )
  let quick = rt.reactor(
    "fixed",
    source=@strata.Selection::category("counter"),
    retry=FixedDelay(5),
    max_retry=3,
    on_failure=(_s, _e) => (),
    failing,
  )
  let started2 = @async.now()
  quick.catch_up()
  let elapsed2 = @async.now() - started2
  assert_true(
    elapsed2 < 150L,
    msg="expected ~15 ms of backoff, got \{elapsed2}",
  )
}
