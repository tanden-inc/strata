# Strata: guide for contributors and coding agents

Strata is an event sourcing toolkit for [MoonBit](https://docs.moonbitlang.com). This file is the working agreement for
anyone (human or agent) changing the code. The product design lives in [README.md](README.md); decisions that changed
the design are recorded in [docs/adr](docs/adr).

## Package map

| Package | Import alias | Purity | Targets | Contents |
|---|---|---|---|---|
| `tanden-inc/strata/core` | `@strata` | pure | all | `Decider`, `DcbDecider`, `Env`, `Selection`, `Scope`, ids, time, `Recorded`, `Context`, `Outcome`, projections, `Preview` |
| `tanden-inc/strata/codec` | `@codec` | pure | all | `JsonCodec`, `TagStyle`, `Upcast`, shred/seal declarations |
| `tanden-inc/strata/store` | `@store` | async | native, js, wasm | `EventStore` trait, `Subscription`, `ViewStore`, `KeyStore`, `MemoryStore` |
| `tanden-inc/strata/runtime` | `@rt` | async | native, js, wasm | `Runtime`, command handlers, reads/folds, projectors, reactors, `Clock`, `IdGenerator` |
| `tanden-inc/strata/testing` | `@testing` | mixed | native, js, wasm | `spec`, `dcb_spec`, laws, store `contract`, test runtime helpers |
| `examples/account`, `examples/ledger` | | | | reference domains; the first TDD targets |

Dependency direction is strictly `core <- codec <- store <- runtime <- testing`. `core` and `codec` must keep
compiling for `wasm-gc` (browser `Preview`); they never import `moonbitlang/async`.

## Status: round 2 (road to 1.0)

The 0.1 interface is implemented and green. The next round is driven by `docs/ROADMAP.md`: each item names its red
test (files called `v1_test.mbt`, new cases in `testing/contract.mbt`) and the interface pieces added for it
(`ViewStore::commit`, `Checkpoint`, `KeySealed`/`KeyDestroyed`, `Selection::none`, `IdBatch::high_water`,
`is_system_event_type`, reactor `max_retry`/`on_failure`, the `store/pg` skeleton). Stubs raise `NotImplemented`, or (for pure functions
whose callers must keep running) return a placeholder marked `// TODO(strata): …`; `make todo` lists both. Work through the roadmap top to bottom; do not weaken a test to
make it pass — if a test is wrong, say so in the PR and fix the test first.

## Status: round 1 (historical)

The public interface is designed and frozen for 0.1; bodies are stubs. `make todo` lists every stub. Tests are
written against the interface and are red until implemented.

Two stub styles, on purpose:

- **Pure functions** use `...`: they panic when called. On native a panic aborts the whole test executable of that
  package; on js it fails only the synchronous test that hit it.
- **Effectful functions** (`async`, or `-> T raise`) call `todo("Type::method")` from `core`, which raises
  `NotImplemented`. A red test then fails cleanly on every target.

Implement in this order so that each suite becomes runnable as soon as possible:

1. `core/ids.mbt`, `core/time.mbt`, `core/selection.mbt`, `core/env.mbt`, `core/event.mbt` (identifier plumbing;
   `store`, `runtime` and the examples call these during test setup).
2. `core/decider.mbt`, `core/dcb.mbt`, `core/projection.mbt`, `core/preview.mbt`, then `testing/spec.mbt` and
   `testing/laws.mbt` (the `examples/*` spec tests go green here).
3. `codec/codec.mbt` (`type_of`, `upgrade`, upcasts).
4. `store/memory.mbt` against `testing/contract.mbt` (write the contract cases first).
5. `runtime/*` (handlers, reads, projectors, reactors), then `testing/harness.mbt` helpers and `testing/arbitrary.mbt`.

`moon.mod` mutes `todo`, `unused_value`, `unused_field`, `unused_mut`, `unused_trait_bound`, `unused_async` and
`struct_never_constructed` while stubs exist; restore `warnings = "+missing_doc"` when `make todo` is empty.

## API conventions

- Public structs are readonly (`pub struct`) and constructed through a labelled constructor `Type::Type(...)`,
  callable as `Type(...)`. Fields can therefore be added in minor releases. Identifier newtypes
  (`EventId`, `StreamId`, `Position`, `Instant`, `Duration`, `Actor`, `Tag`) are `pub(all) struct X(...)`.
- Enums and suberrors that users construct are `pub(all)`; `pub` alone is read-only across packages.
- Derive `Eq, Debug` on values, add `Hash, Compare` for keys and `ToJson, FromJson` for persisted values.
  Newtypes implement `ToJson`/`FromJson` by hand (string or number) so the stored format is stable.
- Effects live in types: pure functions never `async`; effectful functions are `async` and `raise`.
  Domain rejections are user `suberror`s and propagate as `Error`. Strata's own errors are `pub(all) suberror`.
- Trait methods declare optional parameters without defaults; `Runtime` applies the defaults.
- Functions that accept an implementation are generic over the trait (`fn[St : EventStore] ...`) and coerce with
  `as &EventStore` internally, so callers never write `as &Trait`.
- Every `pub` item has a `///` doc comment (`missing_doc` is on). Blocks are separated by `///|`.
- Tags starting with `$` are system tags written by the store (`$stream:`, `$category:`, `$tenant:`); user code
  cannot create them. `Selection` constructors normalise, so `Eq`/`Hash` on selections have set semantics.
- The stored payload is the whole value produced by `derive(ToJson)`; the event type name is derived from it by the
  codec's `TagStyle` (default `Flat`: `["Deposited", {...}]`).

## TDD loop

1. Pick a stub (`make todo`) or a red test.
2. Run that package or file: `moon test --target js core` or `moon test --target native core/selection_test.mbt`.
   Use js first: a panic there fails one test; on native a panicking stub aborts the whole test executable.
3. Implement, keeping the signature. If the signature must change, change the test first and explain why in the PR.
4. `moon info && moon fmt`; read the `pkg.generated.mbti` diff. No diff means no visible API change.
5. Snapshots: `inspect` for `Show` values, `debug_inspect` for `derive(Debug)` values, `json_inspect` for JSON.
   `moon test -u` rewrites expected values; review them as a diff.
6. `make ci` before pushing.

## Tooling

- `moon check --deny-warn`, `moon fmt`, `moon info`, `moon test [-u] [--target js|native|wasm-gc] [path] [-f glob]`,
  `moon coverage analyze > uncovered.log`, `moon bench`, `moon ide doc '@pkg.Symbol'` (better than grep for APIs),
  `moon explain --diagnostic <id>` for any warning.
- `Makefile` wraps the CI sequence; `.githooks/pre-commit` runs fmt/check/info.
- The MoonBit agent skills at <https://github.com/moonbitlang/skills> are recommended for coding agents.
