///|
/// What a decision may depend on besides the command and the state:
/// who is acting, for which tenant, at what time, with which event ids, plus
/// application-declared extras. Supplied by the runtime, fixed by tests.
pub struct Env {
  /// The acting principal.
  actor : Actor
  /// The tenant; also becomes a stream-name prefix (`t1/account-acc-1`).
  tenant : String?
  /// The current instant according to the runtime `Clock`.
  now : Instant
  /// The ids the events emitted by this decision will carry.
  ids : IdBatch
  /// Application-declared facts (for example a rate-table version).
  extra : Json
}

///|
/// Builds an environment. `ids` defaults to a deterministic batch so that
/// hand-built environments (tests, `Preview`) are reproducible.
pub fn Env::Env(
  actor~ : Actor,
  now~ : Instant,
  tenant? : String,
  ids? : IdBatch = IdBatch::deterministic(),
  extra? : Json = Json::null(),
) -> Env {
  { actor, tenant, now, ids, extra, }
}

///|
/// The audit envelope a caller supplies with a command: correlation and
/// causation, the actor, the tenant, the idempotency key and free-form flags.
/// The runtime derives `Env` and `Metadata` from it.
pub struct Context {
  actor : Actor
  tenant : String?
  correlation_id : String?
  causation_id : EventId?
  idempotency_key : String?
  flags : Array[String]
  extra : Json
}

///|
/// Builds a context.
pub fn Context::Context(
  actor~ : Actor,
  tenant? : String,
  correlation_id? : String,
  causation_id? : EventId,
  idempotency_key? : String,
  flags? : Array[String] = [],
  extra? : Json = Json::null(),
) -> Context {
  {
    actor,
    tenant,
    correlation_id,
    causation_id,
    idempotency_key,
    flags,
    extra,
  }
}

///|
/// Whether a flag such as `"anonymous"` is set.
pub fn Context::flag(self : Context, name : String) -> Bool {
  self.flags.contains(name)
}

///|
/// A copy with the idempotency key set.
pub fn Context::with_idempotency_key(self : Context, key : String) -> Context {
  { ..self, idempotency_key: Some(key), }
}

///|
/// A copy with a flag added.
pub fn Context::with_flag(self : Context, name : String) -> Context {
  if self.flags.contains(name) {
    self
  } else {
    let flags = self.flags.copy()
    flags.push(name)
    { ..self, flags, }
  }
}

///|
/// The metadata that will be stored with events recorded under this context.
pub fn Context::to_metadata(self : Context) -> Metadata {
  {
    correlation_id: self.correlation_id,
    causation_id: self.causation_id,
    actor: Some(self.actor),
    tenant: self.tenant,
    idempotency_key: self.idempotency_key,
    extra: self.extra,
  }
}

///|
/// Metadata stored alongside every event.
pub struct Metadata {
  correlation_id : String?
  causation_id : EventId?
  actor : Actor?
  tenant : String?
  idempotency_key : String?
  extra : Json
} derive(Eq, Debug, ToJson, FromJson)

///|
/// Builds metadata.
pub fn Metadata::Metadata(
  correlation_id? : String,
  causation_id? : EventId,
  actor? : Actor,
  tenant? : String,
  idempotency_key? : String,
  extra? : Json = Json::null(),
) -> Metadata {
  { correlation_id, causation_id, actor, tenant, idempotency_key, extra, }
}
