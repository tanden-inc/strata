# core (`@strata`)

`tanden-inc/strata/core` is pure: no IO, no `async`, compiles for every target including `wasm-gc`. Import it as
`@strata`. Signatures below are taken from `core/pkg.generated.mbti`; every item links to the page that explains it.

## Decider

The write model. See [Deciders](/concepts/deciders) and [tutorial part 1](/tutorial/01-your-first-decider).

```moonbit
pub struct Decider[C, E, S, N]
pub fn Decider::Decider(category~ : String, initial~ : S,
  decide~ : (C, S, Env) -> Array[E] raise, evolve~ : (S, E) -> S,
  advise? : (C, S, Env) -> Array[N], tags? : (E) -> Array[Tag], is_terminal? : (S) -> Bool) -> Self
```

| Method | Purpose |
|---|---|
| `category()`, `initial()` | the constructor arguments |
| `decide(cmd, state, env) -> Array[E] raise` | run the decision alone |
| `advise(cmd, state, env) -> Array[N]` | run the advice alone; `[]` when none was declared |
| `evolve(state, event) -> S` | fold one event |
| `tags_of(event) -> Array[Tag]` | the event's tags; `[]` when none was declared |
| `is_terminal(state) -> Bool` | `false` when none was declared |
| `run(cmd, state, env) -> Decision[E, N] raise` | `decide` then `advise`; what specs, `Preview` and the runtime call |
| `replay(events : Iter[E]) -> S` | fold a history from `initial` |
| `replay_from(state, events) -> S` | continue from a snapshot |

```moonbit
pub struct Decision[E, N] { events : Array[E]; notices : Array[N] }
```

## DcbDecider

A decider whose consistency unit is a `Selection`. See [Consistency boundaries](/concepts/consistency-boundaries) and
[tutorial part 6](/tutorial/06-dynamic-consistency-boundaries).

```moonbit
pub struct DcbDecider[C, E, S, N]
pub fn DcbDecider::DcbDecider(category~ : String, stream~ : (C) -> String, scope~ : (C) -> Selection,
  tags~ : (E) -> Array[Tag], initial~ : S,
  decide~ : (C, S, Env, Scope) -> Array[E] raise, evolve~ : (S, E, Scope) -> S,
  advise? : (C, S, Env, Scope) -> Array[N]) -> Self
```

| Method | Purpose |
|---|---|
| `stream_of(cmd) -> String`, `scope_of(cmd) -> Scope`, `tags_of(event)` | the three command/event → boundary mappings |
| `evolve(state, event, scope)`, `run(cmd, state, env, scope)` | scope-aware counterparts of `Decider`'s |
| `replay(scope, events)`, `replay_from(scope, state, events)` | folds over the partial world |

## Env, Context, Metadata

See [Environment, identity, and time](/concepts/environment-identity-and-time).

```moonbit
pub struct Env { actor : Actor; tenant : String?; now : Instant; ids : IdBatch; extra : Json }
pub fn Env::Env(actor~, now~, tenant?, ids?, extra?) -> Env

pub struct Context { actor : Actor; tenant : String?; correlation_id : String?; causation_id : EventId?;
                     idempotency_key : String?; flags : Array[String]; extra : Json }
pub fn Context::Context(actor~, tenant?, correlation_id?, causation_id?, idempotency_key?, flags?, extra?) -> Context
pub fn Context::flag(Self, String) -> Bool
pub fn Context::with_flag(Self, String) -> Context
pub fn Context::with_idempotency_key(Self, String) -> Context
pub fn Context::to_metadata(Self) -> Metadata

pub struct Metadata { correlation_id : String?; causation_id : EventId?; actor : Actor?; tenant : String?;
                      idempotency_key : String?; extra : Json }
```

## Selection and Scope

See [Selections](/concepts/selections).

| Constructor | Names |
|---|---|
| `Selection::all()` | the whole log |
| `Selection::none()` | nothing; `any_of([])` normalises to this |
| `Selection::stream(StreamId)` | one stream (`$stream:` tag) |
| `Selection::category(name, tenant?)` | every stream in a category, optionally one tenant's |
| `Selection::tags(Array[Tag])` | events carrying all of the tags |
| `Selection::types(Array[String], tags?)` | events of any of the types, optionally with tags |
| `Selection::any_of(Array[Selection])` | the union |

| Method | Purpose |
|---|---|
| `items() -> Array[SelectionItem]` | the normalised disjuncts (`{ types, tags }`) |
| `is_all()`, `single_stream() -> StreamId?` | shape queries |
| `matches(event_type~, tags~) -> Bool` | membership test |
| `ToJson` / `FromJson` | persisted as snapshot keys |

