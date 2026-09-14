///|
/// How the JSON produced by `derive(ToJson)` names an enum variant, which is
/// how Strata learns an event's type name.
///
/// - `Flat` (the derive default): `["Deposited", {"amount": 100}]`, or the bare
///   string `"Closed"` for a payload-less variant.
/// - `Legacy(tag_key)`: `{"$tag": "Deposited", "amount": 100}`, produced by
///   `derive(ToJson(style="legacy"))`.
pub(all) enum TagStyle {
  Flat
  Legacy(tag_key~ : String)
} derive(Eq, Debug)

///|
/// An encoded event: the type name the codec derived, the schema version it
/// was written under, and the whole derived JSON value.
pub struct Encoded {
  event_type : String
  schema : Int
  data : Json
} derive(Eq, Debug)

///|
/// Builds an encoded event.
pub fn Encoded::Encoded(
  event_type~ : String,
  schema~ : Int,
  data~ : Json,
) -> Encoded {
  { event_type, schema, data, }
}

///|
/// A `Json -> Json` transformation applied to an event payload at read time.
/// Upcasters are pure and unit-testable; stored events are never rewritten.
pub struct Upcast {
  priv apply : (Json) -> Json raise
}

///|
fn copy_json_map(obj : Map[String, Json]) -> Map[String, Json] {
  let out : Map[String, Json] = Map([])
  obj.each((k, v) => out[k] = v)
  out
}

///|
fn map_payload(
  data : Json,
  f : (Map[String, Json]) -> Map[String, Json],
) -> Json {
  match data {
    Object(obj) => Json::object(f(copy_json_map(obj)))
    Array(arr) =>
      if arr.length() >= 2 {
        match arr[1] {
          Object(obj) => {
            let out = arr.copy()
            out[1] = Json::object(f(copy_json_map(obj)))
            Json::array(out)
          }
          _ => data
        }
      } else {
        data
      }
    _ => data
  }
}

///|
fn set_type_tag(data : Json, type_name : String, style : TagStyle) -> Json {
  match style {
    Flat =>
      match data {
        String(_) => Json::string(type_name)
        Array(arr) => {
          let out = if arr.is_empty() {
            [Json::string(type_name)]
          } else {
            let out = arr.copy()
            out[0] = Json::string(type_name)
            out
          }
          Json::array(out)
        }
        other => other
      }
    Legacy(tag_key~) =>
      match data {
        Object(obj) => {
          let out = copy_json_map(obj)
          out[tag_key] = Json::string(type_name)
          Json::object(out)
        }
        String(_) => Json::object(Map([(tag_key, Json::string(type_name))]))
        other => other
      }
  }
}

///|
/// Adds a field with a default value if it is missing.
pub fn Upcast::add_field(name : String, default : Json) -> Upcast {
  {
    apply: data => {
      map_payload(data, obj => {
        if obj.contains(name) == false {
          obj[name] = default
        }
        obj
      })
    },
  }
}

///|
/// Renames a field.
pub fn Upcast::rename_field(from~ : String, to~ : String) -> Upcast {
  {
    apply: data => {
      map_payload(data, obj => {
        match obj.get(from) {
          None => obj
          Some(value) => {
            obj.remove(from)
            obj[to] = value
            obj
          }
        }
      })
    },
  }
}

///|
/// Removes a field.
pub fn Upcast::remove_field(name : String) -> Upcast {
  {
    apply: data => {
      map_payload(data, obj => {
        obj.remove(name)
        obj
      })
    },
  }
}

///|
/// An arbitrary transformation.
pub fn Upcast::map(f : (Json) -> Json raise) -> Upcast {
  { apply: f, }
}

///|
/// This upcast followed by another.
pub fn Upcast::then(self : Upcast, next : Upcast) -> Upcast {
  { apply: data => next.run(self.run(data)), }
}

///|
/// Applies the upcast to a payload.
pub fn Upcast::run(self : Upcast, payload : Json) -> Json raise {
  (self.apply)(payload)
}

///|
/// The serialisation policy of an application: the current schema version,
/// the tag style of derived JSON, upcasters per event type and version,
/// renamed and deprecated type names, and privacy markings.
///
/// Storage is exactly what `derive(ToJson)` produces; the codec adds nothing
/// to the payload. Configure with the cascade syntax:
///
/// ```mbt nocheck
/// let codec = @codec.JsonCodec(schema_version=2)
///   ..migrate("Withdrawn", from=1, @codec.Upcast::add_field("fee", 0))
///   ..rename("Opened", to="AccountOpened")
///   ..deprecated("LegacyFeeCharged")
/// ```
pub struct JsonCodec {
  priv schema_version : Int
  priv style : TagStyle
  priv upcasts : Map[String, Array[(Int, Upcast)]]
  priv renames : Map[String, String]
  priv deprecated : Map[String, String?]
  priv shredded : Array[FieldPath]
  priv mut redacted_as : Json
  priv sealed_meta : Array[String]
  priv mut seal_when : ((@strata.Context) -> Bool)?
}

///|
/// Builds a codec for the given current schema version.
pub fn JsonCodec::JsonCodec(
  schema_version? : Int = 1,
  style? : TagStyle = Flat,
) -> JsonCodec {
  {
    schema_version,
    style,
    upcasts: Map([]),
    renames: Map([]),
    deprecated: Map([]),
    shredded: [],
    redacted_as: Json::string("<redacted>"),
    sealed_meta: [],
    seal_when: None,
  }
}

