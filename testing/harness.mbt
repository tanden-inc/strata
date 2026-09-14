///|
/// A runtime for tests: `MemoryStore`, a fixed clock at the epoch, sequential
/// ids (`evt-0001`, ...), the default codec.
pub fn runtime(
  clock? : @rt.Clock = @rt.Clock::fixed(@strata.Instant(0)),
  ids? : @rt.IdGenerator = @rt.IdGenerator::sequential(),
  codec? : @codec.JsonCodec = @codec.JsonCodec(),
) -> @rt.Runtime {
  @rt.Runtime(@store.MemoryStore(), codec~, clock~, ids~)
}

///|
/// A deterministic environment.
pub fn env(
  actor? : @strata.Actor = @strata.Actor("user:test"),
  now? : @strata.Instant = @strata.Instant(0),
  tenant? : String,
  ids? : @strata.IdBatch = @strata.IdBatch::deterministic(),
) -> @strata.Env {
  @strata.Env(actor~, now~, tenant?, ids~)
}

///|
/// A recorded event for reactor and projection tests.
pub fn[E] recorded(
  event : E,
  stream~ : @strata.StreamId,
  version~ : Int,
  position~ : @strata.Position,
  id? : @strata.EventId,
  event_type? : String = "",
  actor? : @strata.Actor,
  at? : @strata.Instant = @strata.Instant(0),
  tags? : Array[@strata.Tag] = [],
) -> @strata.Recorded[E] {
  let meta = match actor {
    Some(actor) => @strata.Metadata(actor~)
    None => @strata.Metadata()
  }
  @strata.Recorded(
    id=id.unwrap_or(@strata.EventId("evt-0001")),
    position~,
    stream~,
    version~,
    event_type~,
    event~,
    tags~,
    recorded_at=at,
    meta~,
  )
}

///|
fn system_tags(stream : @strata.StreamId) -> Array[@strata.Tag] {
  let tags : Array[@strata.Tag] = [
    @strata.Tag::kv(key="$stream", value=stream.0),
    @strata.Tag::kv(key="$category", value=stream.category()),
  ]
  match stream.tenant() {
    Some(tenant) => tags.push(@strata.Tag::kv(key="$tenant", value=tenant))
    None => ()
  }
  tags
}

///|
/// A stored event for codec and store tests.
pub fn stored(
  event_type~ : String,
  data~ : Json,
  stream~ : @strata.StreamId,
  version~ : Int,
  position~ : @strata.Position,
  schema? : Int = 1,
  id? : @strata.EventId,
  tags? : Array[@strata.Tag] = [],
  at? : @strata.Instant = @strata.Instant(0),
) -> @strata.StoredEvent {
  let tags = if tags.is_empty() { system_tags(stream) } else { tags }
  @strata.StoredEvent(
    id=id.unwrap_or(@strata.EventId("evt-0001")),
    position~,
    stream~,
    version~,
    event_type~,
    schema~,
    data~,
    tags~,
    meta=@strata.Metadata(),
    recorded_at=at,
  )
}

///|
/// The result of decoding a set of fixtures: what decoded, and how many
/// deprecated shapes were skipped.
pub struct FixtureReport[E] {
  decoded : Array[@strata.Recorded[E]]
  skipped : Int
} derive(Eq, Debug)

///|
/// A set of historical event shapes that must keep decoding.
pub struct Fixtures {
  priv events : Array[@strata.StoredEvent]
}

///|
/// Fixtures from stored events (load them from JSON files in your own tests).
pub fn Fixtures::from_stored(events : Array[@strata.StoredEvent]) -> Fixtures {
  { events, }
}

///|
/// Fixtures from raw `(event_type, schema, data)` triples.
pub fn Fixtures::from_json(shapes : Array[(String, Int, Json)]) -> Fixtures {
  let events = shapes.mapi((i, shape) => {
    let (event_type, schema, data) = shape
    @strata.StoredEvent(
      id=@strata.EventId("fix-\{i}"),
      position=@strata.Position((i + 1).to_int64()),
      stream=@strata.StreamId("fixture-f"),
      version=i + 1,
      event_type~,
      schema~,
      data~,
      meta=@strata.Metadata(),
      recorded_at=@strata.Instant(0),
    )
  })
  { events, }
}

///|
/// Decodes every fixture with the codec; raises `DecodeError` on the first
/// shape that no longer decodes.
pub fn[E : @json.FromJson] Fixtures::all_decode(
  self : Fixtures,
  codec : @codec.JsonCodec,
) -> FixtureReport[E] raise {
  let decoded : Array[@strata.Recorded[E]] = codec.decode_all(self.events)
  { decoded, skipped: self.events.length() - decoded.length(), }
}
