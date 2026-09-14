# Status and stability

## What is implemented

The 0.1 interface is implemented and green: `core`, `codec`, `store` (in-memory), `runtime` and `testing`, plus the
`account` and `ledger` reference domains. The committed `pkg.generated.mbti` files are the authoritative list of the
public surface; the [reference](/reference/core) section is written from them.

The one package whose bodies still raise `NotImplemented` is `store/pg`, the PostgreSQL adapter. `make todo` in the
repository lists exactly those stubs.

## What is planned

| Item | Where it stands |
|---|---|
| PostgreSQL store (`store/pg`) | Required for 1.0. Skeleton exists; the store contract runs against it when `STRATA_TEST_PG` is set. Driver choice pending. |
| Sealing and shredding encryption | Declarations exist in `codec` and the `KeyStore` trait; field encryption is a 1.1 item. `forget` and `unseal` already append their markers. |
| HTTP and GraphQL adapters, `gen graphql` | 1.x; see [HTTP and GraphQL](/design/http-and-graphql). |
| `moon prove` obligations | 1.x, experimental. |
| `examples/assignment`, the multi-source `landing` view | Referenced in prose; not yet in the repository. |

The ordered list of work, each item with its red test, is the [roadmap](/ROADMAP).

## Stores and targets

| | native | js | wasm-gc |
|---|---|---|---|
| Domain code, read models, `Preview` | ✓ | ✓ | ✓ |
| `MemoryStore`, runtime, `@testing` | ✓ | ✓ | wasm (not wasm-gc; `moonbitlang/async` does not target it) |
| PostgreSQL store | planned | planned (host driver) | — |
| Async projectors and reactors | ✓ | ✓ | — |
| HTTP / GraphQL integration | planned | planned | — |

The planned PostgreSQL schema is a single `events` table (`position bigserial`, `stream_id`, `version`, `type`,
`schema`, `data jsonb`, `meta jsonb`, `tags text[]`, `recorded_at`) with a unique `(stream_id, version)` index and a
GIN index on `tags`, plus `checkpoints`, `snapshots`, `views` and `keys`. Every `Selection` compiles to one indexed
`SELECT`.

## Versioning

Strata follows semantic versioning. Until 1.0, minor releases may still adjust the surface, and every change shows up
in the committed `pkg.generated.mbti` files.

**Stable at 1.0**, breaking changes only in 2.0: `strata/core` (including `Selection` semantics, `Env`, `IdBatch`,
`Scope`, and the `Decider` / `DcbDecider` / `Projection` constructors), `strata/codec`, `strata/runtime`, the
`EventStore` contract and its contract test suite, the in-memory and PostgreSQL stores, `strata/testing`, the on-disk
PostgreSQL schema (forward-migrated), and the stored JSON format.

**A rule about the stable surface.** Every public struct in the stable packages is readonly and constructed through a
function with labelled arguments (`Env(actor~, now~)`, `Context(actor~)`, `Decider(...)`); only identifier newtypes
(`EventId`, `Actor`, `Tag`, ...) are open for literal construction. This is what lets Strata add a capability, a new
optional argument or a new `Env` field, in a minor release without breaking any caller. See
[API conventions](/reference/conventions).

**Experimental**, may change in minor releases, always behind an explicit import: the JS host store, `moon prove`
helpers, the `gen graphql` tool's output format, and the KurrentDB adapter when it lands.

## Toolchain

Strata is developed against the latest stable MoonBit toolchain (0.10 line) and `moonbitlang/async` 0.21. CI runs
`moon check --deny-warn`, `moon fmt --check`, `moon info` drift detection, and the test suites on native, js and (for
the pure packages) wasm-gc.
