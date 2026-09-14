# Road to Strata 1.0

Status as of 2026-09-14: the 0.1 interface is implemented and green (89 tests). This file lists what stands between
that and a 1.0 release, in the order to do it. Every item has a red test; `make todo` lists the stubs that go with
the new interface pieces. Work test-first: make the named test green, keep `moon check --deny-warn` clean, run
`moon info && moon fmt`, and review the `.mbti` diff.

## 1. Correctness (blocking)

| Item | Red test | Notes |
|---|---|---|
| Event ids never overlap across decisions | `runtime/v1_test.mbt` "event ids never overlap…", "id generators start the next batch…" | `IdBatch::high_water()` is the new primitive; `IdGenerator` must start after it. ULIDs must also stay monotonic when `now` goes backwards. |
| `forget`/`unseal` markers must not break reads | `runtime/v1_test.mbt` "forget keeps the stream…", "unseal returns…"; `codec/v1_test.mbt` "system events are skipped" | `core.is_system_event_type` + `JsonCodec::decode` returning `None` for `$…` types. |
| DCB boundary on the snapshot path | `runtime/v1_test.mbt` "the DCB boundary holds on the snapshot path" | Read `head()` before the scope/tail read, always. |
| Atomic read-side commit | `testing/contract.mbt` "a failed append leaves inline views untouched", "commit applies rows and checkpoint together" | New `ViewStore::commit(writes~, checkpoint?)`; `MemoryStore::append` must validate everything before mutating; projectors write rows and checkpoint through `commit`. See ADR 0005. |
| Tenant isolation | `runtime/v1_test.mbt` "inline projections and reads keep tenants apart"; `examples/account/v1_test.mbt` | Inline row key `tenant/entity`; `live(..., tenant?)`; `CommandHandler::load(id, tenant?)`. |
| Bounded reactor retry + dead letter | `runtime/v1_test.mbt` "reactors retry a bounded number…" | `Runtime::reactor(max_retry?, on_failure?)`. Default retry is `FixedDelay(100)`, 5 attempts. |
| `Selection::none()`; `any_of([])` is none | `core/v1_test.mbt`, contract "category selections are tenant-aware" | A `MultiProjection` with no sources must subscribe to nothing. |
| Key store semantics | `store/v1_test.mbt` "destroyed keys stay destroyed", "sealed keys are withheld…" | `KeyDestroyed`, `KeySealed`; `unseal` never lifts the seal or re-creates keys. |
| Instant validation | `core/v1_test.mbt` "instants reject second 60…" | Reject `:60`, hour 24, impossible dates. |
| Subscription close wakes readers | `store/v1_test.mbt` "closing a subscription releases…" | `close` broadcasts. |

## 1b. Round 3: defects found in the round-2 implementation

| Item | Red test | Notes |
|---|---|---|
| `IdGenerator::sequential` repeats ids from the third decision on | `runtime/v1b_test.mbt` "event ids stay unique across many decisions…", "sequential ids never repeat…" | `offset` starts a fresh, relative `high_water`; the generator must accumulate the absolute start itself. |
| ULID monotonicity after an empty batch | `runtime/v1b_test.mbt` "ulids stay monotonic across an empty batch…" | Track the last id handed out, not the last batch's base. |
| Reactor treats cancellation as failure | `runtime/v1b_test.mbt` "cancelling a reactor is not a handler failure" | Re-raise when `@async.is_cancellation_error(err)`; no retry, no dead-letter, no checkpoint advance. |
| Reactor ignores `ExponentialDelay` | `runtime/v1b_test.mbt` "reactor retry honours the configured delays" | Use `@async.retry(retry, max_retry~, fatal_error=is_cancellation_error, ..)` or compute the schedule. |
| `unseal` creates keys | `store/v1b_test.mbt` "unseal never creates a key" | New `KeyMissing`. |
| Checkpoints are invisible on a standalone `MemoryViewStore` | `store/v1b_test.mbt` "a standalone view store keeps the checkpoints it commits" | New `ViewStore::checkpoint(name)`; `MemoryStore::load_checkpoint` reads the same table. Reactors should checkpoint through `commit` too. |
| `dcb_reversal_law` widens to `all()` for tagless targets | `testing/v1b_test.mbt` "dcb_reversal_law rejects a target that has no boundary at all" | A target without tags has no boundary; the law must fail. |
| `loud` reactor test accepted a timeout as success | `runtime/v1_test.mbt` (tightened to `Failure(_)`) | — |

## 2. Promises without code

| Item | Decision |
|---|---|
| PostgreSQL store | Required for 1.0. Skeleton in `store/pg` (native only); the contract runs when `STRATA_TEST_PG` is set (`store/pg/pg_test.mbt`). Pick the driver first (`Lfan-ke/moon-postgres` or `moonbit-community/postgres`; check their `moonbitlang/async` pin) and record it in an ADR. Add a docker-compose service and a CI job with a `postgres` service container. |
| Sealing / shredding encryption | Deferred to 1.1. The declarations stay; README now says so. Do not claim encryption before it exists. |
| `http`, `graphql`, `gen graphql`, `moon prove` | Deferred to 1.x; documented as planned. |
| `examples/assignment`, the `landing` multi-source example | Nice to have before 1.0; both are referenced by the README. |

## 3. Laws and coverage

- `advice_law` is redefined (purity of advice) and stubbed: `testing/v1_test.mbt`.
- `dcb_reversal_law` must fail for absent targets and fold `restores` inside the target's boundary: `testing/v1_test.mbt`.
- Retry success path, snapshot save/load, `Projector::rebuild`, `fold_multi`, legacy decode: covered by the new tests above.
- Generators (`testing/arbitrary.mbt`) must produce stream/category selections and are now exercised: `testing/v1_test.mbt`.
- Afterwards: `moon coverage analyze > uncovered.log` and close the remaining branches that matter.

## 4. Release hygiene

- Doc tests: `examples/account/README.mbt.md` is the first; add one per package for the README snippets that matter.
- CI runs wasm-gc tests now (`make test-wasm-gc`); keep it.
- Publish contents: `moon package --list` must not include `examples/`, `benchmarks/`, `docs/` (`.moonignore`).
- Benchmarks: `benchmarks/README.md` has the table to fill; `replay 1000 + decide` covers the pure half, the
  end-to-end `execute` benchmark still needs an async harness.
- Before tagging 0.1.0 / 1.0.0: `CHANGELOG.md` release entry, README status badge and note, version in `moon.mod`,
  `moon publish --dry-run`.
