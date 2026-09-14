///|
/// A decider whose consistency boundary is a `Selection` rather than one
/// stream (Dynamic Consistency Boundaries).
///
/// `scope` names the events a command reads; the store rejects the append if
/// any event matching that selection appeared in between. Events still land in
/// a stream (`category` + `stream(cmd)`) and carry `tags(event)` so that
/// reactors and views can follow them.
///
/// State is a fold over *only* the selected events, so `evolve` receives the
/// `Scope` and must ignore the parts of an event the scope does not own.
pub struct DcbDecider[C, E, S, N] {
  priv category : String
  priv stream : (C) -> String
  priv scope : (C) -> Selection
  priv tags : (E) -> Array[Tag]
  priv initial : S
  priv decide : (C, S, Env, Scope) -> Array[E] raise
  priv evolve : (S, E, Scope) -> S
  priv advise : (C, S, Env, Scope) -> Array[N]
}

///|
/// Builds a DCB decider.
pub fn[C, E, S, N] DcbDecider::DcbDecider(
  category~ : String,
  stream~ : (C) -> String,
  scope~ : (C) -> Selection,
  tags~ : (E) -> Array[Tag],
  initial~ : S,
  decide~ : (C, S, Env, Scope) -> Array[E] raise,
  evolve~ : (S, E, Scope) -> S,
  advise? : (C, S, Env, Scope) -> Array[N] = (_, _, _, _) => [],
) -> DcbDecider[C, E, S, N] {
  { category, stream, scope, tags, initial, decide, evolve, advise, }
}

///|
/// The stream category.
pub fn[C, E, S, N] DcbDecider::category(
  self : DcbDecider[C, E, S, N],
) -> String {
  self.category
}

///|
/// The entity id of the stream a command's events land in.
pub fn[C, E, S, N] DcbDecider::stream_of(
  self : DcbDecider[C, E, S, N],
  cmd : C,
) -> String {
  (self.stream)(cmd)
}

///|
/// The selection a command reads (its consistency boundary).
pub fn[C, E, S, N] DcbDecider::scope_of(
  self : DcbDecider[C, E, S, N],
  cmd : C,
) -> Scope {
  Scope::of((self.scope)(cmd))
}

///|
/// The tags an event carries. Computed from the event alone, on purpose.
pub fn[C, E, S, N] DcbDecider::tags_of(
  self : DcbDecider[C, E, S, N],
  event : E,
) -> Array[Tag] {
  (self.tags)(event)
}

///|
/// The state before any event.
pub fn[C, E, S, N] DcbDecider::initial(self : DcbDecider[C, E, S, N]) -> S {
  self.initial
}

///|
/// Applies one event within a scope.
pub fn[C, E, S, N] DcbDecider::evolve(
  self : DcbDecider[C, E, S, N],
  state : S,
  event : E,
  scope : Scope,
) -> S {
  (self.evolve)(state, event, scope)
}

///|
/// `decide`, then `advise` only if `decide` succeeded.
pub fn[C, E, S, N] DcbDecider::run(
  self : DcbDecider[C, E, S, N],
  cmd : C,
  state : S,
  env : Env,
  scope : Scope,
) -> Decision[E, N] raise {
  let events = (self.decide)(cmd, state, env, scope)
  Decision(events~, notices=(self.advise)(cmd, state, env, scope))
}

///|
/// Folds the events a scope selected over the initial state.
pub fn[C, E, S, N] DcbDecider::replay(
  self : DcbDecider[C, E, S, N],
  scope : Scope,
  events : Iter[E],
) -> S {
  self.replay_from(scope, self.initial, events)
}

///|
/// Folds events over a given state within a scope.
pub fn[C, E, S, N] DcbDecider::replay_from(
  self : DcbDecider[C, E, S, N],
  scope : Scope,
  state : S,
  events : Iter[E],
) -> S {
  let mut state = state
  for event in events {
    state = self.evolve(state, event, scope)
  }
  state
}
