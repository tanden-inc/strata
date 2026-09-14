///|
/// A field inside an event payload, `"<EventType>.<field>"`, e.g. `"Opened.owner"`.
pub(all) struct FieldPath(String) derive(Eq, Compare, Hash, Debug)

///|
/// A value that may be withheld: readable, sealed (readable only through
/// `Runtime::unseal` with a capability), or shredded (key destroyed).
pub(all) enum Sealed[T] {
  Value(T)
  Sealed
  Shredded
} derive(Eq, Debug)

///|
/// Marks payload fields as encrypted with a per-subject key. After the key is
/// destroyed (`Runtime::forget`) the field decodes as `redacted_as`.
pub fn JsonCodec::shred(
  self : JsonCodec,
  fields~ : Array[FieldPath],
  redacted_as? : Json = Json::string("<redacted>"),
) -> Unit {
  self.shredded.clear()
  self.shredded.append(fields[:])
  self.redacted_as = redacted_as
}

///|
/// Marks metadata fields (for example `"actor"`) as sealed when `when`
/// accepts the command's context: stored encrypted, returned as `Sealed`,
/// readable only through `Runtime::unseal`.
pub fn JsonCodec::seal(
  self : JsonCodec,
  meta~ : Array[String],
  when~ : (@strata.Context) -> Bool,
) -> Unit {
  self.sealed_meta.clear()
  self.sealed_meta.append(meta[:])
  self.seal_when = Some(when)
}

///|
/// The shredded field paths.
pub fn JsonCodec::shredded_fields(self : JsonCodec) -> Array[FieldPath] {
  self.shredded
}

///|
/// The sealed metadata field names.
pub fn JsonCodec::sealed_meta(self : JsonCodec) -> Array[String] {
  self.sealed_meta
}

///|
/// Whether a context asks for sealing.
pub fn JsonCodec::seals(self : JsonCodec, ctx : @strata.Context) -> Bool {
  match self.seal_when {
    Some(when) => when(ctx)
    None => false
  }
}
