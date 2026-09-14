# API conventions

The rules Strata's public surface follows. Knowing them makes the reference predictable, and they are the reason the
stable packages can grow without breaking callers.

## Construction

- Public structs are readonly (`pub struct`) and constructed through a labelled constructor `Type::Type(...)`,
  callable as `Type(...)`: `Env(actor~, now~)`, `Context(actor~)`, `Decider(category~, initial~, decide~, evolve~)`.
  Optional capabilities are optional arguments (`advise?`, `tags?`, `is_terminal?`), so a new one can be added in a
  minor release.
- Identifier newtypes are `pub(all) struct X(...)` and open for literal construction: `EventId("evt-1")`,
  `Actor("user:alice")`, `Tag("code:X")`, `StreamId("account-acc-1")`, `Position(41)`, `Instant(ms)`, `Duration(ms)`.
- Enums and suberrors that users construct are `pub(all)` (`ExpectedVersion`, `AppendCondition`, `TagStyle`,
  `SnapshotKey`, every Strata error); `pub` alone is read-only across packages.
- Nothing with a construction-time invariant is exposed as a struct literal.

## Derivations

- Values derive `Eq, Debug`; keys add `Hash, Compare`; persisted values add `ToJson, FromJson`.
- Newtypes implement `ToJson`/`FromJson` by hand as plain scalars, so the stored format is readable and stable.
- Your event, state and view types need `Eq, Debug, ToJson, FromJson`; commands need `Eq, Debug`; notices `Eq, Debug`
  (and `ToJson` if you return them over the wire).

## Effects

- Pure functions are never `async`. Effectful functions are `async` and `raise`. If it is in `core` or `codec`, it
  cannot touch a store.
- Domain rejections are your own `suberror`s and propagate as `Error`, unchanged. Strata's own errors are
  `pub(all) suberror`s listed in [Errors](/reference/errors).
- Trait methods declare optional parameters without defaults; `Runtime` applies the defaults.
- Functions that accept an implementation are generic over the trait (`fn[St : EventStore] Runtime(...)`) and coerce
  internally, so callers never write `as &Trait`.

## Selections and tags

- Tags starting with `$` are system tags written by the store (`$stream:`, `$category:`, `$tenant:`); user code
  cannot create them.
- `Selection` constructors normalise their input, so `Eq` and `Hash` on selections have set semantics.

## Storage

- The stored payload is the whole value produced by `derive(ToJson)`; the event type name is derived from it by the
  codec's `TagStyle` (default `Flat`: `["Deposited", {...}]`).

## Documentation and interface files

- Every `pub` item has a `///` doc comment (`missing_doc` is a compile error); blocks are separated by `///|`.
- Every visible API change shows up in the committed `pkg.generated.mbti` files (`moon info`); CI fails on drift.
