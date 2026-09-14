# runtime (`@rt`)

`tanden-inc/strata/runtime` is the async shell: everything that reads or writes a store. Targets: native, js, wasm.
Functions that touch the store are `async` and may `raise`.

## Runtime

```moonbit
pub fn[St : EventStore] Runtime::Runtime(St, codec? : JsonCodec, clock? : Clock, ids? : IdGenerator,
                                          keys? : &KeyStore) -> Runtime
```

Defaults: a fresh `JsonCodec()`, `Clock::system()`, `IdGenerator::ulid()`, `MemoryKeyStore()`. Accessors `store()`,
`views()`, `codec()`, `clock()`, `keys()` return the parts.

## Command handlers

See [tutorial part 3](/tutorial/03-running-commands) and [Idempotency and concurrency](/concepts/idempotency-and-concurrency).

```moonbit
pub fn Runtime::handler(Self, Decider[C, E, S, N], retry? : Retry, snapshot? : SnapshotPolicy,
                        inline? : Array[InlineProjection[E]]) -> CommandHandler[C, E, S, N]
pub async fn CommandHandler::execute(Self, id : String, C, ctx~ : Context, expected? : ExpectedVersion,
                                     idempotency_key? : String) -> Outcome[E, N]
pub async fn CommandHandler::load(Self, id : String, tenant? : String) -> (S, Int)
pub fn CommandHandler::stream_id(Self, id : String, tenant? : String) -> StreamId

pub fn Runtime::dcb_handler(Self, DcbDecider[C, E, S, N], retry? : Retry, snapshot? : SnapshotPolicy) -> DcbHandler[C, E, S, N]
pub async fn DcbHandler::execute(Self, C, ctx~ : Context, idempotency_key? : String) -> Outcome[E, N]
pub async fn DcbHandler::load(Self, C) -> (S, Position)
```

`execute` raises the decider's own `suberror`s unchanged, `AppendConflict`, `IdempotencyConflict::KeyReused`,
`StreamTerminal::Terminal` (stream deciders only) and `DecodeError`. `E` and `S` need `ToJson + FromJson`.

```moonbit
pub fn inline(Projection[E, V], into~ : String) -> InlineProjection[E]   // V : ToJson + FromJson
pub fn InlineProjection::table(Self) -> String
```

## Policies

```moonbit
pub fn Retry::none() -> Retry                                           // default
pub fn Retry::on_conflict(max~ : Int, backoff? : Duration) -> Retry     // AppendConflict only
pub fn Retry::max(Self) -> Int
pub fn Retry::backoff(Self) -> Duration

pub fn SnapshotPolicy::never() -> SnapshotPolicy                        // default
pub fn SnapshotPolicy::every(Int, version~ : Int) -> SnapshotPolicy
pub fn SnapshotPolicy::interval(Self) -> Int
pub fn SnapshotPolicy::version(Self) -> Int
```

## Reads and folds

See [Selections](/concepts/selections) and [Read models](/concepts/read-models).

```moonbit
pub async fn Runtime::read(Self, Selection, after? : Position, limit? : Int) -> Page
pub struct Page { events : Array[StoredEvent]; next : Position? }
pub fn[E : FromJson] Page::decode(Self) -> Array[Recorded[E]] raise DecodeError

pub async fn Runtime::fold(Self, Projection[E, V], Selection) -> V
pub async fn Runtime::fold_keyed(Self, KeyedProjection[E, K, R], Selection) -> Map[K, R]
pub async fn Runtime::fold_multi(Self, MultiProjection[V]) -> V
pub async fn Runtime::live(Self, Projection[E, V], category~ : String, id~ : String, tenant? : String) -> (V, Int)
pub async fn Runtime::subscribe(Self, Selection, from~ : Position) -> &Subscription
pub async fn Runtime::state_at(Self, Decider[C, E, S, N], Recorded[X]) -> S   // replay pinned to (stream, version)
```

## Projectors

```moonbit
pub fn Runtime::projector(Self, name : String, MultiProjection[V], into~ : String) -> Projector
pub fn Runtime::projector_keyed(Self, name : String, KeyedProjection[E, K, R], source~ : Selection, into~ : String) -> Projector
```

| `Projector` method | Purpose |
|---|---|
| `start(group : TaskGroup)` | run as a task until the group ends |
| `run()` | run in the current task until cancelled |
| `catch_up()` | process to the current head and return |
| `wait_for(Position, timeout~ : Duration)` | block until the projector has passed a position; raises `WaitTimeout` |
| `rebuild()` | replay into a fresh table, then `swap` |
| `on_forgotten((String) -> Unit)` | called with the subject when `forget` runs |
| `name()`, `position()` | identity and checkpoint |

Rows and checkpoint are written together through `ViewStore::commit`. A `MultiProjection` writes one row per table
(key `"view"`); a keyed projector writes one row per key.

## Reactors

See [tutorial part 7](/tutorial/07-reactors) and [ADR 0006](/adr/0006-id-batches-and-reactor-failure).

```moonbit
pub fn Runtime::reactor(Self, name : String, source~ : Selection, retry? : @async.RetryMethod, max_retry? : Int,
                        on_failure? : async (StoredEvent, Error) -> Unit,
                        handler : async (Recorded[E]) -> Unit) -> Reactor
```

Defaults: `retry = FixedDelay(100)`, `max_retry = 5`. `Reactor` has `start(group)`, `run()`, `catch_up()`, `name()`
and `position()`.

## Privacy

```moonbit
pub async fn Runtime::forget(Self, category~ : String, id~ : String, tenant? : String) -> Unit
pub async fn Runtime::unseal(Self, StoredEvent, capability~ : String) -> Metadata
```

`forget` destroys the subject's key, appends a `$strata.forgotten` marker to the stream and notifies projectors;
`unseal` returns the metadata and appends a `$strata.unsealed` marker. See
[Sealing and shredding](/concepts/sealing-and-shredding).

## Clock and IdGenerator

```moonbit
pub fn Clock::system() -> Clock
pub fn Clock::fixed(Instant) -> Clock
pub fn Clock::manual(Instant) -> Clock          // advance(Duration) moves it
pub fn Clock::parse_fixed(String) -> Clock raise InvalidInstant
pub fn Clock::now(Self) -> Instant
pub fn Clock::advance(Self, Duration) -> Unit   // no-op on system and fixed clocks

pub fn IdGenerator::ulid() -> IdGenerator                     // monotonic, also when now goes backwards
pub fn IdGenerator::sequential(prefix? : String) -> IdGenerator   // "evt-0001", ...; tests
pub fn IdGenerator::reserve(Self, now~ : Instant) -> IdBatch
```

## Errors

`StreamTerminal::Terminal(stream~)`, `WaitTimeout(waiting_for~, reached~)`: see [Errors](/reference/errors).
