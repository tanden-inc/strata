///|
/// A Given/When/Then specification over a `Decider`: plain values in, plain
/// values out, no store, no runtime, no `async`. Immutable builder: every
/// method returns a new spec.
pub struct Spec[C, E, S, N] {
  priv decider : @strata.Decider[C, E, S, N]
  priv history : Array[E]
  priv env : @strata.Env
}

///|
/// Starts a specification. The default environment acts as
/// `Actor("user:test")` at `1970-01-01T00:00:00Z` with deterministic ids.
pub fn[C, E, S, N] spec(
  decider : @strata.Decider[C, E, S, N],
) -> Spec[C, E, S, N] {
  { decider, history: [], env: env(), }
}

///|
/// The past events.
pub fn[C, E, S, N] Spec::given(
  self : Spec[C, E, S, N],
  events : Array[E],
) -> Spec[C, E, S, N] {
  { ..self, history: self.history + events, }
}

///|
fn copy_env(
  env : @strata.Env,
  actor~ : @strata.Actor,
  now~ : @strata.Instant,
  ids~ : @strata.IdBatch,
  tenant~ : String?,
) -> @strata.Env {
  match tenant {
    Some(tenant) => @strata.Env(actor~, now~, tenant~, ids~, extra=env.extra)
    None => @strata.Env(actor~, now~, ids~, extra=env.extra)
  }
}

///|
fn[C, E, S, N] Spec::with_actor(
  self : Spec[C, E, S, N],
  actor : @strata.Actor,
  tenant : String?,
) -> Spec[C, E, S, N] {
  {
    ..self,
    env: copy_env(self.env, actor~, now=self.env.now, ids=self.env.ids, tenant~),
  }
}

///|
/// Who is acting (and for which tenant).
pub fn[C, E, S, N] Spec::acting_as(
  self : Spec[C, E, S, N],
  actor~ : @strata.Actor,
  tenant? : String,
) -> Spec[C, E, S, N] {
  let tenant = match tenant {
    Some(t) => Some(t)
    None => self.env.tenant
  }
  self.with_actor(actor, tenant)
}

///|
/// When the command runs.
pub fn[C, E, S, N] Spec::at(
  self : Spec[C, E, S, N],
  now : @strata.Instant,
) -> Spec[C, E, S, N] {
  {
    ..self,
    env: copy_env(
      self.env,
      actor=self.env.actor,
      now~,
      ids=self.env.ids,
      tenant=self.env.tenant,
    ),
  }
}

///|
/// Replaces the whole environment.
pub fn[C, E, S, N] Spec::with_env(
  self : Spec[C, E, S, N],
  env : @strata.Env,
) -> Spec[C, E, S, N] {
  { ..self, env, }
}

///|
/// Replaces the id batch.
pub fn[C, E, S, N] Spec::with_ids(
  self : Spec[C, E, S, N],
  ids : @strata.IdBatch,
) -> Spec[C, E, S, N] {
  {
    ..self,
    env: copy_env(
      self.env,
      actor=self.env.actor,
      now=self.env.now,
      ids~,
      tenant=self.env.tenant,
    ),
  }
}

///|
/// The state after the given events.
pub fn[C, E, S, N] Spec::state(self : Spec[C, E, S, N]) -> S {
  self.decider.replay(self.history.iter())
}

///|
fn[C, E, S, N] Spec::run(
  self : Spec[C, E, S, N],
  cmd : C,
) -> Result[@strata.Decision[E, N], Error] {
  Ok(self.decider.run(cmd, self.state(), self.env)) catch {
    err => Err(err)
  }
}

///|
/// The events a command records, or its rejection.
pub fn[C, E, S, N] Spec::when(
  self : Spec[C, E, S, N],
  cmd : C,
) -> Result[Array[E], Error] {
  match self.run(cmd) {
    Ok(decision) => Ok(decision.events)
    Err(err) => Err(err)
  }
}

///|
/// Runs several commands in sequence, each over the state left by the
/// previous one; stops at the first rejection.
pub fn[C, E, S, N] Spec::when_all(
  self : Spec[C, E, S, N],
  cmds : Array[C],
) -> Result[Array[E], Error] {
  let mut spec = self
  let events : Array[E] = []
  for cmd in cmds {
    match spec.when(cmd) {
      Err(err) => return Err(err)
      Ok(produced) => {
        events.append(produced[:])
        spec = spec.given(produced)
      }
    }
  }
  Ok(events)
}

///|
/// The advice for a command (empty when the command is rejected).
pub fn[C, E, S, N] Spec::advice(self : Spec[C, E, S, N], cmd : C) -> Array[N] {
  match self.run(cmd) {
    Ok(decision) => decision.notices
    Err(_) => []
  }
}

