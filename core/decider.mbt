///|
/// What a decision produced: the events to record and the advice to return.
pub struct Decision[E, N] {
  events : Array[E]
  notices : Array[N]
} derive(Eq, Debug)

///|
/// Builds a decision.
pub fn[E, N] Decision::Decision(
  events~ : Array[E],
  notices? : Array[N] = [],
) -> Decision[E, N] {
  { events, notices, }
}

///|
/// A domain: an initial state, a pure `decide`, a pure `evolve`, and
/// optionally `advise`, `tags` and `is_terminal`.
///
/// - `C` commands, `E` events, `S` state, `N` notices (use `Unit` when the
///   decider gives no advice).
/// - `decide` answers "what is recorded, or why not" and raises a typed
///   rejection; it cannot perform effects because its type has none.
/// - `advise` runs beside `decide` over the same inputs and answers "what
///   should the caller know"; notices are returned, never stored.
pub struct Decider[C, E, S, N] {
  priv category : String
  priv initial : S
  priv decide : (C, S, Env) -> Array[E] raise
  priv evolve : (S, E) -> S
  priv advise : (C, S, Env) -> Array[N]
  priv tags : (E) -> Array[Tag]
  priv is_terminal : (S) -> Bool
}

///|
/// Builds a decider. Optional parts default to "no advice", "no tags" and
/// "never terminal".
pub fn[C, E, S, N] Decider::Decider(
  category~ : String,
  initial~ : S,
  decide~ : (C, S, Env) -> Array[E] raise,
  evolve~ : (S, E) -> S,
  advise? : (C, S, Env) -> Array[N] = (_, _, _) => [],
  tags? : (E) -> Array[Tag] = _ => [],
  is_terminal? : (S) -> Bool = _ => false,
) -> Decider[C, E, S, N] {
  { category, initial, decide, evolve, advise, tags, is_terminal, }
}

///|
/// The stream category (`"account"` gives streams `account-<id>`).
pub fn[C, E, S, N] Decider::category(self : Decider[C, E, S, N]) -> String {
  self.category
}

///|
/// The state before any event.
pub fn[C, E, S, N] Decider::initial(self : Decider[C, E, S, N]) -> S {
  self.initial
}

///|
/// Runs `decide` only.
pub fn[C, E, S, N] Decider::decide(
  self : Decider[C, E, S, N],
  cmd : C,
  state : S,
  env : Env,
) -> Array[E] raise {
  (self.decide)(cmd, state, env)
}

///|
/// Runs `advise` only.
pub fn[C, E, S, N] Decider::advise(
  self : Decider[C, E, S, N],
  cmd : C,
  state : S,
  env : Env,
) -> Array[N] {
  (self.advise)(cmd, state, env)
}

///|
/// Applies one event to the state.
pub fn[C, E, S, N] Decider::evolve(
  self : Decider[C, E, S, N],
  state : S,
  event : E,
) -> S {
  (self.evolve)(state, event)
}

///|
/// The tags an event carries (empty unless `tags=` was given).
pub fn[C, E, S, N] Decider::tags_of(
  self : Decider[C, E, S, N],
  event : E,
) -> Array[Tag] {
  (self.tags)(event)
}

///|
/// Whether the stream accepts no further commands in this state.
pub fn[C, E, S, N] Decider::is_terminal(
  self : Decider[C, E, S, N],
  state : S,
) -> Bool {
  (self.is_terminal)(state)
}

///|
/// The single pure entry point used by the runtime, `Preview` and `testing`:
/// `decide`, then `advise` only if `decide` succeeded. A rejected command gets
/// its error, not commentary.
pub fn[C, E, S, N] Decider::run(
  self : Decider[C, E, S, N],
  cmd : C,
  state : S,
  env : Env,
) -> Decision[E, N] raise {
  let events = self.decide(cmd, state, env)
  Decision(events~, notices=self.advise(cmd, state, env))
}

///|
/// Folds events over the initial state.
pub fn[C, E, S, N] Decider::replay(
  self : Decider[C, E, S, N],
  events : Iter[E],
) -> S {
  self.replay_from(self.initial, events)
}

///|
/// Folds events over a given state (a snapshot plus its tail).
pub fn[C, E, S, N] Decider::replay_from(
  self : Decider[C, E, S, N],
  state : S,
  events : Iter[E],
) -> S {
  let mut state = state
  for event in events {
    state = self.evolve(state, event)
  }
  state
}