///|
/// The schema version new events are written under.
pub fn JsonCodec::schema_version(self : JsonCodec) -> Int {
  self.schema_version
}

///|
/// The tag style.
pub fn JsonCodec::style(self : JsonCodec) -> TagStyle {
  self.style
}

///|
/// Registers an upcaster for events of `event_type` written under schema
/// version `from`; it produces the `from + 1` shape. Chains are applied in
/// version order at read time.
pub fn JsonCodec::migrate(
  self : JsonCodec,
  event_type : String,
  from~ : Int,
  step : Upcast,
) -> Unit {
  if self.upcasts.contains(event_type) == false {
    self.upcasts[event_type] = []
  }
  self.upcasts[event_type].push((from, step))
}

///|
/// Maps a stored type name to the current variant name.
pub fn JsonCodec::rename(
  self : JsonCodec,
  stored : String,
  to~ : String,
) -> Unit {
  self.renames[stored] = to
}

///|
/// Marks a stored type name as deprecated: still readable as a `StoredEvent`,
/// but `decode` returns `None` so folds skip it. `replaced_by` is documentation.
pub fn JsonCodec::deprecated(
  self : JsonCodec,
  event_type : String,
  replaced_by? : String,
) -> Unit {
  self.deprecated[event_type] = replaced_by
}

///|
/// Whether a stored type name is deprecated (after renames).
pub fn JsonCodec::is_deprecated(self : JsonCodec, event_type : String) -> Bool {
  let current = self.renames.get(event_type).unwrap_or(event_type)
  self.deprecated.contains(event_type) || self.deprecated.contains(current)
}

///|
fn untagged(_data : Json) -> String raise @strata.DecodeError {
  raise @strata.DecodeError(
    event_type="",
    position=None,
    reason="JSON value has no type tag",
  )
}

///|
/// The type name a derived JSON value carries, according to the tag style.
pub fn JsonCodec::type_of(
  self : JsonCodec,
  data : Json,
) -> String raise @strata.DecodeError {
  match self.style {
    Flat =>
      match data {
        String(name) => name
        Array(arr) =>
          match arr.get(0) {
            Some(String(name)) => name
            _ => untagged(data)
          }
        _ => untagged(data)
      }
    Legacy(tag_key~) =>
      match data {
        String(name) => name
        Object(obj) =>
          match obj.get(tag_key) {
            Some(String(name)) => name
            _ => untagged(data)
          }
        _ => untagged(data)
      }
  }
}

///|
/// Encodes a domain event: `Json(event)` plus the derived type name and the
/// current schema version.
pub fn[E : ToJson] JsonCodec::encode(
  self : JsonCodec,
  event : E,
) -> Encoded raise @strata.DecodeError {
  let data = Json(event)
  { event_type: self.type_of(data), schema: self.schema_version, data, }
}

///|
/// Brings a stored payload to the current schema: applies the type rename,
/// then every registered upcast from `schema` up to the current version.
/// Returns the current type name and payload. Pure.
pub fn JsonCodec::upgrade(
  self : JsonCodec,
  event_type~ : String,
  schema~ : Int,
  data : Json,
) -> (String, Json) raise @strata.DecodeError {
  let event_type = self.renames.get(event_type).unwrap_or(event_type)
  let mut data = set_type_tag(data, event_type, self.style)
  let steps = self.upcasts.get(event_type).unwrap_or([]).copy()
  steps.sort_by_key(step => step.0)
  for step in steps {
    let (from, caster) = step
    if from >= schema && from < self.schema_version {
      data = caster.run(data) catch {
        err =>
          raise @strata.DecodeError(
            event_type~,
            position=None,
            reason=err.to_string(),
          )
      }
    }
  }
  (event_type, data)
}

///|
/// Decodes a stored event into a domain event: `upgrade`, then `FromJson`.
/// Returns `None` when the type is deprecated or is a Strata system event
/// (`$strata.forgotten`, `$strata.unsealed`, ...).
pub fn[E : @json.FromJson] JsonCodec::decode(
  self : JsonCodec,
  stored : @strata.StoredEvent,
) -> @strata.Recorded[E]? raise @strata.DecodeError {
  if @strata.is_system_event_type(stored.event_type) {
    return None
  }
  let (event_type, data) = self.upgrade(
    event_type=stored.event_type,
    schema=stored.schema,
    stored.data,
  )
  ignore(self.redacted_as)
  if self.is_deprecated(event_type) {
    return None
  }
  let event : E = @json.from_json(data) catch {
    @json.JsonDecodeError((_, reason)) =>
      raise @strata.DecodeError(
        event_type~,
        position=Some(stored.position),
        reason~,
      )
  }
  let upgraded = @strata.StoredEvent(
    id=stored.id,
    position=stored.position,
    stream=stored.stream,
    version=stored.version,
    event_type~,
    schema=self.schema_version,
    data~,
    tags=stored.tags,
    meta=stored.meta,
    recorded_at=stored.recorded_at,
  )
  Some(@strata.Recorded::from_stored(upgraded, event))
}

///|
/// Decodes several stored events, skipping deprecated ones.
pub fn[E : @json.FromJson] JsonCodec::decode_all(
  self : JsonCodec,
  stored : Array[@strata.StoredEvent],
) -> Array[@strata.Recorded[E]] raise @strata.DecodeError {
  let out : Array[@strata.Recorded[E]] = []
  for s in stored {
    match self.decode(s) {
      Some(r) => out.push(r)
      None => ()
    }
  }
  out
}
