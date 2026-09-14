///|
/// What a command would do: its rejection or events, and its advice.
pub struct PreviewResult[E, N] {
  result : Result[Array[E], Error]
  notices : Array[N]
}

///|
/// Builds a preview result.
pub fn[E, N] PreviewResult::PreviewResult(
  result~ : Result[Array[E], Error],
  notices? : Array[N] = [],
) -> PreviewResult[E, N] {
  { result, notices, }
}

///|
/// Runs a decider over a given state and environment without a store, so a
/// client (for example the browser, via `wasm-gc` or `js`) can preview a
/// command with the same rules the server runs. The state may be stale; the
/// server's `execute` remains the authority.
pub struct Preview[C, E, S, N] {
  priv decider : Decider[C, E, S, N]
  priv state : S
  priv env : Env
}

///|
/// Builds a preview.
pub fn[C, E, S, N] Preview::Preview(
  decider : Decider[C, E, S, N],
  state~ : S,
  env~ : Env,
) -> Preview[C, E, S, N] {
  { decider, state, env, }
}

///|
/// The decision (or rejection) and advice for a command.
pub fn[C, E, S, N] Preview::of(
  self : Preview[C, E, S, N],
  cmd : C,
) -> PreviewResult[E, N] {
  try {
    let decision = self.decider.run(cmd, self.state, self.env)
    PreviewResult(result=Ok(decision.events), notices=decision.notices)
  } catch {
    err => PreviewResult(result=Err(err), notices=[])
  }
}

///|
/// The state the preview runs over.
pub fn[C, E, S, N] Preview::state(self : Preview[C, E, S, N]) -> S {
  self.state
}