```moonbit
pub struct Scope
pub fn Scope::of(Selection) -> Scope
pub fn Scope::owns(Self, Tag) -> Bool
pub fn Scope::selection(Self) -> Selection
```

## Identifiers and time

All identifier newtypes are `pub(all) struct X(String)` (or `Int64`) with hand-written `ToJson`/`FromJson` as plain
scalars, `Show`, `Eq`, `Compare`, `Hash`.

| Type | Constructors and methods |
|---|---|
| `EventId(String)` | `ulid(timestamp~, random~ : Bytes)`, `increment()`, `timestamp() -> Instant?`, `is_ulid()` |
| `StreamId(String)` | `of(category~, id~, tenant?)`, `parse(String) raise InvalidStreamId`, `category()`, `entity_id()`, `tenant()` |
| `Position(Int64)` | `start : Position`, `next()` |
| `Actor(String)` | |
| `Tag(String)` | `kv(key~, value~)`, `key()`, `value() -> String?`, `is_system()` |
| `IdBatch` | `at(i) -> EventId`, `high_water() -> Int`, `from(EventId)`, `offset(Int)`, `deterministic(prefix?)` |
| `Instant(Int64)` | `parse(String) raise InvalidInstant`, `to_iso8601()`, `add(Duration)`, `since(Instant) -> Duration` |
| `Duration(Int64)` | `millis`, `seconds`, `minutes`, `hours`, `to_millis()` |

`is_system_event_type(String) -> Bool` recognises `$strata.*` marker events.

## Events and outcomes

```moonbit
pub struct NewEvent { id; event_type; schema : Int; data : Json; tags; meta : Metadata }   // what a store appends
pub fn NewEvent::NewEvent(id~, event_type~, schema~, data~, tags?, meta~) -> NewEvent raise InvalidTag

pub struct StoredEvent { id; position; stream; version; event_type; schema; data : Json; tags; meta; recorded_at }
pub fn StoredEvent::user_tags(Self) -> Array[Tag]   // without $-prefixed system tags

pub struct Recorded[E] { id; position; stream; version; event_type; event : E; tags; recorded_at; meta }
pub fn Recorded::from_stored(StoredEvent, E) -> Recorded[E]
pub fn Recorded::entity_id(Self) -> String
pub fn Recorded::caused(Self, actor?) -> Context   // correlation inherited, causation_id = id, idempotency_key = id

pub(all) enum ExpectedVersion { Any; NoStream; Exact(Int) }
pub(all) enum AppendCondition { Stream(StreamId, ExpectedVersion); Dcb(selection~ : Selection, after~ : Position?) }

pub struct Outcome[E, N] { events : Array[Recorded[E]]; notices : Array[N]; version : Int; position : Position; deduplicated : Bool }
```

## Projections

See [Read models](/concepts/read-models).

```moonbit
pub struct Projection[E, V]
pub fn Projection::Projection(initial~ : V, apply~ : (V, E) -> V) -> Self
pub fn Projection::fold(Self, Iter[E]) -> V

pub struct KeyedProjection[E, K, R]
pub fn KeyedProjection::KeyedProjection(keys~ : (Recorded[E]) -> Array[K], initial~ : R, apply~ : (K, R, Recorded[E]) -> R) -> Self
pub fn KeyedProjection::fold(Self, Iter[Recorded[E]]) -> Map[K, R]      // K : Eq + Hash

pub struct MultiProjection[V]
pub fn MultiProjection::MultiProjection(initial~ : V) -> Self
pub fn MultiProjection::source(Self, Selection, (V, Recorded[E]) -> V) -> Unit   // E : FromJson; chain with ..
pub fn MultiProjection::selection(Self) -> Selection                              // union of the sources
pub fn MultiProjection::apply_stored(Self, V, StoredEvent) -> V raise DecodeError
```

`initial()`, `apply(...)`, `keys_of(...)` and `sources()` expose the constructor arguments.

## Preview

See [Preview](/concepts/preview).

```moonbit
pub struct Preview[C, E, S, N]
pub fn Preview::Preview(Decider[C, E, S, N], state~ : S, env~ : Env) -> Self
pub fn Preview::of(Self, C) -> PreviewResult[E, N]
pub fn Preview::state(Self) -> S

pub struct PreviewResult[E, N] { result : Result[Array[E], Error]; notices : Array[N] }
```

## Errors

`AppendConflict`, `IdempotencyConflict`, `DecodeError`, `InvalidStreamId`, `InvalidInstant`, `InvalidTag`,
`NotImplemented`: see [Errors](/reference/errors). `todo(name)` raises `NotImplemented` and marks a stub.
