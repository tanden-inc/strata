///|
/// The identity of a recorded event.
///
/// The runtime mints ULIDs (26-character Crockford base32, monotonic within a
/// batch); tests use deterministic ids such as `evt-0001`. The type does not
/// enforce the ULID shape so that both are `EventId`s.
pub(all) struct EventId(String) derive (
  Eq,
  Compare,
  Hash,
  Debug,
  @quickcheck.Arbitrary,
)

///|
let crockford : String = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

///|
fn crockford_value(c : Char) -> Int? {
  let u = c.to_ascii_uppercase()
  for i in 0..<32 {
    if crockford.get_char(i).unwrap() == u {
      return Some(i)
    }
  }
  None
}

///|
fn crockford_char(value : Int) -> Char {
  crockford.get_char(value & 31).unwrap()
}

///|
fn entropy10(random : Bytes) -> Array[Byte] {
  let out : Array[Byte] = Array::make(10, b'\x00')
  let n = if random.length() < 10 { random.length() } else { 10 }
  for i in 0..<n {
    out[i] = random[i]
  }
  out
}

///|
fn encode_crockford_time(ms : Int64) -> Array[Char] {
  let mut now = ms
  let chars : Array[Char] = Array::make(10, '0')
  for i in 0..<10 {
    chars[9 - i] = crockford_char((now % 32L).to_int())
    now = now / 32L
  }
  chars
}

///|
fn encode_crockford_entropy(bytes : Array[Byte]) -> Array[Char] {
  let chars : Array[Char] = []
  let mut acc : UInt = 0
  let mut bits = 0
  for b in bytes {
    acc = (acc << 8) | b.to_uint()
    bits += 8
    while bits >= 5 {
      bits -= 5
      chars.push(crockford_char(((acc >> bits) & 31).reinterpret_as_int()))
      acc = acc & ((1U << bits) - 1)
    }
  }
  chars
}

///|
fn decode_crockford_time(text : String) -> Instant? {
  let mut n = 0L
  for i in 0..<10 {
    match crockford_value(text.get_char(i).unwrap()) {
      None => return None
      Some(v) => n = n * 32L + v.to_int64()
    }
  }
  Some(Instant(n))
}

///|
fn decode_crockford_entropy(text : String) -> Array[Byte]? {
  let buf : Array[Byte] = []
  let mut acc : UInt = 0
  let mut bits = 0
  for i in 10..<26 {
    match crockford_value(text.get_char(i).unwrap()) {
      None => return None
      Some(v) => {
        acc = (acc << 5) | v.reinterpret_as_uint()
        bits += 5
        if bits >= 8 {
          bits -= 8
          buf.push(((acc >> bits) & 0xFF).to_byte())
          acc = acc & ((1U << bits) - 1)
        }
      }
    }
  }
  Some(buf)
}

///|
fn increment_bytes(bytes : Array[Byte]) -> Array[Byte] {
  let out = bytes.copy()
  let mut i = out.length() - 1
  while i >= 0 {
    let n = out[i].to_int() + 1
    if n < 256 {
      out[i] = n.to_byte()
      break
    }
    out[i] = b'\x00'
    i = i - 1
  }
  out
}

///|
fn encode_ulid(timestamp : Instant, entropy : Array[Byte]) -> EventId {
  let chars = encode_crockford_time(timestamp.0)
  chars.append(encode_crockford_entropy(entropy)[:])
  EventId(String::from_iter(chars.iter()))
}

///|
/// Builds a ULID from a timestamp and 10 random bytes (80 bits of entropy).
pub fn EventId::ulid(timestamp~ : Instant, random~ : Bytes) -> EventId {
  encode_ulid(timestamp, entropy10(random))
}

///|
/// The next id in a monotonic ULID batch: same timestamp, random part plus one.
pub fn EventId::increment(self : EventId) -> EventId {
  guard self.is_ulid() else { self }
  match (self.timestamp(), decode_crockford_entropy(self.0)) {
    (Some(ts), Some(entropy)) => encode_ulid(ts, increment_bytes(entropy))
    _ => self
  }
}

