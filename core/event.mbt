///|
/// An event as handed to the store: already encoded, not yet positioned.
pub struct NewEvent {
  id : EventId
  event_type : String
  schema : Int
  data : Json
  tags : Array[Tag]
  meta : Metadata
} derive(Eq, Debug)

///|
/// Builds a new event. Raises `InvalidTag` if any tag is a system tag.
pub fn NewEvent::NewEvent(
  id~ : EventId,
  event_type~ : String,
  schema~ : Int,
  data~ : Json,
  tags? : Array[Tag] = [],
  meta~ : Metadata,
) -> NewEvent raise InvalidTag {
  for tag in tags {
    if tag.is_system() {
      raise InvalidTag(tag)
    }
  }
  { id, event_type, schema, data, tags, meta, }
}

///|
/// An event as the store returns it: the type-erased envelope, with system
/// tags included in `tags`.
pub struct StoredEvent {
  id : EventId
  position : Position
  stream : StreamId
  version : Int
  event_type : String
  schema : Int
  data : Json
  tags : Array[Tag]
  meta : Metadata
  recorded_at : Instant
} derive(Eq, Debug, ToJson, FromJson)

///|
/// Builds a stored event (stores and test fixtures).
pub fn StoredEvent::StoredEvent(
  id~ : EventId,
  position~ : Position,
  stream~ : StreamId,
  version~ : Int,
  event_type~ : String,
  schema~ : Int,
  data~ : Json,
  tags? : Array[Tag] = [],
  meta~ : Metadata,
  recorded_at~ : Instant,
) -> StoredEvent {
  {
    id,
    position,
    stream,
    version,
    event_type,
    schema,
    data,
    tags,
    meta,
    recorded_at,
  }
}

///|
/// The user tags of a stored event (system tags removed).
pub fn StoredEvent::user_tags(self : StoredEvent) -> Array[Tag] {
  self.tags.filter(t => t.is_system() == false)
}

///|
/// A decoded event with its envelope. `tags` holds user tags only.
pub struct Recorded[E] {
  id : EventId
  position : Position
  stream : StreamId
  version : Int
  event_type : String
  event : E
  tags : Array[Tag]
  recorded_at : Instant
  meta : Metadata
} derive(Eq, Debug)

///|
/// Builds a recorded event (runtime and tests).
pub fn[E] Recorded::Recorded(
  id~ : EventId,
  position~ : Position,
  stream~ : StreamId,
  version~ : Int,
  event_type~ : String,
  event~ : E,
  tags? : Array[Tag] = [],
  recorded_at~ : Instant,
  meta~ : Metadata,
) -> Recorded[E] {
  { id, position, stream, version, event_type, event, tags, recorded_at, meta, }
}

///|
/// Pairs a stored envelope with its decoded event; system tags are dropped.
pub fn[E] Recorded::from_stored(stored : StoredEvent, event : E) -> Recorded[E] {
  Recorded(
    id=stored.id,
    position=stored.position,
    stream=stored.stream,
    version=stored.version,
    event_type=stored.event_type,
    event~,
    tags=stored.user_tags(),
    recorded_at=stored.recorded_at,
    meta=stored.meta,
  )
}

///|
/// The entity id part of the stream name.
pub fn[E] Recorded::entity_id(self : Recorded[E]) -> String {
  self.stream.entity_id()
}

///|
/// A context for commands issued *because of* this event: the correlation id
/// is inherited, the causation id and the idempotency key are this event's id.
/// The actor defaults to the recorded actor, then to `Actor("system")`.
pub fn[E] Recorded::caused(self : Recorded[E], actor? : Actor) -> Context {
  let actor = match actor {
    Some(a) => a
    None => self.meta.actor.unwrap_or(Actor("system"))
  }
  {
    actor,
    tenant: self.meta.tenant,
    correlation_id: Some(self.meta.correlation_id.unwrap_or(self.id.0)),
    causation_id: Some(self.id),
    idempotency_key: Some(self.id.0),
    flags: [],
    extra: self.meta.extra,
  }
}

///|
/// Whether an event type name belongs to Strata itself (`$strata.forgotten`,
/// `$strata.unsealed`, ...). Codecs skip these when decoding domain events;
/// folds and projections never see them.
pub fn is_system_event_type(event_type : String) -> Bool {
  event_type.has_prefix("$")
}
