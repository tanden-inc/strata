///|
/// The result of a successful append.
pub struct AppendResult {
  /// The appended events with their positions and versions.
  events : Array[@strata.StoredEvent]
  /// The stream version after the append.
  version : Int
  /// The global position of the last appended event.
  position : @strata.Position
} derive(Eq, Debug)

///|
/// Builds an append result.
pub fn AppendResult::AppendResult(
  events~ : Array[@strata.StoredEvent],
  version~ : Int,
  position~ : @strata.Position,
) -> AppendResult {
  { events, version, position, }
}

///|
/// A write to an inline read model, committed atomically with an append.
/// `value = None` deletes the row.
pub struct ViewWrite {
  table : String
  key : String
  value : Json?
} derive(Eq, Debug)

///|
/// Builds a view write.
pub fn ViewWrite::ViewWrite(
  table~ : String,
  key~ : String,
  value~ : Json?,
) -> ViewWrite {
  { table, key, value, }
}

///|
/// Identifies a snapshot: per stream, or per DCB selection. `version` is the
/// application's snapshot format version; bump it to invalidate.
pub(all) enum SnapshotKey {
  Stream(@strata.StreamId, version~ : Int)
  Dcb(@strata.Selection, version~ : Int)
} derive(Eq, Hash, Debug, ToJson, FromJson)

///|
/// A cached state: the global position and stream version it covers, and the
/// state as JSON.
pub struct SnapshotRecord {
  position : @strata.Position
  version : Int
  state : Json
} derive(Eq, Debug, ToJson, FromJson)

///|
/// Builds a snapshot record.
pub fn SnapshotRecord::SnapshotRecord(
  position~ : @strata.Position,
  version~ : Int,
  state~ : Json,
) -> SnapshotRecord {
  { position, version, state, }
}

///|
/// A live, pull-based feed of events matching a selection.
pub(open) trait Subscription {
  /// Waits for events after the current position and returns them in global
  /// order. Returns an empty array when `timeout` elapses first.
  async fn next(Self, timeout? : @strata.Duration) -> Array[@strata.StoredEvent]
  /// The position of the last event handed out.
  fn position(Self) -> @strata.Position
  /// Stops the subscription.
  fn close(Self) -> Unit
}

///|
/// A projector's or reactor's progress marker.
pub struct Checkpoint {
  name : String
  position : @strata.Position
} derive(Eq, Debug, ToJson, FromJson)

///|
/// Builds a checkpoint.
pub fn Checkpoint::Checkpoint(
  name~ : String,
  position~ : @strata.Position,
) -> Checkpoint {
  { name, position, }
}

///|
/// Raised when a sealed key is requested through `key_for` (use `unseal`).
pub(all) suberror KeySealed {
  KeySealed(subject~ : String)
} derive(Eq, Debug)

///|
/// Raised by `unseal` when the subject never had a key; unsealing never
/// creates one.
pub(all) suberror KeyMissing {
  KeyMissing(subject~ : String)
} derive(Eq, Debug)

///|
/// Raised when a destroyed (shredded) key is requested.
pub(all) suberror KeyDestroyed {
  KeyDestroyed(subject~ : String)
} derive(Eq, Debug)

///|
/// Storage for read models written inline with appends or by projectors.
///
/// `commit` is the unit of atomicity for the read side: the rows and the
/// checkpoint it carries become visible together or not at all. Projectors
/// use it so that at-least-once delivery is effectively-once.
pub(open) trait ViewStore {
  /// Applies several writes and, optionally, a checkpoint atomically.
  async fn commit(Self, writes~ : Array[ViewWrite], checkpoint? : Checkpoint) -> Unit
  /// A checkpoint written through `commit` (the same table
  /// `EventStore::load_checkpoint` reads).
  async fn checkpoint(Self, name : String) -> @strata.Position?
  /// Reads one row.
  async fn get(Self, table~ : String, key~ : String) -> Json?
  /// Writes one row.
  async fn put(Self, table~ : String, key~ : String, value : Json) -> Unit
  /// Deletes one row.
  async fn delete(Self, table~ : String, key~ : String) -> Unit
  /// The keys of a table.
  async fn keys(Self, table~ : String) -> Array[String]
  /// Atomically replaces table `to` with table `from` (used by `rebuild`).
  async fn swap(Self, from~ : String, to~ : String) -> Unit
}

///|
/// Per-subject encryption keys backing shredding and sealing.
pub(open) trait KeyStore {
  /// The key for a subject, created on first use. Raises `KeySealed` while
  /// the subject is sealed and `KeyDestroyed` after `destroy`.
  async fn key_for(Self, subject : String) -> Bytes
  /// Destroys the key: shredded fields become unreadable forever.
  async fn destroy(Self, subject : String) -> Unit
  /// Withholds the key from ordinary reads until `destroy`; `unseal` does not
  /// lift the seal, it only hands the key to a capability holder once.
  async fn seal(Self, subject : String) -> Unit
  /// Returns a sealed key to a capability holder; every call is recorded.
  /// Raises `KeyDestroyed` for a destroyed key and never re-creates it.
  async fn unseal(Self, subject : String, capability~ : String) -> Bytes
}

///|
/// The event store contract. Every implementation must pass
/// `@testing.contract`.
///
/// Semantics:
/// - `append` is atomic: all events, the inline view writes, or nothing.
///   The store adds system tags (`$stream:`, `$category:`, `$tenant:`) and
///   assigns positions and versions. It raises `AppendConflict` when the
///   condition fails. For `Dcb`, `after` is the head the writer observed
///   before reading its scope; any matching event with a greater position
///   conflicts.
/// - `read` returns events in global position order, strictly after `after`.
/// - Idempotency keys are indexed globally (`find_idempotent`); the runtime
///   decides whether a match is a replay or a conflict.
/// - Subscriptions deliver in global order, at least once.
pub(open) trait EventStore {
  /// Appends events to a stream under a condition.
  async fn append(
    Self,
    stream~ : @strata.StreamId,
    condition~ : @strata.AppendCondition,
    events~ : Array[@strata.NewEvent],
    recorded_at~ : @strata.Instant,
    inline? : Array[ViewWrite],
  ) -> AppendResult
  /// A page of events matching a selection, after a position.
  async fn read(
    Self,
    selection : @strata.Selection,
    after? : @strata.Position,
    limit? : Int,
  ) -> Array[@strata.StoredEvent]
  /// The events of one stream from a version (1-based) onwards.
  async fn read_stream(Self, stream : @strata.StreamId, from_version? : Int) -> Array[
    @strata.StoredEvent,
  ]
  /// The position of the last event in the log (`start` when empty).
  async fn head(Self) -> @strata.Position
  /// Events recorded under an idempotency key, optionally within one stream.
  async fn find_idempotent(Self, key~ : String, stream? : @strata.StreamId) -> Array[
    @strata.StoredEvent,
  ]
  /// A live feed of events matching a selection, after `from`.
  async fn subscribe(
    Self,
    selection : @strata.Selection,
    from~ : @strata.Position,
  ) -> &Subscription
  /// The checkpoint of a projector or reactor.
  async fn load_checkpoint(Self, name : String) -> @strata.Position?
  /// Saves a checkpoint.
  async fn save_checkpoint(Self, name : String, position : @strata.Position) -> Unit
  /// Loads a snapshot.
  async fn load_snapshot(Self, key : SnapshotKey) -> SnapshotRecord?
  /// Saves a snapshot.
  async fn save_snapshot(Self, key : SnapshotKey, record : SnapshotRecord) -> Unit
  /// The view store this event store writes inline projections to.
  fn views(Self) -> &ViewStore
}
