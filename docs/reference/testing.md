# testing (`@testing`)

`tanden-inc/strata/testing` is imported `for "test"`. It holds the pure spec machinery, the laws, the store contract
and helpers for runtime tests. See [Testing](/concepts/testing).

## Specs

```moonbit
pub fn spec(Decider[C, E, S, N]) -> Spec[C, E, S, N]
```

| `Spec` method | Purpose |
|---|---|
| `given(Array[E])` | the history; folds with `evolve` |
| `acting_as(actor~, tenant?)` | fix who is acting |
| `at(Instant)` | fix `env.now` |
| `with_env(Env)`, `with_ids(IdBatch)` | replace the environment or the id batch |
| `state() -> S` | the folded state |
| `when(C) -> Result[Array[E], Error]` | run `decide` |
| `when_all(Array[C]) -> Result[Array[E], Error]` | run in sequence, threading state; stops at the first rejection |
| `advice(C) -> Array[N]` | run `advise`; `[]` when `decide` rejects |
| `decision(C) -> Result[Decision[E, N], Error]` | both at once |

Every builder returns a new `Spec`, so a base spec can be shared across assertions. Ids are `evt-0001`, `evt-0002`,
... unless replaced.

```moonbit
pub fn dcb_spec(DcbDecider[C, E, S, N]) -> DcbSpec[C, E, S, N]
```

`DcbSpec` has `given`, `acting_as`, `state`, `when`, `advice`, plus `scope_of(C)` to fix the scope and
`assert_scope_closed()`, which fails if removing every out-of-scope event from the history changes the state.

## Laws

All laws take `loc~` automatically and raise on failure.

```moonbit
pub fn replay_law(Decider[C, E, S, N], Array[E]) -> Unit raise                       // S : Eq + Debug
pub fn advice_law(Decider[C, E, S, N], histories~ : Array[Array[E]], commands~ : Array[C]) -> Unit raise
pub fn reversal_law(Decider[C, E, S, N], reverses~ : (E) -> EventId?, identity~ : (E) -> EventId?,
                    histories~ : Array[Array[E]], restores? : (S, S) -> Bool) -> Unit raise
pub fn dcb_reversal_law(DcbDecider[C, E, S, N], reverses~, identity~, histories~, restores?) -> Unit raise
```

## Store contract

```moonbit
pub async fn[St : EventStore] contract(make~ : async () -> St) -> Unit
pub fn contract_cases() -> Array[String]
```

`contract` builds a fresh store per case with `make` and runs the twenty-one cases named by `contract_cases()`, in
that order: append positions and versions, the three `ExpectedVersion`s, DCB conditions with and without `after`,
global-order reads and paging, stream reads, system tags, the `$` tag rule, `find_idempotent`, subscriptions and
their timeouts, checkpoints, snapshots keyed by selection, atomic inline writes, `commit`, tenant-aware category
selections, type selections.

## Runtime helpers

```moonbit
pub fn runtime(clock? : Clock, ids? : IdGenerator, codec? : JsonCodec) -> Runtime   // MemoryStore, fixed clock, sequential ids
pub fn env(actor?, now?, tenant?, ids?) -> Env
pub fn recorded(E, stream~, version~, position~, id?, event_type?, actor?, at?, tags?) -> Recorded[E]
pub fn stored(event_type~, data~, stream~, version~, position~, schema?, id?, tags?, at?) -> StoredEvent
```

## Fixtures

```moonbit
pub fn Fixtures::from_json(Array[(String, Int, Json)]) -> Fixtures    // (event_type, schema, data)
pub fn Fixtures::from_stored(Array[StoredEvent]) -> Fixtures
pub fn[E : FromJson] Fixtures::all_decode(Self, JsonCodec) -> FixtureReport[E] raise
pub struct FixtureReport[E] { decoded : Array[Recorded[E]]; skipped : Int }
```

## Generators

For `moonbitlang/quickcheck`: `arbitrary_selection`, `arbitrary_env`, `arbitrary_tag`, each
`(Int, RandomState) -> T`. `Actor`, `EventId` and `Instant` derive `Arbitrary` in `core`.
