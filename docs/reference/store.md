# store (`@store`)

`tanden-inc/strata/store` defines the storage contract as four `pub(open)` traits with `async` methods, and ships the
in-memory implementations. Targets: native, js, wasm. Any type that implements `EventStore` can be passed to
`@rt.Runtime`; run `@testing.contract` against it ([Testing](/concepts/testing#contracts)). The decision to use a
trait rather than a virtual package is [ADR 0001](/adr/0001-store-as-trait).

## EventStore

```moonbit
pub(open) trait EventStore {
  async fn append(Self, stream~ : StreamId, condition~ : AppendCondition, events~ : Array[NewEvent],
                  recorded_at~ : Instant, inline? : Array[ViewWrite]) -> AppendResult
  async fn read(Self, Selection, after? : Position, limit? : Int) -> Array[StoredEvent]
  async fn read_stream(Self, StreamId, from_version? : Int) -> Array[StoredEvent]
  async fn head(Self) -> Position
  async fn find_idempotent(Self, key~ : String, stream? : StreamId) -> Array[StoredEvent]
  async fn subscribe(Self, Selection, from~ : Position) -> &Subscription
  async fn load_checkpoint(Self, String) -> Position?
  async fn save_checkpoint(Self, String, Position) -> Unit
  async fn load_snapshot(Self, SnapshotKey) -> SnapshotRecord?
  async fn save_snapshot(Self, SnapshotKey, SnapshotRecord) -> Unit
  fn views(Self) -> &ViewStore
}
```

| Method | Contract |
|---|---|
| `append` | validates the condition, the events and the inline writes before mutating anything; a failed append leaves the log, the head and the views untouched. Writes `$stream:`, `$category:` and `$tenant:` system tags. Raises `AppendConflict` (`StreamConflict` or `BoundaryConflict`), `InvalidTag`. |
| `read` | events matching the selection in global position order, strictly after `after`, at most `limit` |
| `read_stream` | one stream from a version |
| `head` | the last position in the log |
| `find_idempotent` | the original batch stored under an idempotency key, optionally narrowed to a stream |
| `subscribe` | a live cursor from a position |
| checkpoints, snapshots | named positions for projectors and reactors; state caches keyed by `SnapshotKey` |

```moonbit
pub struct AppendResult { events : Array[StoredEvent]; version : Int; position : Position }
pub(all) enum SnapshotKey { Stream(StreamId, version~ : Int); Dcb(Selection, version~ : Int) }
pub struct SnapshotRecord { position : Position; version : Int; state : Json }
```

## ViewStore

Rows for read models, keyed by table and row key. `commit` is the atomic write projectors use
([ADR 0005](/adr/0005-atomic-read-side-commit)).

```moonbit
pub(open) trait ViewStore {
  async fn commit(Self, writes~ : Array[ViewWrite], checkpoint? : Checkpoint) -> Unit   // atomic by contract
  async fn checkpoint(Self, String) -> Position?
  async fn get(Self, table~ : String, key~ : String) -> Json?
  async fn put(Self, table~ : String, key~ : String, Json) -> Unit
  async fn delete(Self, table~ : String, key~ : String) -> Unit
  async fn keys(Self, table~ : String) -> Array[String]
  async fn swap(Self, from~ : String, to~ : String) -> Unit   // blue/green rebuild
}
pub struct ViewWrite { table : String; key : String; value : Json? }   // None deletes
pub struct Checkpoint { name : String; position : Position }
```

## Subscription

```moonbit
pub(open) trait Subscription {
  async fn next(Self, timeout? : Duration) -> Array[StoredEvent]   // empty batch on timeout
  fn position(Self) -> Position
  fn close(Self) -> Unit                                            // wakes blocked readers
}
```

## KeyStore

Per-subject keys for [sealing and shredding](/concepts/sealing-and-shredding).

```moonbit
pub(open) trait KeyStore {
  async fn key_for(Self, String) -> Bytes                          // raises KeyDestroyed, KeySealed
  async fn destroy(Self, String) -> Unit
  async fn seal(Self, String) -> Unit
  async fn unseal(Self, String, capability~ : String) -> Bytes     // raises KeyMissing, KeyDestroyed; never lifts the seal
}
```

## In-memory implementations

| Type | Notes |
|---|---|
| `MemoryStore::MemoryStore()` | the default `EventStore`; owns a `MemoryViewStore` and the checkpoint table so `commit` is atomic; `length()` counts events |
| `MemoryViewStore::MemoryViewStore()` | standalone `ViewStore` |
| `MemoryKeyStore::MemoryKeyStore()` | `KeyStore`; `unseals()` returns the audit list of `(subject, capability)` |
| `MemorySubscription` | returned by `MemoryStore::subscribe` |

## PostgreSQL

::: warning Skeleton
`tanden-inc/strata/store/pg` (native only) declares `PgStore::connect(url)`, `PgStore::migrate()`, `PgStore::close()`
and `impl EventStore`, plus `PgViewStore`. Every method raises `NotImplemented`; the contract runs against it when
`STRATA_TEST_PG` is set. It is the first item under *Promises without code* in the [roadmap](/ROADMAP).
:::

## Errors

`KeySealed(subject~)`, `KeyMissing(subject~)`, `KeyDestroyed(subject~)`: see [Errors](/reference/errors).
