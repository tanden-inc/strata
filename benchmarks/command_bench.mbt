///|
priv enum Ev {
  Added(Int)
}

///|
let counter : @strata.Decider[Int, Ev, Int, Unit] = @strata.Decider(
  category="counter",
  initial=0,
  decide=(n, _s, _env) => [Added(n)],
  evolve=(s, e) => {
    match e {
      Added(n) => s + n
    }
  },
)

///|
/// The pure half of the command path: replay 1000 events, then decide.
test "replay and decide" (b : @bench.T) {
  let history : Array[Ev] = []
  for i in 0..<1000 {
    history.push(Added(i))
  }
  let env = @strata.Env(actor=@strata.Actor("bench"), now=@strata.Instant(0))
  b.bench(name="replay 1000 + decide", fn() {
    let state = counter.replay(history.iter())
    b.keep(counter.run(1, state, env) catch { _ => panic() })
  })
}