///|
/// The timestamp encoded in a ULID, or `None` for non-ULID ids.
pub fn EventId::timestamp(self : EventId) -> Instant? {
  if self.is_ulid() {
    decode_crockford_time(self.0)
  } else {
    None
  }
}

///|
/// Whether this id has the ULID shape.
pub fn EventId::is_ulid(self : EventId) -> Bool {
  self.0.length() == 26 && self.0.all(c => crockford_value(c) is Some(_))
}

///|
pub impl Show for EventId with fn to_string(self) {
  self.0
}

///|
pub impl ToJson for EventId with fn to_json(self) {
  Json::string(self.0)
}

///|
pub impl @json.FromJson for EventId with fn from_json(json, path) {
  guard json is String(s) else {
    raise @json.JsonDecodeError((path, "EventId: expected a string"))
  }
  EventId(s)
}

///|
/// The name of a stream: `<category>-<id>`, or `<tenant>/<category>-<id>`
/// when a tenant is set.
pub(all) struct StreamId(String) derive(Eq, Compare, Hash, Debug)

///|
fn StreamId::name_part(self : StreamId) -> String {
  match self.0.split_once("/") {
    Some((_, rest)) => rest.to_owned()
    None => self.0
  }
}

///|
/// Builds a stream name from its parts.
pub fn StreamId::of(
  category~ : String,
  id~ : String,
  tenant? : String,
) -> StreamId {
  match tenant {
    Some(t) => StreamId("\{t}/\{category}-\{id}")
    None => StreamId("\{category}-\{id}")
  }
}

///|
/// Parses `"account-acc-1"` or `"t1/account-acc-1"`. The category is the
/// prefix up to the first `-`.
pub fn StreamId::parse(text : String) -> StreamId raise InvalidStreamId {
  let name = match text.split_once("/") {
    Some((tenant, rest)) => {
      if tenant.is_empty() || rest.is_empty() {
        raise InvalidStreamId(text)
      }
      rest.to_owned()
    }
    None => text
  }
  match name.split_once("-") {
    Some((category, id)) =>
      if category.is_empty() || id.is_empty() {
        raise InvalidStreamId(text)
      } else {
        StreamId(text)
      }
    None => raise InvalidStreamId(text)
  }
}

///|
/// The category part of the name.
pub fn StreamId::category(self : StreamId) -> String {
  match self.name_part().split_once("-") {
    Some((category, _)) => category.to_owned()
    None => self.name_part()
  }
}

///|
/// The entity id part of the name.
pub fn StreamId::entity_id(self : StreamId) -> String {
  match self.name_part().split_once("-") {
    Some((_, id)) => id.to_owned()
    None => ""
  }
}

///|
/// The tenant prefix, if any.
pub fn StreamId::tenant(self : StreamId) -> String? {
  match self.0.split_once("/") {
    Some((tenant, _)) => Some(tenant.to_owned())
    None => None
  }
}

///|
pub impl Show for StreamId with fn to_string(self) {
  self.0
}

///|
pub impl ToJson for StreamId with fn to_json(self) {
  Json::string(self.0)
}

///|
pub impl @json.FromJson for StreamId with fn from_json(json, path) {
  guard json is String(s) else {
    raise @json.JsonDecodeError((path, "StreamId: expected a string"))
  }
  StreamId(s)
}

///|
/// A position in the global log. Positions are dense, strictly increasing,
/// and assigned by the store.
pub(all) struct Position(Int64) derive(Eq, Compare, Hash, Debug)

///|
/// The position before the first event; subscribe from here to read everything.
pub let start : Position = Position(0)

///|
/// The position after this one.
pub fn Position::next(self : Position) -> Position {
  Position(self.0 + 1)
}

///|
pub impl Show for Position with fn to_string(self) {
  self.0.to_string()
}

///|
pub impl ToJson for Position with fn to_json(self) {
  Json::number(self.0.to_double())
}

///|
pub impl @json.FromJson for Position with fn from_json(json, path) {
  guard json is Number(n, ..) else {
    raise @json.JsonDecodeError((path, "Position: expected a number"))
  }
  Position(n.to_int64())
}

