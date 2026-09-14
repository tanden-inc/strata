///|
/// Raised when a string cannot be parsed as a `StreamId`.
pub(all) suberror InvalidStreamId {
  InvalidStreamId(String)
} derive(Eq, Debug)

///|
/// Raised when a string is not an ISO-8601 UTC instant.
pub(all) suberror InvalidInstant {
  InvalidInstant(String)
} derive(Eq, Debug)

///|
/// Raised when user code tries to write a system tag (a tag starting with `$`)
/// or an otherwise malformed tag.
pub(all) suberror InvalidTag {
  InvalidTag(Tag)
} derive(Eq, Debug)

///|
/// Raised when a stored event cannot be turned back into a domain value.
///
/// `position` is `None` when the failure happened before the event had a
/// position (for example while encoding).
pub(all) suberror DecodeError {
  DecodeError(event_type~ : String, position~ : Position?, reason~ : String)
} derive(Eq, Debug)

///|
/// Raised by interface stubs that are not implemented yet. Every effectful
/// stub raises this instead of panicking so that a red test stays a test
/// failure rather than a crashed test binary. `make todo` lists them.
pub(all) suberror NotImplemented {
  NotImplemented(String)
} derive(Eq, Debug)

///|
/// Marks an unimplemented, raise-capable body: `todo("Type::method")`.
pub fn[T] todo(name : String) -> T raise NotImplemented {
  raise NotImplemented(name)
}
