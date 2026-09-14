<p align="center">
  <img src="docs/assets/strata.svg" width="120" alt="Strata">
</p>

<h1 align="center">Strata</h1>

<p align="center">
  <strong>Event sourcing for MoonBit — where the type checker does the bookkeeping.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/status-interfaces%20designed%2C%20implementing-orange" alt="status">
  <img src="https://img.shields.io/badge/targets-native%20%7C%20js%20%7C%20wasm--gc-blue" alt="targets">
  <img src="https://img.shields.io/badge/MoonBit-0.10%2B-lightgrey" alt="MoonBit 0.10+">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-green" alt="License"></a>
</p>

---

> **Status.** `core`, `codec`, `store` (in-memory), `runtime` and `testing` are implemented against the 0.1 interface
> (see the `pkg.generated.mbti` files). The road to 1.0 is in [`docs/ROADMAP.md`](docs/ROADMAP.md): the PostgreSQL
> store, a handful of correctness fixes with red tests, and release hygiene. Sealing/shredding encryption, `http`,
> `graphql` and `moon prove` obligations are planned for 1.x; their sections below say so.

Strata is an event sourcing toolkit for MoonBit web backends. You describe a domain as plain enums and pure functions; Strata takes care of persistence, optimistic concurrency, idempotency, read models, process managers, schema evolution, snapshots, and the other dozen things every event-sourced system needs and every team ends up rebuilding by hand.

Three ideas run through the whole library. **Writes are decisions**: a `Decider` turns a command and a state into events or a typed rejection, and it is a pure function by construction. **Most decisions are to record**: alongside the decision, a `Decider` can offer *advice* — warnings and forecasts computed from the same state, returned to the caller, never persisted — so a system can inform without blocking. **Reads are selections**: every read model, every reactor, and every consistency boundary is expressed with the same `Selection` type — a stream, a category, a set of tags, or a combination — so the read side is exactly as expressive as the write side.

The domain code you write has no dependency on a database, a runtime, or even on `async`. It compiles unchanged to the native backend (production, with PostgreSQL), to JavaScript, and to WebAssembly — which means the same `decide` and `advise` that run on your server can run in the browser to preview a command before it is sent. Your tests are Given/When/Then over plain values and run in milliseconds. And because the interesting parts are pure functions over closed sum types, the compiler tells you exactly what to update when your model changes — and `moon prove` can tell you that your invariants actually hold.

```moonbit
pub let account : @strata.Decider[AccountCmd, AccountEvent, Account, Unit] = @strata.Decider(
  category="account",
  initial={ owner: None, balance: 0, closed: false },
  decide=(cmd, s, env) => match (cmd, s) {
    (Withdraw(..), _) if Some(env.actor) != s.owner =>
      raise AccountError::NotOwner
    (Withdraw(amount~), _) if amount > s.balance =>
      raise AccountError::Insufficient(balance=s.balance, requested=amount)
    (Withdraw(amount~), _) => [Withdrawn(amount~, by=env.actor)]
    ...
  },
  evolve=(s, e) => match e {
    Deposited(amount~, ..) => { ..s, balance: s.balance + amount }
    Withdrawn(amount~, ..) => { ..s, balance: s.balance - amount }
    ...
  },
  is_terminal=s => s.closed,
)
```

That value is your entire aggregate. Everything else in this README is about what Strata does with it.

## Contents

