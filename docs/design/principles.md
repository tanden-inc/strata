# Design principles

Strata is small on purpose. Eight decisions explain almost all of it.

## 1. Deciders, not aggregates

A domain is a `Decider[C, E, S, N]`: an initial state, `decide : (C, S, Env) -> Array[E] raise`, and
`evolve : (S, E) -> S`. There is no base class, no `apply` method to override, no lifecycle. This is the functional
formulation that F# and TypeScript event sourcing communities converged on, and it fits MoonBit better than it fits
either of those: enums give you the closed event set, `raise` gives you typed rejection, and immutability makes
`evolve` a fold with no aliasing questions. The table of *what is rejected and what is recorded* that you drew on the
whiteboard is the `match` in `decide`.

Deciders are built with `Decider(...)` and labelled arguments; optional parts (`advise`, `tags`, `is_terminal`) are
simply omitted. `Decider[C, E, S, N]` always names its notice type; a decider without advice uses `Unit`. Strata never
exposes a public struct literal as an API surface, so the library can add capabilities without breaking a single call
site.

## 2. Two kinds of domain, one shape

Some domains are *guard-first*: a bank account rejects an overdraft, and `decide` is the gatekeeper. Others are
*record-first*: an expense system records the overspend, flags it, and leaves the judgement to a person, and `decide`
rarely raises at all. Most real systems are both, in different places.

Strata gives one shape to both. `decide` answers exactly one question, *what is recorded, or why not*, and stays
two-valued. A second pure function, `advise : (C, S, Env) -> Array[N]`, runs beside it over the same command and
state, and answers a different question: *what should the caller know*. Notices are returned in the `Outcome`, never
appended to the log, and never able to block. Keeping the two apart keeps `decide` provable and keeps the log honest:
a warning is a derivation, and derivations do not belong in the source of truth.

## 3. Effects live in the types; facts of the invocation arrive in `Env`

`decide` is neither `async` nor does it take a store. It is a compile error to call a clock, read a stream, or
generate an id inside it. What a decision may legitimately depend on beyond the command and the state, who is acting,
on whose behalf, what time it is, and *what the ids of the events it is about to emit will be*, arrives as a value,
`Env`, supplied by the runtime and fixed by tests. Everything effectful lives in `Runtime`, whose functions are
`async` and `raise`. Reading a Strata codebase, you always know where the IO is; a domain package that does not import
`strata/runtime` *cannot* perform any.

## 4. Adding is a compile error, not a runtime surprise

Events are closed sums. `evolve` and every read model's `apply` must match exhaustively. When you add `FeeCharged`,
the build fails at every site that needs to care, and passes only when you have decided what each of them does.
Cross-context evolution is handled where it belongs, in the serialized format, so closedness costs nothing at the
boundary.

## 5. Serialization is derived, and derived output is the storage format

Strata stores exactly what `derive(ToJson)` produces, `["Deposited", {"amount": 100, "by": "user:alice"}]` for a
variant with a payload, `"Closed"` for one without, alongside a schema version. The event type name is read back out
of that value (`TagStyle::Flat`; applications that prefer `derive(ToJson(style="legacy"))` get `{"$tag": "Deposited",
...}` and configure `TagStyle::Legacy(tag_key="$tag")`). Upcasting is a chain of `Json -> Json` functions applied at
read time. You never write a codec and you never register a type name. Recorded in [ADR 0002](/adr/0002-json-layout).

## 6. One `Selection` for reads, subscriptions, and boundaries

A `Selection` names a set of events: by stream, by category, by type, by tag, or by any combination. The same value
drives a paged read (`rt.read`), a fold into a view (`rt.fold`), a read model's sources, a reactor's subscription,
and, as an `AppendCondition`, a dynamic consistency boundary on writes. Because the write side and the read side share
one vocabulary, anything you can guard you can also view, and anything you can view you can also react to. (It is
called `Selection` and not `Query` so that it can live in the same file as a GraphQL schema without a fight.)

## 7. Pure core, async shell, one store trait

`strata/core` has no IO and compiles to every target, including the browser, where it powers command preview.
`strata/runtime` is the async shell. The `EventStore` contract is a trait with `async` methods: `MemoryStore` is the
default implementation, PostgreSQL (native) and a JS-host adapter are passed to `Runtime(store)` instead. The contract
test suite runs against every store, so an adapter that passes it behaves like every other adapter. Build-time
selection through a virtual package was considered and set aside; see [ADR 0001](/adr/0001-store-as-trait).

## 8. Tests are specifications; laws and proofs are on the menu

Given/When/Then over plain values, with expected events written by `moon test --update` and reviewed as diffs.
Property tests for laws such as *replay equals snapshot plus tail*, *out-of-scope events do not change a DCB state*,
and *a reversal stays inside its target's boundary*. And, planned, `moon prove` obligations over `decide` and
`evolve`, which are pure functions and therefore provable.