///|
/// The principal acting on the system, for example `Actor("user:alice")`.
pub(all) struct Actor(String) derive (
  Eq,
  Compare,
  Hash,
  Debug,
  @quickcheck.Arbitrary,
)

///|
pub impl Show for Actor with fn to_string(self) {
  self.0
}

///|
pub impl ToJson for Actor with fn to_json(self) {
  Json::string(self.0)
}

///|
pub impl @json.FromJson for Actor with fn from_json(json, path) {
  guard json is String(s) else {
    raise @json.JsonDecodeError((path, "Actor: expected a string"))
  }
  Actor(s)
}

///|
/// A tag attached to an event, conventionally `key:value` such as `code:X`.
///
/// Tags starting with `$` are system tags (`$stream:`, `$category:`,
/// `$tenant:`) written by the store; user code cannot append them.
pub(all) struct Tag(String) derive(Eq, Compare, Hash, Debug)

///|
/// Builds a `key:value` tag.
pub fn Tag::kv(key~ : String, value~ : String) -> Tag {
  Tag("\{key}:\{value}")
}

///|
/// The part before the first `:`, or the whole tag when there is none.
pub fn Tag::key(self : Tag) -> String {
  match self.0.split_once(":") {
    Some((key, _)) => key.to_owned()
    None => self.0
  }
}

///|
/// The part after the first `:`, or `None` when there is none.
pub fn Tag::value(self : Tag) -> String? {
  match self.0.split_once(":") {
    Some((_, value)) => Some(value.to_owned())
    None => None
  }
}

///|
/// Whether this is a system tag (starts with `$`).
pub fn Tag::is_system(self : Tag) -> Bool {
  self.0.has_prefix("$")
}

///|
pub impl Show for Tag with fn to_string(self) {
  self.0
}

///|
pub impl ToJson for Tag with fn to_json(self) {
  Json::string(self.0)
}

///|
pub impl @json.FromJson for Tag with fn from_json(json, path) {
  guard json is String(s) else {
    raise @json.JsonDecodeError((path, "Tag: expected a string"))
  }
  Tag(s)
}

///|
/// The ids that the events emitted by one decision will receive.
///
/// The runtime reserves the batch before calling `decide`, so a decision can
/// embed `env.ids.at(i)` in the i-th event it emits and the store guarantees
/// `recorded.id == recorded.event.id`.
pub struct IdBatch {
  priv at : (Int) -> EventId
  priv high_water : Ref[Int]
}

///|
/// The id of the i-th event (0-based) emitted by this decision.
pub fn IdBatch::at(self : IdBatch, index : Int) -> EventId {
  if index > self.high_water.val {
    self.high_water.val = index
  }
  (self.at)(index)
}

///|
/// The highest index handed out so far, or -1 when no id was taken. An
/// `IdGenerator` uses it to start the next batch after the ids a decision
/// actually consumed, so batches never overlap.
pub fn IdBatch::high_water(self : IdBatch) -> Int {
  self.high_water.val
}

///|
/// A monotonic ULID batch starting at `base`.
pub fn IdBatch::from(base : EventId) -> IdBatch {
  {
    high_water: { val: -1, },
    at: i => {
      let mut id = base
      for _ in 0..<i {
        id = id.increment()
      }
      id
    },
  }
}

///|
/// The same batch starting `by` ids later (`at(i)` becomes `at(i + by)`).
pub fn IdBatch::offset(self : IdBatch, by : Int) -> IdBatch {
  { high_water: { val: -1, }, at: i => (self.at)(i + by), }
}

///|
/// A deterministic batch for tests: `evt-0001`, `evt-0002`, ...
pub fn IdBatch::deterministic(prefix? : String = "evt-") -> IdBatch {
  {
    high_water: { val: -1, },
    at: i => {
      let mut padded = (i + 1).to_string()
      while padded.length() < 4 {
        padded = "0" + padded
      }
      EventId(prefix + padded)
    },
  }
}
