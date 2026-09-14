///|
#warnings("-unused_value")
priv enum Cmd {
  Inc(Int)
  Fail
} derive(Eq, Debug)

///|
#warnings("-unused_value")
priv enum Ev {
  Added(Int)
} derive(Eq, Debug)

///|
#warnings("-unused_value")
priv suberror Nope derive(Eq, Debug)

///|
let counter : @core.Decider[Cmd, Ev, Int, String] = @core.Decider(
  category="counter",
  initial=0,
  decide=(cmd, _s, _env) => {
    match cmd {
      Inc(n) => [Added(n)]
      Fail => raise Nope
    }
  },
  evolve=(s, e) => {
    match e {
      Added(n) => s + n
    }
  },
  advise=(cmd, s, _env) => {
    match cmd {
      Inc(n) if s + n > 10 => ["over ten"]
      _ => []
    }
  },
  is_terminal=s => s >= 100,
)

///|
let env : @core.Env = @core.Env(
  actor=@core.Actor("user:test"),
  now=@core.Instant(0),
)

///|
test "run decides then advises" {
  counter.run(Inc(3), 9, env)
  |> debug_inspect(content="{ events: [Added(3)], notices: [\"over ten\"] }")
  counter.run(Inc(1), 0, env)
  |> debug_inspect(content="{ events: [Added(1)], notices: [] }")
}

///|
test "a rejected command produces no advice" {
  let advised : Ref[Bool] = { val: false, }
  let d : @core.Decider[Cmd, Ev, Int, String] = @core.Decider(
    category="c",
    initial=0,
    decide=(_c, _s, _e) => raise Nope,
    evolve=(s, _e) => s,
    advise=(_c, _s, _e) => {
      advised.val = true
      ["x"]
    },
  )
  let rejected = try {
    d.run(Fail, 0, env) |> ignore
    false
  } catch {
    Nope => true
    e => raise e
  }
  assert_true(rejected)
  assert_false(advised.val)
}

///|
test "replay folds and replay_from continues" {
  inspect(
    counter.replay([Ev::Added(1), Ev::Added(2), Ev::Added(3)].iter()),
    content="6",
  )
  inspect(counter.replay_from(6, [Ev::Added(4)].iter()), content="10")
  inspect(counter.replay(([] : Array[Ev]).iter()), content="0")
}

///|
test "defaults: no advice, no tags, never terminal" {
  let d : @core.Decider[Cmd, Ev, Int, Unit] = @core.Decider(
    category="c",
    initial=0,
    decide=(_c, _s, _e) => [Added(1)],
    evolve=(s, _e) => s,
  )
  debug_inspect(d.advise(Inc(1), 0, env), content="[]")
  debug_inspect(d.tags_of(Added(1)), content="[]")
  assert_false(d.is_terminal(1000))
  assert_true(counter.is_terminal(100))
  inspect(d.category(), content="c")
}

///|
test "preview reports rejection, events and advice" {
  let preview = @core.Preview(counter, state=9, env~)
  let over = preview.of(Inc(3))
  debug_inspect(over.result, content="Ok([Added(3)])")
  debug_inspect(over.notices, content="[\"over ten\"]")
  let bad = preview.of(Fail)
  debug_inspect(bad.result, content="Err(Nope)")
  debug_inspect(bad.notices, content="[]")
}