- [Why Strata](#why-strata)
- [Sixty seconds](#sixty-seconds)
- [Design](#design)
- [Tour](#tour)
  - [Commands and optimistic concurrency](#commands-and-optimistic-concurrency)
  - [Advice: informing without blocking](#advice-informing-without-blocking)
  - [Preview: the same decision in the browser](#preview-the-same-decision-in-the-browser)
  - [Idempotency](#idempotency)
  - [Environment, identity, and time](#environment-identity-and-time)
  - [Selections](#selections)
  - [Read models](#read-models)
  - [Reactors and process managers](#reactors-and-process-managers)
  - [Dynamic consistency boundaries](#dynamic-consistency-boundaries)
  - [The partial world](#the-partial-world)
  - [Reversals](#reversals)
  - [Schema evolution](#schema-evolution)
  - [Closing the books and snapshots](#closing-the-books-and-snapshots)
  - [Integration events](#integration-events)
  - [Sealing and shredding](#sealing-and-shredding)
  - [HTTP and GraphQL](#http-and-graphql)
- [Testing](#testing)
- [Architecture](#architecture)
- [Stores and targets](#stores-and-targets)
- [How Strata relates to other tools](#how-strata-relates-to-other-tools)
- [Stability](#stability)
- [FAQ](#faq)
- [Acknowledgements](#acknowledgements)

## Why Strata

Event sourcing is a good idea with a bad reputation, and most of the reputation is earned by tooling rather than by the idea. Across ecosystems the same taxes show up:

**The boilerplate tax.** One class per event, a serializer per class, a registry entry per serializer, an upcaster per version. Teams write hundreds of lines before the first business rule.

**The reflection tax.** Annotations and runtime scanning decide which method handles which event. Nothing is checked until the process starts. Rename an event and find out in production which projection you forgot.

**The mutability tax.** Aggregates are objects that mutate themselves while events are applied. Reasoning about them means reasoning about time; testing them means constructing them.

**The effect tax.** Clocks, random IDs, and database calls leak into domain code because nothing stops them. Unit tests grow a database. Replays become non-deterministic.

**The read-side tax.** Write models get all the design attention; read models are an afterthought bolted to one stream at a time. The moment a view needs two categories, or a fan-out to several keys, or a fold over events selected by tag, you are writing infrastructure.

**The judgement tax.** Every library assumes the aggregate is a gatekeeper. Domains where the right answer is *record it, flag it, let a person decide* end up either smuggling warnings into the log as fake events or rebuilding the aggregate's state in a second place just to compute them.

MoonBit removes the first four at the language level, and Strata is designed so that the last two never appear:

| Tax | What MoonBit gives you | What Strata does with it |
|---|---|---|
| Boilerplate | `derive(ToJson, FromJson)` on enums and structs | Derived JSON *is* the storage format (`["Deposited", {"amount": 100, ...}]`). No codecs, no registries. |
| Reflection | Closed enums with exhaustive `match` | Adding an event variant is a compile error in every `evolve` and `apply` that forgot it. |
| Mutability | Immutable-by-default data and `{ ..s, field }` updates | State is a value. Replay is a fold. Snapshots are `Eq`. |
| Effects | Checked errors (`raise`) and `async` tracked in function types | `decide` is `(C, S, Env) -> Array[E] raise`. It *cannot* call a clock or a database — the type won't let it. Identity, time, and actor arrive as values in `Env`. |
| Read side | Values, closures, and generics that compose | One `Selection` type drives folds, paged reads, projections, reactors, and consistency conditions. Views fan out to many keys and fold many sources without wrapper types. |
| Judgement | Pure functions are cheap to run twice | `advise` runs beside `decide` over the same state, returns notices that are never stored, and compiles to the browser so the client can see the warning before the server does. |
| — | Traits with `async` methods and `#cfg(target)` | The event store is one trait; pass any implementation to `Runtime(store)`. Same contract tests on memory and PostgreSQL. |
| — | Structured concurrency with cancellation | Projectors and reactors are tasks in a `TaskGroup`. Shutdown is automatic. |
| — | `moon prove` | Invariants over `decide`/`evolve` can be proven, not just tested (experimental). |

Strata is what event sourcing looks like when the language was designed after the pattern.

## Sixty seconds

```bash
moon add tanden-inc/strata
```

```moonbit
// moon.pkg
import {
  "tanden-inc/strata/core" @strata,
  "tanden-inc/strata/store" @store,      // EventStore trait + the in-memory MemoryStore
  "tanden-inc/strata/runtime" @rt,
  "moonbitlang/async",
}

import {
  "tanden-inc/strata/testing" @testing,
} for "test"
```

Define the domain — events are facts, commands are intents, state is a fold:

```moonbit
pub(all) enum AccountEvent {
  Opened(owner~ : @strata.Actor)
  Deposited(amount~ : Int, by~ : @strata.Actor)
  Withdrawn(amount~ : Int, by~ : @strata.Actor)
  Closed(by~ : @strata.Actor)
} derive(Eq, Debug, ToJson, FromJson)

pub(all) enum AccountCmd {
  Open
  Deposit(amount~ : Int)
  Withdraw(amount~ : Int)
  Close
} derive(Eq, Debug)

pub(all) struct Account { owner : @strata.Actor?; balance : Int; closed : Bool } derive(Eq, Debug, ToJson, FromJson)

pub(all) suberror AccountError {
  AlreadyOpened
  NotOpened
  NotOwner
  NonPositive(amount~ : Int)
  Insufficient(balance~ : Int, requested~ : Int)
  NotEmpty(balance~ : Int)
  AlreadyClosed
} derive(Eq, Debug)

pub let account : @strata.Decider[AccountCmd, AccountEvent, Account, Unit] = @strata.Decider(
  category="account",
  initial={ owner: None, balance: 0, closed: false },
  decide=(cmd, s, env) => match (cmd, s) {
    (_, { closed: true, .. })                      => raise AccountError::AlreadyClosed
    (Open, { owner: Some(_), .. })                 => raise AccountError::AlreadyOpened
    (Open, _)                                      => [Opened(owner=env.actor)]
    (_, { owner: None, .. })                       => raise AccountError::NotOpened
    (Withdraw(..) | Close, _) if Some(env.actor) != s.owner => raise AccountError::NotOwner
    (Deposit(amount~), _) if amount <= 0           => raise AccountError::NonPositive(amount~)
    (Deposit(amount~), _)                          => [Deposited(amount~, by=env.actor)]
    (Withdraw(amount~), _) if amount <= 0          => raise AccountError::NonPositive(amount~)
    (Withdraw(amount~), _) if amount > s.balance   =>
      raise AccountError::Insufficient(balance=s.balance, requested=amount)
    (Withdraw(amount~), _)                         => [Withdrawn(amount~, by=env.actor)]
    (Close, _) if s.balance != 0                   => raise AccountError::NotEmpty(balance=s.balance)
    (Close, _)                                     => [Closed(by=env.actor)]
  },
  evolve=(s, e) => match e {
    Opened(owner~)         => { ..s, owner: Some(owner) }
    Deposited(amount~, ..) => { ..s, balance: s.balance + amount }
    Withdrawn(amount~, ..) => { ..s, balance: s.balance - amount }
    Closed(..)             => { ..s, closed: true }
  },
  is_terminal=s => s.closed,
)
```

Test it without a database, a runtime, or `async`:

```moonbit
let alice : @strata.Actor = @strata.Actor("user:alice")

test "withdrawals cannot exceed the balance" {
  @testing.spec(account)
    .acting_as(actor=alice)
    .given([Opened(owner=alice), Deposited(amount=50, by=alice)])
    .when(Withdraw(amount=80))
    |> debug_inspect(content="Err(Insufficient(balance=50, requested=80))")
}

test "only the owner can withdraw" {
  @testing.spec(account)
    .acting_as(actor=@strata.Actor("user:mallory"))
    .given([Opened(owner=alice), Deposited(amount=50, by=alice)])
    .when(Withdraw(amount=10))
    |> debug_inspect(content="Err(NotOwner)")
}
```

Run it:

```moonbit
async fn main {
  let rt = @rt.Runtime(@store.MemoryStore())
  let accounts = rt.handler(account)
  let ctx = @strata.Context(actor=alice)
  accounts.execute("acc-1", Open, ctx~) |> ignore
  let out = accounts.execute("acc-1", Deposit(amount=100), ctx~)
  println("v\{out.version}: \{Repr(out.events.map(r => r.event))}")   // v2: [Deposited(amount=100, by=Actor("user:alice"))]
}
```

Switch to PostgreSQL by passing another `EventStore` implementation. Nothing above changes.

```moonbit
let rt = @rt.Runtime(@store_pg.PgStore::connect(url))   // planned: tanden-inc/strata/store/pg
```

## Design

Strata is small on purpose. Eight decisions explain almost all of it.

### 1. Deciders, not aggregates

A domain is a `Decider[C, E, S]`: an initial state, `decide : (C, S, Env) -> Array[E] raise`, and `evolve : (S, E) -> S`. There is no base class, no `apply` method to override, no lifecycle. This is the functional formulation that F# and TypeScript event sourcing communities converged on, and it fits MoonBit better than it fits either of those: enums give you the closed event set, `raise` gives you typed rejection, and immutability makes `evolve` a fold with no aliasing questions. The table of *what is rejected and what is recorded* that you drew on the whiteboard is the `match` in `decide`.

Deciders are built with `Decider(...)` and labelled arguments; optional parts (`advise`, `tags`, `is_terminal`) are simply omitted. `Decider[C, E, S, N]` always names its notice type; a decider without advice uses `Unit`. Strata never exposes a public struct literal as an API surface, so the library can add capabilities without breaking a single call site.

### 2. Two kinds of domain, one shape

Some domains are *guard-first*: a bank account rejects an overdraft, and `decide` is the gatekeeper. Others are *record-first*: an expense system records the overspend, flags it, and leaves the judgement to a person, and `decide` rarely raises at all. Most real systems are both, in different places.

Strata gives one shape to both. `decide` answers exactly one question — *what is recorded, or why not* — and stays two-valued. A second pure function, `advise : (C, S, Env) -> Array[N]`, runs beside it over the same command and state, and answers a different question: *what should the caller know*. Notices are returned in the `Outcome`, never appended to the log, and never able to block. Keeping the two apart keeps `decide` provable and keeps the log honest: a warning is a derivation, and derivations do not belong in the source of truth.

### 3. Effects live in the types; facts of the invocation arrive in `Env`

`decide` is neither `async` nor does it take a store. It is a compile error to call a clock, read a stream, or generate an ID inside it. What a decision may legitimately depend on beyond the command and the state — who is acting, on whose behalf, what time it is, and *what the IDs of the events it is about to emit will be* — arrives as a value, `Env`, supplied by the runtime and fixed by tests. Everything effectful lives in `Runtime`, whose functions are `async` and `raise`. Reading a Strata codebase, you always know where the IO is; a domain package that does not import `strata/runtime` *cannot* perform any.

### 4. Adding is a compile error, not a runtime surprise

Events are closed sums. `evolve` and every read model's `apply` must match exhaustively. When you add `FeeCharged`, the build fails at every site that needs to care, and passes only when you have decided what each of them does. Cross-context evolution is handled where it belongs — in the serialized format — so closedness costs nothing at the boundary.

### 5. Serialization is derived, and derived output is the storage format

Strata stores exactly what `derive(ToJson)` produces — `["Deposited", {"amount": 100, "by": "user:alice"}]` for a variant with a payload, `"Closed"` for one without — alongside a schema version. The event type name is read back out of that value (`TagStyle::Flat`; applications that prefer `derive(ToJson(style="legacy"))` get `{"$tag": "Deposited", ...}` and configure `TagStyle::Legacy(tag_key="$tag")`). Upcasting is a chain of `Json -> Json` functions applied at read time. You never write a codec and you never register a type name.

### 6. One `Selection` for reads, subscriptions, and boundaries

A `Selection` names a set of events: by stream, by category, by type, by tag, or by any combination. The same value drives a paged read (`rt.read`), a fold into a view (`rt.fold`), a read model's sources, a reactor's subscription, and — as an `AppendCondition` — a Dynamic Consistency Boundary on writes. Because the write side and the read side share one vocabulary, anything you can guard you can also view, and anything you can view you can also react to. (It is called `Selection` and not `Query` so that it can live in the same file as a GraphQL schema without a fight.)

### 7. Pure core, async shell, build-time store selection

`strata/core` has no IO and compiles to every target — including the browser, where it powers command preview. `strata/runtime` is the async shell. The `EventStore` contract is a trait with `async` methods: `MemoryStore` is the default implementation, PostgreSQL (native) and a JS-host adapter are passed to `Runtime(store)` instead. The contract test suite runs against every store, so an adapter that passes it behaves like every other adapter. (Build-time selection through a virtual package may come later; see `docs/adr/0001-store-as-trait.md`.)

### 8. Tests are specifications; laws and proofs are on the menu

Given/When/Then over plain values, with expected events written by `moon test --update` and reviewed as diffs. Property tests for laws such as *replay equals snapshot plus tail*, *out-of-scope events do not change a DCB state*, and *a reversal stays inside its target's boundary*. And for the invariants that matter most, `moon prove` obligations over `decide` and `evolve`, which are pure functions and therefore provable.

## Tour

Each section below is one thing an event-sourced system has to get right, and the smallest Strata code that gets it right. The full versions live in [`examples/`](examples/); the [`ledger`](examples/ledger) example is the reference for DCB, advice, reversals, and the read side.

### Commands and optimistic concurrency

A command runs as *read → fold with `evolve` → `decide` (and `advise`) → append with the version you read*. The runtime does this every time, so you never forget the last step.

```moonbit
let accounts = rt.handler(account)
let out = accounts.execute("acc-1", Deposit(amount=100), ctx~)
// out.events   : [Recorded[AccountEvent]]  — what was appended, with IDs and positions
// out.notices  : []                        — advice; see below
// out.version  : 2                         — stream version after the append; hand it out as an ETag
// out.position : 41                        — global position; what async read models chase
```

If another writer got there first, `execute` raises `AppendConflict`. Because `decide` is pure, "read again and re-decide" is always safe, so you can ask for it declaratively:

```moonbit
let accounts = rt.handler(account, retry=@rt.Retry::on_conflict(max=3))
```

Retry applies to conflicts only: the runtime re-runs a command when the error `is AppendConflict`. Domain errors are your own `suberror`s and are never retried.

Clients can participate too. Pass the version they last saw and the store enforces it:

```moonbit
accounts.execute("acc-1", Withdraw(amount=30), ctx~, expected=Exact(version_from_if_match))
```

`ExpectedVersion` is `Any | NoStream | Exact(Int)`. `NoStream` means "create only", which is how you make IDs unique without a lookup table.

### Advice: informing without blocking

A budget code that may be overspent, a timesheet that may exceed the plan, a shipment that may miss its window: in many domains the correct behaviour is to record the fact and tell someone, not to refuse. Writing that with `raise` is wrong (it blocks), and writing it as an event is wrong (it puts a derivation in the log). `advise` is the third option.

```moonbit
pub(all) enum ChargeNotice {
  WillOverrun(landing~ : Int)
  OutsidePeriod(period~ : Period)
  UnfundedCode
} derive(Eq, Debug, ToJson)

pub let charge : @strata.Decider[ChargeCmd, ChargeEvent, CodeLedger, ChargeNotice] = @strata.Decider(
  category="code",
  initial=CodeLedger::empty(),
  decide=(cmd, s, env) => match cmd {
    // record-first: nothing here raises except malformed input
    Charge(amount~, ..) if amount <= 0 => raise ChargeError::NonPositive(amount~)
    Charge(amount~, reference~)        => [Charged(id=env.ids.at(0), amount~, reference~, by=env.actor)]
    Explain(reason~, landing~)         => [OverrunExplained(reason~, landing~, by=env.actor)]
  },
  advise=(cmd, s, env) => match cmd {
    Charge(amount~, ..) if s.balance - amount < 0   => [WillOverrun(landing=s.balance - amount)]
    Charge(..) if !s.period.contains(env.now)       => [OutsidePeriod(period=s.period)]
    Charge(..) if s.budget == 0                     => [UnfundedCode]
    _ => []
  },
  evolve=...,
)
```

Rules of advice:

- `advise` receives exactly what `decide` receives, so a notice can be as informed as a rejection.
- Notices come back in `out.notices`. They are not stored, not replayed, not part of any read model. If a fact deserves to persist — *the responsible person explained the overrun* — that is an event, recorded by a command, as above.
- `advise` is evaluated only when `decide` succeeds. A rejected command gets its error, not commentary.
- The fourth type parameter names the notice type. `Decider[C, E, S, Unit]` is a decider with no advice.

In tests, advice is a first-class expectation alongside events:

```moonbit
test "charging past the balance is recorded and flagged" {
  let spec = @testing.spec(charge).given([Budgeted(amount=100, by=alice), Charged(id=EventId("c-1"), amount=80, reference="inv-1", by=alice)])
  spec.when(Charge(amount=50, reference="inv-9"))   |> debug_inspect(content="Ok([Charged(id=EventId(\"evt-0001\"), amount=50, reference=\"inv-9\", by=Actor(\"user:alice\"))])")
  spec.advice(Charge(amount=50, reference="inv-9")) |> debug_inspect(content="[WillOverrun(landing=-30)]")
}
```

### Preview: the same decision in the browser

Because `strata/core` has no IO, it compiles to `wasm-gc` and `js`. A `Decider` is a value, so the client can hold the same one the server runs. Give it a state and an environment, and it will tell you what a command *would* do — the rejection, the events, the advice — before a request is sent:

```moonbit
// in the browser, with a state fetched from the server (a live view, or a snapshot — both are `Eq`)
let preview = @strata.Preview(charge, state~, env=@strata.Env(actor=me, now=@strata.Instant(js_date_now_ms)))
let outcome = preview.of(Charge(amount=50, reference="inv-9"))
match outcome.result {
  Ok(events) => show_confirmation(events, warnings=outcome.notices)
  Err(e)     => show_inline_error(e)
}
```

The server remains the authority: the client's preview is over a possibly stale state, and the real `execute` may see a newer one. But the *logic* is identical by construction, so the warning the user sees is the warning the server would compute. There is no second implementation of the rules in the frontend to drift.

`Preview` and `@testing.spec` are the same machinery (`Decider::run`) with different ergonomics; both are pure and target-independent.

### Idempotency

Networks retry. Reactors redeliver. The same command *will* arrive twice, and the answer is not to teach every `decide` about duplicates.

```moonbit
let a = accounts.execute("acc-1", Deposit(amount=100), ctx~, idempotency_key="req-7f3a")
let b = accounts.execute("acc-1", Deposit(amount=100), ctx~, idempotency_key="req-7f3a")
assert_eq(a.version, b.version)
assert_true(b.deduplicated)
```

The key is stored in event metadata; no extra table. Reactors set it automatically from the event they are reacting to, so in practice you only think about it at the API boundary.

### Environment, identity, and time

Strata separates four things that other libraries blur together.

**The command** is the intent: `Withdraw(amount=80)`. It does not say who, or when — those are not part of the intent.

**The environment** (`Env`) is what a decision may depend on besides the command and the state: the acting principal, the tenant, the current instant, the identities of the events about to be emitted, and any typed extras your application declares. It is passed *into* `decide` and `advise` as a value. A rule such as *only the owner may withdraw* is written once, against `env.actor`, and tested by fixing the environment in the spec.

**The event** is a fact. Facts legitimately include who acted and when the business says it happened, so `decide` stamps `env.actor` (and, when the meaning is "as of", an instant) into the event body where the domain cares. This is not a duplicate of the command's actor — commands do not carry one — it is the decision turning an invocation fact into a domain fact.

**The metadata** (`Context`) is the audit envelope: correlation and causation IDs, the actor, the tenant, the idempotency key. It exists whether or not the domain chose to record the actor in the event. The runtime derives `Env` from `Context`, so callers supply one thing.

```moonbit
pub struct Env {
  actor : Actor            // who is acting
  tenant : String?         // also becomes a stream-name prefix: "t1/account-acc-1"
  now : Instant            // from the runtime Clock; fixed in tests
  ids : IdBatch            // the IDs the events emitted by this decision will carry
  extra : Json             // application-declared facts (e.g. a rate table version)
}
// built with Env(actor~, now~, tenant?, ids?, extra?) so fields can be added later
```

**Identity is supplied, not generated.** `decide` cannot make a ULID — that would be an effect. Yet events often need to be referred to later: a reversal names the entry it undoes, a settlement names the reservation it settles. So the runtime reserves the IDs *before* calling `decide`, and `env.ids.at(i)` is the ID that the *i*-th emitted event will receive. `decide` can write it into the event body; `evolve` can index state by it; and the runtime guarantees `recorded.id == recorded.event.id` wherever you chose to embed it. In `testing.spec` the batch is deterministic (`evt-0001`, `evt-0002`, …), so snapshots stay stable.

```moonbit
(Reserve(amount~, ref~), _) => [Reserved(id=env.ids.at(0), amount~, ref~, by=env.actor)]
(Settle(reservation~), _) if !s.reservations.contains(reservation) =>
  raise LedgerError::UnknownReservation(reservation~)
```

What consumers see is the envelope:

```moonbit
pub struct Recorded[E] {
  id : EventId            // ULID — the basis for idempotency, causation, and dedup
  position : Position
  stream : StreamId
  version : Int
  event_type : String
  event : E
  tags : Array[Tag]       // the event's own tags; system tags ($stream:, $category:, $tenant:) stay in the store
  recorded_at : Instant
  meta : Metadata         // correlation_id, causation_id, actor, tenant, idempotency_key, extra : Json
}
```

Time is a runtime concern. `env.now` is the default source; a command may still carry an explicit instant when the business meaning is "as of". Either way the runtime's `Clock` is injectable, so replays and tests are deterministic:

```moonbit
let rt = @rt.Runtime(store, clock=@rt.Clock::parse_fixed("2026-09-13T00:00:00Z"))
```

### Selections

`Selection` is how Strata names a set of events. It follows the Dynamic Consistency Boundaries specification: a selection is a list of items, each item is a set of event types (empty means any) *and* a set of tags that must all be present, and the items are OR-ed together.

```moonbit
Selection::stream(StreamId("account-acc-1"))           // one stream            ($stream: system tag)
Selection::category("account")                         // every stream in a category ($category:)
Selection::tags([Tag("code:X")])                       // events tagged code:X   (tags within an item: AND)
Selection::tags([Tag("code:X"), Tag("period:2026-09")]) // events tagged with both
Selection::types(["Moved", "Reserved"], tags=[Tag("code:X")])
Selection::any_of([Selection::tags([Tag("code:X")]), Selection::tags([Tag("code:Y")])])   // items: OR
Selection::all()                                       // the global log
```

Constructors normalise their input, so two selections that name the same set are `Eq` and hash alike; that is what
snapshot and checkpoint keys rely on. Streams, categories and tenants are ordinary tags that the store writes on
every event (`$stream:`, `$category:`, `$tenant:`), so one tag index serves every kind of read.

Three primitives consume a `Selection`, and everything else in the read side is built on them:

```moonbit
// Paged, position-ordered reads. Decode where the type is known.
let page = rt.read(Selection::tags([Tag("code:X")]), limit=50)
let history : Array[Recorded[LedgerEvent]] = page.decode()
// page.next : Position?   — pass as `after` for the next page

// Fold a selection into a value.
let balances = rt.fold(code_balances, Selection::tags([Tag("code:X")]))

// Subscribe from a position (what projectors and reactors use underneath).
rt.subscribe(Selection::category("allocation"), from=checkpoint)
```

`rt.live(view, category="account", id~)` is `rt.fold(view, Selection::stream(...))` with a nicer name, and returns the stream version alongside the value for use as an `ETag`.

### Read models

A read model is a fold over events. Write the fold once; choose where and how often it runs.

**A view over one selection**

```moonbit
pub(all) struct BalanceView { balance : Int; tx_count : Int } derive(Eq, Debug, ToJson, FromJson)

pub let balance_view : @strata.Projection[AccountEvent, BalanceView] = @strata.Projection(
  initial={ balance: 0, tx_count: 0 },
  apply=(v, e) => match e {
    Deposited(amount~, ..) => { balance: v.balance + amount, tx_count: v.tx_count + 1 }
    Withdrawn(amount~, ..) => { balance: v.balance - amount, tx_count: v.tx_count + 1 }
    Opened(..) | Closed(..) => v
  },
)
```

**A keyed view that fans out.** One event often belongs to several rows: a transfer touches the source and the destination. `keys` returns every key the event contributes to, and `apply` receives the key so each row can interpret the event from its own point of view. Keyed projections receive the full `Recorded[E]`, because rows frequently want `recorded_at`, `meta.actor`, or `id`.

```moonbit
pub let code_ledger : @strata.KeyedProjection[LedgerEvent, Code, CodeRow] = @strata.KeyedProjection(
  keys=r => match r.event {
    Moved(from~, to~, ..) => [from, to]
    Reserved(code~, ..) | Released(code~, ..) | Reversed(tags~, ..) => codes_in(r.event)
  },
  initial=CodeRow::empty(),
  apply=(code, row, r) => match r.event {
    Moved(from~, to~, amount~, ..) if code == from => { ..row, balance: row.balance - amount, out: row.out + 1 }
    Moved(to~, amount~, ..)        if code == to   => { ..row, balance: row.balance + amount, inbound: row.inbound + 1 }
    Reserved(amount~, ..)                          => { ..row, reserved: row.reserved + amount }
    ...
  },
)
```

**A view over several sources.** Cross-cutting screens — everything pending, projected landing balances — need events from more than one category. Declare each source with its own typed `apply`; Strata merges them in global position order. No wrapper enum.

```moonbit
pub let landing : @strata.MultiProjection[LandingView] = @strata.MultiProjection(initial=LandingView::empty())
  ..source(Selection::category("code"), (v, r : Recorded[CodeEvent]) => match r.event {
      Opened(period~, ..) => v.open(r.entity_id(), period)
      Closed(..)          => v.close(r.entity_id())
      _ => v
    })
  ..source(Selection::category("ledger"), (v, r : Recorded[LedgerEvent]) => v.apply_ledger(r))
  ..source(Selection::category("assignment"), (v, r : Recorded[AssignmentEvent]) => match r.event {
      Accepted(request~, ..) => v.add_future_charge(request)   // a fat event; see "Reaching for state"
      _ => v
    })
```

A note on what this relies on: merging sources by global position is well-defined because there is one log with one `Position`. That is a definition, not a limitation Strata intends to lift — if you split an application across stores, you need a merge with its own ordering semantics, which is a different tool.

**Where it runs**

```moonbit
// Live: fold on read. No cache, always current.
let (view, version) = rt.live(balance_view, category="account", id="acc-1")
let ledger = rt.fold_keyed(code_ledger, Selection::tags([Tag("period:2026-09")]))

// Inline: updated in the same transaction as the append. Strongly consistent.
let accounts = rt.handler(account, inline=[@rt.inline(balance_view, into="balances")])

// Async: a subscription with a checkpoint. Scales; eventually consistent.
let daemon = rt.projector("landing", landing, into="landing")
@async.with_task_group(g => { daemon.start(g); serve(g) })
```

Rows live in the store's `ViewStore` (`rt.views()`), keyed by table name and row key; the PostgreSQL store keeps them
in the same database so inline writes share the append's transaction.

Async projectors are at-least-once. Because `apply` is pure and the view is committed with its checkpoint in one transaction, the result is effectively-once without any dedup code. `daemon.rebuild()` replays into a fresh table and swaps it in; read models are disposable by design. `daemon.wait_for(position, timeout~)` blocks until the projector has passed a position — the piece an API layer needs to return a freshly-updated view after a write.

**Reaching for state.** Thin events (`Accepted(by~)`) keep the log honest but leave consumers without the details they need. Rather than copying the request into every downstream event, a read model or reactor can ask for the writer's state as it stood when the event was recorded:

```moonbit
let req = rt.state_at(assignment, r).request   // replay pinned to (r.stream, r.version): deterministic
```

`state_at` is a runtime call, so it is available to reactors and API handlers; a projection's `apply` is pure and
needs the fat event. Whether to ship fat events or lean on `state_at` is a domain trade-off; Strata supports both and the [design notes](docs/events-fat-or-thin.md) discuss when each wins.

### Reactors and process managers

Workflows that span streams are built from *react to an event, issue a command*. Failures are handled with compensating commands, not transactions. A reactor subscribes to a `Selection`, so it can follow a category, a tag, or a combination.

```moonbit
let transfer_pm = rt.reactor("transfer-pm", source=Selection::category("transfer"),
  (r : Recorded[TransferEvent]) => {
    let ctx = r.caused()   // inherits correlation_id; causation_id = r.id; idempotency_key = r.id
    match r.event {
      Requested(from~, amount~, ..) =>
        try {
          accounts.execute(from, Withdraw(amount~), ctx~) |> ignore
          transfers.execute(r.entity_id(), MarkDebited, ctx~) |> ignore
        } catch {
          AccountError::Insufficient(..) =>
            transfers.execute(r.entity_id(), MarkFailed(reason="insufficient"), ctx~) |> ignore
        }
      Debited => { /* credit the destination; compensate the source if that fails */ }
      Credited => transfers.execute(r.entity_id(), MarkCompleted, ctx~) |> ignore
      Completed | Failed(..) => ()
    }
  })
```

Three properties make redelivery harmless: the reactor checkpoints its position; `r.caused()` turns the triggering event's ID into the downstream idempotency key; and the `transfer` decider is a state machine that rejects out-of-order commands. Teams routinely write a dozen reactors without a single line that mentions duplicates. A reactor is an `async` closure over `Recorded[E]` — no base class, no annotations. To test one, run it against `@testing.runtime()` (a memory store with a fixed clock and sequential ids), call `reactor.catch_up()`, and snapshot what the log contains afterwards.

Two-party handshakes — *A requests, B accepts, nobody above them approves* — are a state machine plus `env.actor`, not a process manager. The [`ledger`](examples/ledger) example's sibling transfer and the [`assignment`](examples/assignment) example's request/accept are the reference shapes.

### Dynamic consistency boundaries

Some invariants do not fit in one stream. The canonical example is not uniqueness but *conservation*: moving budget between two cost codes must debit one and credit the other in a single, atomic fact, so the total is preserved by construction rather than repaired by a process manager.

With DCB, a command declares the set of events it reads as a `Selection`, and the store rejects the append if any event matching that selection appeared in between. The `Decider` and `DcbDecider` shapes are deliberately parallel:

```moonbit
pub(all) enum LedgerEvent {
  Moved(id~ : EventId, from~ : Code, to~ : Code, amount~ : Int, reason~ : String, by~ : Actor)
  Reserved(id~ : EventId, code~ : Code, amount~ : Int, reference~ : String, by~ : Actor)
  Released(code~ : Code, reservation~ : EventId, by~ : Actor)
  Reversed(of~ : EventId, tags~ : Array[Tag], reason~ : String, by~ : Actor)   // see Reversals
} derive(Eq, Debug, ToJson, FromJson)

// Tags say which boundaries an event may belong to. Computed from the event alone.
fn code_tag(code : Code) -> Tag { Tag("code:\{code}") }
fn ledger_tags(e : LedgerEvent) -> Array[Tag] {
  match e {
    Moved(from~, to~, ..)                  => [code_tag(from), code_tag(to)]
    Reserved(code~, ..) | Released(code~, ..) => [code_tag(code)]
    Reversed(tags~, ..)                    => tags
  }
}

pub(all) struct Balances { of : Map[Code, Int]; reserved : Map[Code, Int]; entries : Map[String, Entry] } derive(Eq, Debug, ToJson, FromJson)

pub let ledger : @strata.DcbDecider[LedgerCmd, LedgerEvent, Balances, Unit] = @strata.DcbDecider(
  category="ledger",                                     // events still get a stream …
  stream=cmd => cmd.from,                                // … named after the source code
  scope=cmd => Selection::any_of([                       // the boundary is a selection, not an ID
    Selection::tags([code_tag(cmd.from)]),
    Selection::tags([code_tag(cmd.to)]),
  ]),
  tags=ledger_tags,
  initial=Balances::empty(),
  decide=(cmd, s, env, _scope) => match cmd {
    Move(from~, to~, amount~, reason~) if s.available(from) < amount =>
      raise LedgerError::Insufficient(code=from, available=s.available(from), requested=amount)
    Move(from~, to~, amount~, reason~) =>
      [Moved(id=env.ids.at(0), from~, to~, amount~, reason~, by=env.actor)]
    ...
  },
  evolve=(s, e, scope) => match e {                      // ← evolve knows its scope; see next section
    Moved(id~, from~, to~, amount~, ..) => {
      let s1 = if scope.owns(code_tag(from)) { s.credit(from, -amount) } else { s }
      let s2 = if scope.owns(code_tag(to))   { s1.credit(to, amount) }   else { s1 }
      s2.remember(id, ledger_tags(e))
    }
    ...
  },
)

let codes = rt.dcb_handler(ledger)
codes.execute(Move(from="ORG-CORE01", to="PRJ-14", amount=2_000, reason="Q4 kickoff"), ctx~)
```

Under the hood this is the same `EventStore::append`, with `AppendCondition::Dcb(selection~, after~)` instead of `Stream(id, version)`; `after` is the log head the handler observed before reading its scope. The event lands in the `ledger-ORG-CORE01` stream *and* carries both tags, so a reactor can follow `Selection::category("ledger")` or `Selection::tags([Tag("code:PRJ-14")])`, and a view can fold either. The PostgreSQL store will index tags with GIN and check the condition inside the insert transaction.

Use streams by default; use DCB where the invariant crosses them. And notice that in a record-first domain, DCB is rare: a *charge* against a code that may go negative needs no boundary at all — it is an append to the code's stream with a notice. Only the *move*, which must not create money, needs the boundary. Most record-first ledgers are DCB-light.

### The partial world

A DCB state is a fold over *only the events the scope selected*. That is what makes the boundary small and the append cheap, and it has one consequence worth stating plainly: an event may mention things the scope does not own. `Moved(from=X, to=Y)` matched the scope `code:X`, and its effect on `Y` must be ignored — `Y` is outside this decision's world, and its balance is not being read, so it must not be written to state either.

Strata makes this discipline mechanical rather than remembered:

- `evolve` on a `DcbDecider` receives the `Scope`. `scope.owns(tag)` answers "is this tag part of the selection that produced these events?" State updates for anything else are simply not made.
- `@testing.dcb_spec` checks the property directly: removing every out-of-scope event from the history must not change the resulting state. A leak is a failing test, not a subtle balance drift.
- `Scope` is also available to `decide` and `advise`, so a rule can refuse to act — or warn — about a code it did not read.

```moonbit
test "state depends only on the scope" {
  @testing.dcb_spec(ledger)
    .given(history)                       // may contain events about codes outside the scope
    .scope_of(Move(from="X", to="Y", amount=10, reason="t"))
    .assert_scope_closed()                // state(history) == state(history ∩ scope)
}
```

Two more things follow from the partial world. **Hot tags** — a root code that appears in thousands of moves — are handled the same way hot streams are: DCB handlers accept `snapshot=`, keyed by the normalized selection and position, and period tags (`period:2026-Q4`) in the scope keep the selected set small. Both are described under [Closing the books and snapshots](#closing-the-books-and-snapshots).

### Reversals

Stored events are never deleted or edited. A mistake is corrected by recording that it was a mistake. In ledger-shaped domains this is not an edge case but a daily operation, so Strata gives it a shape and a law.

A reversal event names the entry it undoes by ID — which is why `env.ids` exists — and **carries its target's tags**, so that it lands inside the same consistency boundaries and the same views as the thing it reverses. `tags` is computed from the event alone, on purpose: a tag that depended on state would make the boundary depend on who was looking.

```moonbit
(Reverse(target~, reason~), _) => match s.entries.get(target) {
  None        => raise LedgerError::UnknownEntry(target~)
  Some(entry) if entry.reversed => raise LedgerError::AlreadyReversed(target~)
  Some(entry) => [Reversed(of=target, tags=entry.tags, reason~, by=env.actor)]
}
```

The law that keeps this honest is in `testing`:

```moonbit
test "reversals stay inside their target's boundary" {
  @testing.dcb_reversal_law(
    ledger,
    reverses=e => match e { Reversed(of~, ..) => Some(of); _ => None },
    identity=e => match e { Moved(id~, ..) | Reserved(id~, ..) => Some(id); _ => None },
    histories=[history_with_reversal],
  )
  // ∀ history: tags(reversal) ⊇ tags(target); pass `restores=` to also check the effect is undone
}
```

Because the reversal is itself an event, the fact that a correction happened, who made it, and why, are as permanent as the entry that was corrected. [`docs/reversals.md`](docs/reversals.md) covers partial reversals, reversing a reversal, and closing periods with open corrections.

### Schema evolution

Stored events are never rewritten. Change happens at read time, in three shapes:

```moonbit
let codec = @codec.JsonCodec(schema_version=2)
  ..migrate("Withdrawn", from=1, @codec.Upcast::add_field("fee", 0))   // additive change: fill a default
  ..rename("Opened", to="AccountOpened")                                // stored type name → current variant
  .deprecated("LegacyFeeCharged", replaced_by="Withdrawn")              // still readable, skipped by folds

let rt = @rt.Runtime(store, codec~)
```

Upcasters are `Json -> Json` and unit-testable. Keep a JSON fixture of every event shape you have ever written and let the suite prove they all still decode:

```moonbit
test "every historical shape still decodes" {
  let report : @testing.FixtureReport[AccountEvent] =
    @testing.Fixtures::from_json(load_fixtures("fixtures/account")).all_decode(codec)
  inspect(report.decoded.length(), content="17")
}
```

### Closing the books and snapshots

Streams and tags that grow forever — accounts, root cost codes — are closed per period, the way accountants have always done it. The closing event carries the summary; the next period opens with it, and the period becomes part of the stream name or the tag set.

```moonbit
(ClosePeriod(next~), { period: Some(p), .. }) =>
  [PeriodClosed(period=p, closing_balance=s.balance, next~, by=env.actor)]

// DCB: put the period in the scope so the selected set stays bounded
scope=cmd => Selection::tags([Tag("code:\{cmd.code}"), Tag("period:\{cmd.period}")])
```

A reactor opens the next period with `expected=NoStream`, so a redelivered close cannot open it twice. `is_terminal` lets the runtime reject commands on a closed stream right after the fold, before `decide` runs. Reach for this before you reach for snapshots.

Snapshots are a cache of state, never the truth. They live in a side stream so the log stays clean, carry a version stamp so you can invalidate them by changing one number, and work for both kinds of decider:

```moonbit
let accounts = rt.handler(account, snapshot=@rt.SnapshotPolicy::every(200, version=3))
let codes    = rt.dcb_handler(ledger, snapshot=@rt.SnapshotPolicy::every(500, version=1))  // keyed by (normalised selection, version)
```

### Integration events

Domain events are yours to change; what leaves your service is a contract. Translate at the edge, and note that the event store is already a durable log — there is no separate outbox table to keep in sync.

```moonbit
pub(all) enum LedgerPublicEvent {
  BudgetMoved(from~ : Code, to~ : Code, amount~ : Int, reason~ : String, at~ : Instant)
} derive(Debug, ToJson)

let publisher = rt.reactor("ledger-public", source=Selection::category("ledger"), (r : Recorded[LedgerEvent]) => {
  match r.event {
    Moved(from~, to~, amount~, reason~, ..) =>
      bus.publish(topic="ledger.v1", key=r.id.to_string(),
        BudgetMoved(from~, to~, amount~, reason~, at=r.recorded_at))
    _ => ()
  }
})
```

At-least-once delivery, keyed by event ID so consumers can dedup.

### Sealing and shredding

*Declared in 0.1; encryption lands in 1.1.* An immutable log and privacy are reconciled with keys, not deletion. Strata encrypts marked fields — in event bodies *and* in metadata — with a per-subject key, and offers two things you can do with that key.

**Shredding** destroys the key. The event remains; the field becomes permanently unreadable. This is "forget me".

**Sealing** keeps the key in the key store but withholds it from ordinary reads. The field is readable only through `rt.unseal` with an explicit capability, and every unseal is itself recorded. This is how you make a record *anonymous to the organization* while keeping it *attributable under audit* — an anonymous piece of feedback, a whistleblower report, a sealed bid. The log does not forget who acted; it declines to say, unless asked with authority.

```moonbit
let codec = @codec.JsonCodec(schema_version=2)
  ..shred(fields=[FieldPath("Opened.owner"), FieldPath("Registered.email")], redacted_as="<redacted>")
  .seal(meta=["actor"], when=ctx => ctx.flag("anonymous"))
let rt = @rt.Runtime(store, codec~, keys=my_key_store)   // any `KeyStore`; MemoryKeyStore by default

rt.forget(category="account", id="acc-1")   // destroys the key, appends a $strata.forgotten marker, notifies projectors

r.meta.actor                                // => None while sealed (ordinary read)
rt.unseal(stored, capability="auditor")     // => metadata with the actor; recorded as $strata.unsealed
```

Today `forget` destroys the key and appends a `$strata.forgotten` marker, and `unseal` records a `$strata.unsealed`
marker; field encryption itself is the 1.1 work item.

Deciders and read models never see the encryption. After shredding, `Opened(owner="<redacted>")` decodes normally; `on_forgotten` on a projector is where you drop your own copies. Who may hold an unseal capability is your application's decision; Strata only guarantees that using one leaves a mark.

### HTTP and GraphQL

*Planned; not part of the 0.1 interface.* Strata will ship thin adapters for both, and the same runtime facts drive both: `out.version` is an `ETag`, `out.position` is what you wait for, typed rejections are your error contract.

**HTTP.** Optimistic concurrency extends to clients: return the version as an `ETag`, accept it back as `If-Match`. Domain errors map to 422, conflicts to 409, idempotent replays to 200. Tag-scoped history is a paged read.

```moonbit
(POST, ["accounts", id, "deposit"]) => {
  let body : DepositBody = req.json()
  let out = @strata_http.run(res, () =>
    accounts.execute(id, Deposit(amount=body.amount),
      ctx=@strata.Context::from_http(req),
      expected=req.if_match_version(),
      idempotency_key=req.header("Idempotency-Key")))
  res..status(201)..etag(out.version)..json({ "events": out.events, "notices": out.notices })
}
(GET, ["codes", code, "history"]) => {
  let page = rt.read(Selection::tags([Tag("code:\{code}")]), after=req.cursor(), limit=50)
  let items : Array[Recorded[LedgerEvent]] = page.decode()
  res..json({ "items": items, "next": page.next })
}
```

**GraphQL.** A `suberror` is a closed set of typed rejections; a GraphQL result union is exactly that. A `Selection` is a paged, cursor-based read; a GraphQL connection is exactly that. And `rt.subscribe` is a subscription. `strata/graphql` maps each to each:

```graphql
type Mutation {
  move(from: ID!, to: ID!, amount: Int!, reason: String!, expectedVersion: Int): MoveResult!
}
union MoveResult = Moved | Insufficient | NotOwner | Conflict     # from LedgerError + AppendConflict

type Moved   { events: [LedgerEvent!]!, notices: [LedgerNotice!]!, version: Int!, position: Position! }
type Code {
  id: ID!
  balance: Int!                                                   # inline projection
  landing: Landing!                                               # async projection; resolver waits for position
  history(after: Cursor, first: Int): LedgerEventConnection!      # rt.read(Selection::tags([Tag("code:" + id)]))
}
type Subscription { pending: PendingBoard! }                      # rt.subscribe(Selection::…)
```

```moonbit
// resolver for Mutation.move
let out = codes.execute(Move(..), ctx=@gql.context(req), expected=@gql.expected(args.expectedVersion))
landing_projector.wait_for(out.position, timeout=Duration::seconds(2))   // read-your-writes for the returned Code
```

An honest note: MoonBit's `derive` covers a fixed set of traits, so the SDL and resolver skeletons are produced by `moon run tanden-inc/strata/gen graphql` from your enums and suberrors rather than derived at compile time. The generated code is checked in and type-checked against your domain, so a renamed variant still fails the build — but the "no codecs, no registries" promise of the storage format does not extend to your public schema. [`docs/graphql.md`](docs/graphql.md) covers cursors, N+1 over keyed projections, and error mapping.

## Testing

Strata treats tests as the primary interface for reading a domain.

**Specifications.** Given past events, when a command, then events or an error — and, separately, advice. Values in, values out. The environment is part of the given; event IDs are deterministic.

```moonbit
test "close requires zero balance, then succeeds" {
  let spec = @testing.spec(account).acting_as(actor=alice)
    .given([Opened(owner=alice), Deposited(amount=50, by=alice)])
  spec.when(Close)                            |> debug_inspect(content="Err(NotEmpty(balance=50))")
  spec.when_all([Withdraw(amount=50), Close]) |> debug_inspect(content="Ok([Withdrawn(amount=50, by=Actor(\"user:alice\")), Closed(by=Actor(\"user:alice\"))])")
}
```

`debug_inspect` snapshots mean `moon test --update` writes the expected events and you review them as a diff. One rule, ten lines; put the same blocks in a `README.mbt.md` and your documentation is executable. The full suite for this domain is in [`examples/account`](examples/account).

**Laws.** Properties that must hold for every history, with `moonbitlang/quickcheck`:

```moonbit
test "replay equals snapshot plus tail" {
  @qc.quick_check((events : Array[AccountEvent]) => {
    let k = events.length() / 2
    account.replay(events.iter()) ==
      account.replay_from(account.replay(events.iter().take(k)), events.iter().drop(k))
  })
}
```

`@testing.replay_law`, `@testing.advice_law`, `@testing.dcb_spec(...).assert_scope_closed()` and `@testing.reversal_law` / `dcb_reversal_law` are ready-made laws for the same idea, applied to snapshots, advice, the partial world and corrections.

**Proofs.** For the invariants you cannot afford to get wrong, `decide` and `evolve` are pure and therefore admissible to `moon prove`. The plan for [`examples/ledger`](examples/ledger) is to prove that the sum of balances across all codes is invariant under every accepted `Move` and every `Reversed`. This integration is experimental (see [Stability](#stability)).

**Contracts.** Every `EventStore` implementation runs the same suite: append semantics, expected versions, DCB conditions, selection semantics, subscription ordering, idempotency scopes, sealing.

```moonbit
async test "store contract" {
  @testing.contract(make=() => @store_pg.PgStore::connect(env("STRATA_TEST_PG")))
}
```

## Architecture

```
            commands (+ Context)                                      selections
                    │                                                     │
       ┌────────────▼─────────────┐                    ┌──────────────────▼──────────────────┐
       │  CommandHandler          │                    │  read(sel) · fold(view, sel)         │
       │  reserve ids → read(scope)│                   │  live(view, id) · wait_for(position) │
       │  → replay → decide/advise│                    │  Projection · KeyedProjection        │
       │  → append(condition, es) │                    │  MultiProjection(..)..source(sel)    │
       └────────────┬─────────────┘                    └──────────────────▲──────────────────┘
                    │  Stream(id, version) | Dcb(selection, after)        │ subscribe(sel, from)
       ┌────────────▼─────────────────────────────────────────────────────┴───────────────────┐
       │                          EventStore  (trait)                                         │
       │             MemoryStore (default) │ postgres (native, planned) │ js host (planned)     │
       └───────────────────────────────────────────────────────────────────────────────────────┘
                    ▲
                    │ Recorded[E]   (+ state_at, unseal)
       ┌────────────┴─────────────┐
       │  reactor(source=sel)     │──── commands (r.caused()) ────▶ other handlers
       │  process managers        │──── integration events ───────▶ outside world
       └──────────────────────────┘

  pure (any target, incl. browser): core, codec, Preview
  async (native, js, wasm): store, runtime, testing; later http, graphql
```

| Package | Contents | Effects | Targets |
|---|---|---|---|
| `strata/core` (`@strata`) | `Decider`, `DcbDecider`, `Env`, `IdBatch`, `Scope`, `Selection`, `Projection`, `KeyedProjection`, `MultiProjection`, `Recorded`, `Context`, `Outcome`, `AppendCondition`, `Preview`, ids and time | none | all |
| `strata/codec` (`@codec`) | `JsonCodec`, `TagStyle`, `Upcast`, shredding and sealing declarations | none | all |
| `strata/store` (`@store`) | `EventStore`, `Subscription`, `ViewStore`, `KeyStore` traits; `MemoryStore` | `async` | native, js, wasm |
| `strata/store/pg` | PostgreSQL adapter, tag index, inline views, key store | `async` | native (planned) |
| `strata/store/js` | Adapter over host drivers via `js_async` | `async` | js (planned) |
| `strata/runtime` (`@rt`) | `Runtime`, handlers, `read`/`fold`/`live`, projectors (`wait_for`, `rebuild`), reactors, `state_at`, `unseal`, snapshots, retry, clock | `async` | native, js, wasm |
| `strata/testing` (`@testing`) | `spec`, `dcb_spec`, laws, `Fixtures`, `contract`, `runtime()` test harness, generators | mixed | native, js, wasm |
| `strata/http` | `Context::from_http`, `If-Match`/`ETag`, cursors, error mapping | `async` | planned |
| `strata/graphql` | context, result unions, connections over `Selection`, subscriptions, `gen graphql` | `async` | planned |

## Stores and targets

| | native | js | wasm-gc |
|---|---|---|---|
| Domain code, read models, `Preview` | ✓ | ✓ | ✓ |
| `MemoryStore`, runtime, `@testing` | ✓ | ✓ | wasm (not wasm-gc; `moonbitlang/async` does not target it) |
| PostgreSQL store | planned | planned (host driver) | — |
| Async projectors / reactors | ✓ | ✓ | — |
| HTTP / GraphQL integration | planned (`moonbitlang/async/http`) | planned (host) | — |

The planned PostgreSQL schema is a single `events` table (`position bigserial`, `stream_id`, `version`, `type`, `schema`, `data jsonb`, `meta jsonb`, `tags text[]`, `recorded_at`) with a unique `(stream_id, version)` index and a GIN index on `tags`, plus `checkpoints`, `snapshots`, `views` and `keys`. Every `Selection` compiles to one indexed `SELECT`. Migrations ship in the package and are applied with `@store_pg.migrate(pool)`.

## How Strata relates to other tools

Strata stands on ideas other communities worked out first. If you know them, here is the map:

| If you know… | Strata is… |
|---|---|
| **Emmett** (TypeScript) | the same Decider shape and PostgreSQL-first pragmatism, with the union type checked exhaustively, effects enforced by the compiler, advice beside decisions, and a read side that is a peer of the write side rather than a set of per-stream helpers. |
| **Equinox** (F#) | the same functional core; Strata trades Equinox's storage breadth for one store trait, one contract suite and a single runtime story. |
| **Marten** (.NET) | the same inline/async/live projection lifecycles over PostgreSQL, with multi-source and fan-out views as first-class values instead of subclasses, and without the document-database half. |
| **Commanded** (Elixir) | the same execute/apply split and process managers; Strata runs on structured-concurrency tasks instead of BEAM processes and is statically typed end to end. |
| **Axon** (Java) | a different philosophy: no annotations, no reflection, no server component. What Axon resolves at startup, Strata resolves at compile time. |
| **KurrentDB / EventSourcingDB** | not a competitor — Strata is a library. A KurrentDB adapter for `EventStore` is on the roadmap. |
| **The DCB specification** | implemented faithfully: `Selection` is the spec's query, `AppendCondition::Dcb` is its append condition — and the same `Selection` also drives reads and subscriptions. |

## Stability

Strata follows semantic versioning; until 1.0, minor releases may still adjust the surface below, and every change shows up in the committed `pkg.generated.mbti` files.

**Stable at 1.0** — breaking changes only in 2.0: `strata/core` (including `Selection` semantics, `Env`, `IdBatch`, `Scope`, and the `Decider` / `DcbDecider` / `Projection` constructors), `strata/codec`, `strata/runtime`, the `EventStore` contract and its contract test suite, the in-memory and PostgreSQL stores, `strata/testing`, the on-disk PostgreSQL schema (forward-migrated), and the stored JSON format.

**A rule about the stable surface.** Every public struct in the stable packages is readonly and constructed through a function with labelled arguments (`Env(actor~, now~)`, `Context(actor~)`, `Decider(...)`); only identifier newtypes (`EventId`, `Actor`, `Tag`, ...) are open for literal construction. No struct with construction-time invariants is exposed as a literal. This is what lets Strata add a capability — a new optional argument, a new `Env` field — in a minor release without breaking any caller, and it is why `advise`, `tags` and `is_terminal` are optional arguments rather than fields you have to write.

**Experimental** — may change in minor releases, always behind an explicit import: the JS host store, `moon prove` helpers, the `gen graphql` tool's output format, and the KurrentDB adapter when it lands.

Strata is developed against the latest stable MoonBit toolchain (0.10 line) and `moonbitlang/async` 0.21; CI runs `moon check --deny-warn`, `moon fmt --check`, `moon info` drift detection and the test suites on native and js.

## FAQ

**Should I event-source everything?**
No. Event-source the parts of the system where history is the product: money, inventory, allocation, audit, anything you will be asked to explain later. Strata is comfortable living next to a CRUD service in the same process.

**When do I `raise`, when do I `advise`, and when do I record an event?**
`raise` when the fact must not exist — money created from nothing, an action by someone who cannot take it. `advise` when the fact may exist but someone should know — an overspend, a late entry, an unusual amount. Record an event when a *person* responds to that knowledge — an explanation, an acknowledgement, a correction. The log holds what happened; advice holds what is worth noticing; neither pretends to be the other.

**Why is `advise` separate from `decide` instead of one function returning both?**
Because they answer different questions and are held to different standards. `decide` is the function you prove things about and the one whose output the store persists; keeping it two-valued keeps those obligations small. `advise` is free to be heuristic, to change weekly, to differ per deployment. Bundling them would make the proof surface include the heuristics.

**Why closed enums? I want plugins to add events.**
Because exhaustiveness is the feature. A bounded context owns its event set; other contexts consume the serialized form, which is open by nature. If you need extension inside a context, that is usually two contexts.

**Why does `decide` take an `Env` instead of putting the actor in every command?**
Because the actor, the tenant, and the time are facts about the *invocation*, not about the intent. Commands stay pure intents. Events, being facts, *do* carry the actor where the domain cares — `decide` copies it from `env.actor` — and `meta.actor` records it regardless, for audit. Three roles, three places, no drift.

**Why does the runtime reserve event IDs before `decide` runs?**
Because a decision often needs to *name* what it is recording — a reservation to settle later, an entry to reverse later — and `decide` is not allowed to generate anything. Reserving IDs up front costs nothing (ULIDs are cheap, unused ones are discarded) and gives `decide` a stable, test-deterministic way to refer to its own output. `evolve` stays a fold over plain events because the IDs are *in* the events.

**Why `raise` instead of `Result`?**
Because `raise` is checked and cheap, and because it lets `decide` say what can go wrong in its signature without wrapping every return. Where you want a value, `try ... catch` gives you one. `testing.spec` and `Preview` return `Result` for exactly this reason.

**Streams or DCB?**
Streams when one entity owns the invariant. DCB when the invariant is a relationship between entities — conservation, exclusivity, a cap across a group. Both go through the same `append`, the same `Selection`, and the same read side, so choosing late is cheap. Record-first domains need DCB less often than you expect: an entry that is allowed to go negative needs no boundary.

**Is Preview safe to trust in the client?**
Trust it for what it is: the server's rules over a state that may be a few events behind. It cannot be wrong about the *rules*, only about the *world*, and `execute` corrects the latter with an `AppendConflict`. Never skip the server call because the preview said yes.

**Who can see what? Does Strata do authorization?**
No. The log is one log; `Selection` selects, it does not authorize. Visibility rules — *members of this account may read its observations* — belong in your API layer, typically backed by a projection that answers membership questions. Sealing is the one privacy primitive Strata does provide, because it has to be applied at the storage layer to mean anything.

**Can I use my own store?**
Yes. Implement the `@store.EventStore` trait (and `ViewStore` for inline read models), run `@testing.contract(make=...)` against it, and pass it to `Runtime(store)`.

**Does Strata replace a message broker?**
No. The event store is your system of record and your outbox; a broker is how other systems hear about it. Reactors bridge the two.

**How fast is it?**
The command path is one indexed read and one insert per command; the in-memory store is bound by the fold, and the PostgreSQL store by the database. Benchmarks and methodology live in [`benchmarks/`](benchmarks/) and will be published with the first implemented release.

## Acknowledgements

Strata would not exist without the people who worked out the ideas: the Decider pattern as articulated by Jérémie Chassaing; the functional event sourcing practice of the Equinox and Emmett communities; Marten's projection lifecycles; the Dynamic Consistency Boundaries specification by Sara Pellegrini, Bastian Waidelich, and Paul Grimshaw; the accountants, who knew about reversals and closing the books long before we did; and the MoonBit team, for a language in which all of this could finally be checked by a compiler.

## License

Apache License 2.0. See [LICENSE](LICENSE).

Apache-2.0. See [LICENSE](LICENSE).