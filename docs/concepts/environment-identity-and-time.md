# Environment, identity, and time

Strata separates four things that other libraries blur together.

**The command** is the intent: `Withdraw(amount=80)`. It does not say who, or when; those are not part of the intent.

**The environment** (`Env`) is what a decision may depend on besides the command and the state: the acting principal,
the tenant, the current instant, the identities of the events about to be emitted, and any typed extras your
application declares. It is passed *into* `decide` and `advise` as a value. A rule such as *only the owner may
withdraw* is written once, against `env.actor`, and tested by fixing the environment in the spec.

**The event** is a fact. Facts legitimately include who acted and when the business says it happened, so `decide`
stamps `env.actor` (and, when the meaning is "as of", an instant) into the event body where the domain cares. This
is not a duplicate of the command's actor, since commands do not carry one; it is the decision turning an invocation
fact into a domain fact.

**The metadata** (`Context`) is the audit envelope: correlation and causation ids, the actor, the tenant, the
idempotency key, flags. It exists whether or not the domain chose to record the actor in the event. The runtime
derives `Env` from `Context`, so callers supply one thing.

## `Env`

```moonbit
pub struct Env {
  actor : Actor        // who is acting
  tenant : String?     // also becomes a stream-name prefix: "t1/account-acc-1"
  now : Instant        // from the runtime Clock; fixed in tests
  ids : IdBatch        // the ids the events emitted by this decision will carry
  extra : Json         // application-declared facts (e.g. a rate table version)
}
// built with Env(actor~, now~, tenant?, ids?, extra?) so fields can be added later
```

## Identity is supplied, not generated

`decide` cannot make a ULID; that would be an effect. Yet events often need to be referred to later: a reversal names
the entry it undoes, a settlement names the reservation it settles. So the runtime reserves the ids *before* calling
`decide`, and `env.ids.at(i)` is the id that the *i*-th emitted event will receive. `decide` can write it into the
event body; `evolve` can index state by it; and the runtime guarantees `recorded.id == recorded.event.id` wherever you
chose to embed it. In `@testing.spec` the batch is deterministic (`evt-0001`, `evt-0002`, …), so snapshots stay
stable.

```moonbit
(Reserve(amount~, ref~), _) => [Reserved(id=env.ids.at(0), amount~, ref~, by=env.actor)]
(Settle(reservation~), _) if !s.reservations.contains(reservation) =>
  raise LedgerError::UnknownReservation(reservation~)
```

A batch is sized by use: a decision may take any number of ids, and the generator starts the next batch strictly after
the last id handed out, also when the clock runs backwards ([ADR 0006](/adr/0006-id-batches-and-reactor-failure)).
`EventId` is an opaque string; the runtime mints ULIDs and tests use `evt-0001`.

## What consumers see

Every read decodes into a `Recorded[E]`, the envelope around the event:

```moonbit
pub struct Recorded[E] {
  id : EventId            // ULID; the basis for idempotency, causation, and dedup
  position : Position     // global log position
  stream : StreamId
  version : Int
  event_type : String
  event : E
  tags : Array[Tag]       // the event's own tags; system tags ($stream:, $category:, $tenant:) stay in the store
  recorded_at : Instant
  meta : Metadata         // correlation_id, causation_id, actor, tenant, idempotency_key, extra : Json
}
```

`r.entity_id()` extracts the id from the stream name; `r.caused()` builds the `Context` for a downstream command
([Reactors](/concepts/reactors-and-process-managers)).

## Time

Time is a runtime concern. `env.now` is the default source; a command may still carry an explicit instant when the
business meaning is "as of". The runtime's `Clock` is injectable, so replays and tests are deterministic:

```moonbit
let rt = @rt.Runtime(store, clock=@rt.Clock::parse_fixed("2026-09-13T00:00:00Z"))
```

`Clock::system()`, `fixed(instant)`, `manual(instant)` with `advance(duration)`, and `parse_fixed(iso)` are the four
constructors. `Instant` is unix milliseconds, ISO-8601 in JSON; `Duration` is milliseconds. The standard library has
no instant type and `moonbitlang/x/time` is fallible in every operation and has no JSON form, which is why Strata
defines its own ([ADR 0003](/adr/0003-ids-time-and-system-tags)).

## Tenants

A tenant on the `Context` becomes a prefix of the stream name (`t1/account-acc-1`) and a `$tenant:` system tag on
every event. `Selection::category(name, tenant~)`, `rt.live(..., tenant~)` and `handler.load(id, tenant~)` scope
reads to one tenant, so inline rows and folds never mix tenants.
