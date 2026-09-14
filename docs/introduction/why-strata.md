# Why Strata

Event sourcing is a good idea with a bad reputation, and most of the reputation is earned by tooling rather than by
the idea. Across ecosystems the same taxes show up.

**The boilerplate tax.** One class per event, a serializer per class, a registry entry per serializer, an upcaster
per version. Teams write hundreds of lines before the first business rule.

**The reflection tax.** Annotations and runtime scanning decide which method handles which event. Nothing is checked
until the process starts. Rename an event and find out in production which projection you forgot.

**The mutability tax.** Aggregates are objects that mutate themselves while events are applied. Reasoning about them
means reasoning about time; testing them means constructing them.

**The effect tax.** Clocks, random ids, and database calls leak into domain code because nothing stops them. Unit
tests grow a database. Replays become non-deterministic.

**The read-side tax.** Write models get all the design attention; read models are an afterthought bolted to one
stream at a time. The moment a view needs two categories, or a fan-out to several keys, or a fold over events
selected by tag, you are writing infrastructure.

**The judgement tax.** Every library assumes the aggregate is a gatekeeper. Domains where the right answer is *record
it, flag it, let a person decide* end up either smuggling warnings into the log as fake events or rebuilding the
aggregate's state in a second place just to compute them.

MoonBit removes the first four at the language level, and Strata is designed so that the last two never appear:

| Tax | What MoonBit gives you | What Strata does with it |
|---|---|---|
| Boilerplate | `derive(ToJson, FromJson)` on enums and structs | Derived JSON *is* the storage format (`["Deposited", {"amount": 100, ...}]`). No codecs, no registries. |
| Reflection | Closed enums with exhaustive `match` | Adding an event variant is a compile error in every `evolve` and `apply` that forgot it. |
| Mutability | Immutable-by-default data and `{ ..s, field }` updates | State is a value. Replay is a fold. Snapshots are `Eq`. |
| Effects | Checked errors (`raise`) and `async` tracked in function types | `decide` is `(C, S, Env) -> Array[E] raise`. It *cannot* call a clock or a database; the type won't let it. Identity, time, and actor arrive as values in `Env`. |
| Read side | Values, closures, and generics that compose | One `Selection` type drives folds, paged reads, projections, reactors, and consistency conditions. Views fan out to many keys and fold many sources without wrapper types. |
| Judgement | Pure functions are cheap to run twice | `advise` runs beside `decide` over the same state, returns notices that are never stored, and compiles to the browser so the client can see the warning before the server does. |
| | Traits with `async` methods | The event store is one trait; pass any implementation to `Runtime(store)`. Same contract tests on memory and PostgreSQL. |
| | Structured concurrency with cancellation | Projectors and reactors are tasks in a `TaskGroup`. Shutdown is automatic. |
| | `moon prove` (planned) | Invariants over `decide`/`evolve` can be proven, not just tested. |

Strata is what event sourcing looks like when the language was designed after the pattern.

## Who it is for

Strata is for MoonBit web backends where history is the product: money, inventory, allocation, audit, anything you
will be asked to explain later. It is comfortable living next to a CRUD service in the same process; you do not have
to event-source everything, and you should not.

It is *not* a database, a message broker, or a framework that owns your process. The event store is a trait with an
in-memory implementation today and PostgreSQL on the [roadmap](/ROADMAP); reactors bridge the store to whatever
broker you already use; and the runtime is a value you construct in your own `main`.

## Three ideas

Three ideas run through the whole library, and the rest of this site is organised around them.

- **Writes are decisions.** A [`Decider`](/concepts/deciders) turns a command and a state into events or a typed
  rejection, and it is a pure function by construction.
- **Most decisions are to record.** Alongside the decision, a decider can offer [advice](/tutorial/05-advice):
  warnings and forecasts computed from the same state, returned to the caller, never persisted, so a system can inform
  without blocking.
- **Reads are selections.** Every read model, every reactor, and every consistency boundary is expressed with the same
  [`Selection`](/concepts/selections) type, so the read side is exactly as expressive as the write side.

Continue with [Event sourcing in one page](/introduction/event-sourcing-primer) if the pattern is new to you, or go
straight to the [Quickstart](/guide/quickstart).
