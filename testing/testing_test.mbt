///|
#warnings("-unused_value")
priv enum Cmd {
  Add(Int)
  Boom
} derive(Eq, Debug)

///|
#warnings("-unused_value")
priv enum Ev {
  Added(Int)
} derive(Eq, Debug, ToJson, FromJson)

///|
#warnings("-unused_value")
priv suberror Kaboom derive(Eq, Debug)

///|
let counter : @strata.Decider[Cmd, Ev, Int, String] = @strata.Decider(
  category="counter",
  initial=0,
  decide=(cmd, _s, env) => {
    match cmd {
      Add(n) => [Added(n + env.now.0.to_int())]
      Boom => raise Kaboom
    }
  },
  evolve=(s, e) => {
    match e {
      Added(n) => s + n
    }
  },
  advise=(_c, s, _e) => if s > 5 { ["big"] } else { [] },
)

///|
test "spec builds state from the given events and reports decisions" {
  let spec = @testing.spec(counter).given([Added(2), Added(4)])
  inspect(spec.state(), content="6")
  spec.when(Add(1)) |> debug_inspect(content="Ok([Added(1)])")
  spec.when(Boom) |> debug_inspect(content="Err(Kaboom)")
  spec.advice(Add(1)) |> debug_inspect(content="[\"big\"]")
  spec.advice(Boom) |> debug_inspect(content="[]")
  spec.decision(Add(1))
  |> debug_inspect(content="Ok({ events: [Added(1)], notices: [\"big\"] })")
}

///|
test "spec environment: actor, time and ids are fixed" {
  let spec = @testing.spec(counter).at(@strata.Instant(100))
  spec.when(Add(1)) |> debug_inspect(content="Ok([Added(101)])")
  let ids = @testing.spec(counter)
    .with_ids(@strata.IdBatch::deterministic(prefix="x-"))
    .with_env(@testing.env(actor=@strata.Actor("user:bob")))
  inspect(ids.state(), content="0")
}

///|
test "when_all threads state and stops at the first rejection" {
  let spec = @testing.spec(counter)
  spec.when_all([Add(1), Add(2)])
  |> debug_inspect(content="Ok([Added(1), Added(2)])")
  spec.when_all([Add(1), Boom, Add(2)]) |> debug_inspect(content="Err(Kaboom)")
}

///|
test "replay law holds for a lawful decider" {
  @testing.replay_law(counter, [Added(1), Added(2), Added(3)])
}

///|
test "advice law: rejected commands carry no advice" {
  @testing.advice_law(counter, histories=[[], [Added(9)]], commands=[
    Add(1),
    Boom,
  ])
}

///|
test "recorded and stored helpers fill the envelope" {
  let r = @testing.recorded(
    Added(1),
    stream=@strata.StreamId("counter-c1"),
    version=1,
    position=@strata.Position(1),
  )
  inspect(r.id, content="evt-0001")
  inspect(r.entity_id(), content="c1")
  let s = @testing.stored(
    event_type="Added",
    data=["Added", 1],
    stream=@strata.StreamId("counter-c1"),
    version=1,
    position=@strata.Position(1),
  )
  debug_inspect(
    s.tags,
    content="[Tag(\"$stream:counter-c1\"), Tag(\"$category:counter\")]",
  )
}

///|
test "fixtures report decoded and skipped shapes" {
  let codec = @codec.JsonCodec()
  codec.deprecated("Old")
  let fixtures = @testing.Fixtures::from_json([
    ("Added", 1, ["Added", 1]),
    ("Old", 1, "Old"),
  ])
  let report : @testing.FixtureReport[Ev] = fixtures.all_decode(codec)
  debug_inspect(report.decoded.map(r => r.event), content="[Added(1)]")
  inspect(report.skipped, content="1")
  let _ : Array[@strata.Recorded[Ev]] = codec.decode_all([])
}

///|
test "the contract suite has named cases" {
  assert_true(@testing.contract_cases().length() >= 10)
}

///|
async test "the test runtime uses a fixed clock and sequential ids" {
  let rt = @testing.runtime()
  let h = rt.handler(counter)
  let out = h.execute(
    "c1",
    Add(1),
    ctx=@strata.Context(actor=@strata.Actor("u")),
  )
  inspect(out.events[0].id, content="evt-0001")
  inspect(out.events[0].recorded_at, content="1970-01-01T00:00:00.000Z")
}