///|
/// Both the events and the advice, or the rejection.
pub fn[C, E, S, N] Spec::decision(
  self : Spec[C, E, S, N],
  cmd : C,
) -> Result[@strata.Decision[E, N], Error] {
  self.run(cmd)
}

///|
/// A specification over a `DcbDecider`. The history may contain events about
/// tags outside any scope; `scope_of` fixes which command's scope applies.
pub struct DcbSpec[C, E, S, N] {
  priv decider : @strata.DcbDecider[C, E, S, N]
  priv history : Array[E]
  priv env : @strata.Env
  priv scope : @strata.Scope?
}

///|
/// Starts a DCB specification.
pub fn[C, E, S, N] dcb_spec(
  decider : @strata.DcbDecider[C, E, S, N],
) -> DcbSpec[C, E, S, N] {
  { decider, history: [], env: env(), scope: None, }
}

///|
/// The past events (any tags).
pub fn[C, E, S, N] DcbSpec::given(
  self : DcbSpec[C, E, S, N],
  events : Array[E],
) -> DcbSpec[C, E, S, N] {
  { ..self, history: self.history + events, }
}

///|
/// Who is acting.
pub fn[C, E, S, N] DcbSpec::acting_as(
  self : DcbSpec[C, E, S, N],
  actor~ : @strata.Actor,
  tenant? : String,
) -> DcbSpec[C, E, S, N] {
  let tenant = match tenant {
    Some(t) => Some(t)
    None => self.env.tenant
  }
  {
    ..self,
    env: copy_env(self.env, actor~, now=self.env.now, ids=self.env.ids, tenant~),
  }
}

///|
/// Fixes the scope to the one this command would read.
pub fn[C, E, S, N] DcbSpec::scope_of(
  self : DcbSpec[C, E, S, N],
  cmd : C,
) -> DcbSpec[C, E, S, N] {
  { ..self, scope: Some(self.decider.scope_of(cmd)), }
}

///|
fn[C, E, S, N] DcbSpec::resolved_scope(
  self : DcbSpec[C, E, S, N],
  cmd : C,
) -> @strata.Scope {
  match self.scope {
    Some(scope) => scope
    None => self.decider.scope_of(cmd)
  }
}

///|
/// The state the fixed scope sees (history filtered by the scope, folded).
pub fn[C, E, S, N] DcbSpec::state(self : DcbSpec[C, E, S, N]) -> S {
  let scope = match self.scope {
    Some(scope) => scope
    None => @strata.Scope::of(@strata.Selection::all())
  }
  self.decider.replay(scope, self.history.iter())
}

///|
fn[C, E, S, N] DcbSpec::run(
  self : DcbSpec[C, E, S, N],
  cmd : C,
) -> Result[@strata.Decision[E, N], Error] {
  let scope = self.resolved_scope(cmd)
  let state = self.decider.replay(scope, self.history.iter())
  Ok(self.decider.run(cmd, state, self.env, scope)) catch {
    err => Err(err)
  }
}

///|
/// The events a command records within its own scope, or its rejection.
pub fn[C, E, S, N] DcbSpec::when(
  self : DcbSpec[C, E, S, N],
  cmd : C,
) -> Result[Array[E], Error] {
  match self.run(cmd) {
    Ok(decision) => Ok(decision.events)
    Err(err) => Err(err)
  }
}

///|
/// The advice for a command.
pub fn[C, E, S, N] DcbSpec::advice(
  self : DcbSpec[C, E, S, N],
  cmd : C,
) -> Array[N] {
  match self.run(cmd) {
    Ok(decision) => decision.notices
    Err(_) => []
  }
}

///|
fn[C, E, S, N] event_in_scope(
  decider : @strata.DcbDecider[C, E, S, N],
  scope : @strata.Scope,
  event : E,
) -> Bool {
  scope.selection().matches(event_type="", tags=decider.tags_of(event))
}

///|
/// The partial-world law: removing every out-of-scope event from the history
/// must not change the state. Fails with a diff when a leak is found.
#callsite(autofill(loc))
pub fn[C, E, S : Eq + Debug, N] DcbSpec::assert_scope_closed(
  self : DcbSpec[C, E, S, N],
  loc~ : SourceLoc,
) -> Unit raise {
  let scope = match self.scope {
    Some(scope) => scope
    None => fail("DcbSpec::assert_scope_closed requires scope_of", loc~)
  }
  let full = self.decider.replay(scope, self.history.iter())
  let filtered = self.history.filter(event => {
    event_in_scope(self.decider, scope, event)
  })
  let partial = self.decider.replay(scope, filtered.iter())
  assert_eq(full, partial, loc~)
}
