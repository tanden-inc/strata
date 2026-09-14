///|
/// What a writer expects the stream version to be.
pub(all) enum ExpectedVersion {
  /// No expectation.
  Any
  /// The stream must not exist yet ("create only").
  NoStream
  /// The stream must be exactly at this version.
  Exact(Int)
} derive(Eq, Debug, ToJson, FromJson)

///|
/// The condition under which an append is accepted.
pub(all) enum AppendCondition {
  /// Optimistic concurrency on one stream.
  Stream(StreamId, ExpectedVersion)
  /// Dynamic consistency boundary: no event matching `selection` may have
  /// been recorded after `after` (`None` means the selection must be empty).
  Dcb(selection~ : Selection, after~ : Position?)
} derive(Eq, Debug)

///|
/// Raised by the store when an append condition no longer holds.
pub(all) suberror AppendConflict {
  StreamConflict(stream~ : StreamId, expected~ : ExpectedVersion, actual~ : Int)
  BoundaryConflict(selection~ : Selection, after~ : Position?, at~ : Position)
} derive(Eq, Debug)

///|
/// Raised when an idempotency key is reused with a different command.
pub(all) suberror IdempotencyConflict {
  KeyReused(key~ : String, stream~ : StreamId?)
} derive(Eq, Debug)

///|
/// The result of executing a command.
pub struct Outcome[E, N] {
  /// What was appended (empty on an idempotent replay of a rejected command).
  events : Array[Recorded[E]]
  /// Advice computed beside the decision; never stored.
  notices : Array[N]
  /// Stream version after the append; hand it out as an ETag.
  version : Int
  /// Global position of the last appended event; what async read models chase.
  position : Position
  /// `true` when the idempotency key matched an earlier execution.
  deduplicated : Bool
} derive(Eq, Debug)

///|
/// Builds an outcome.
pub fn[E, N] Outcome::Outcome(
  events~ : Array[Recorded[E]],
  notices? : Array[N] = [],
  version~ : Int,
  position~ : Position,
  deduplicated? : Bool = false,
) -> Outcome[E, N] {
  { events, notices, version, position, deduplicated, }
}
