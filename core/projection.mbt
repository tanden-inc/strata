///|
/// A read model over one event type: a fold `(V, E) -> V`.
pub struct Projection[E, V] {
  priv initial : V
  priv apply : (V, E) -> V
}

///|
/// Builds a projection.
pub fn[E, V] Projection::Projection(
  initial~ : V,
  apply~ : (V, E) -> V,
) -> Projection[E, V] {
  { initial, apply, }
}

///|
/// The view before any event.
pub fn[E, V] Projection::initial(self : Projection[E, V]) -> V {
  self.initial
}

///|
/// Applies one event.
pub fn[E, V] Projection::apply(
  self : Projection[E, V],
  view : V,
  event : E,
) -> V {
  (self.apply)(view, event)
}

///|
/// Folds events over the initial view.
pub fn[E, V] Projection::fold(self : Projection[E, V], events : Iter[E]) -> V {
  let mut view = self.initial
  for event in events {
    view = self.apply(view, event)
  }
  view
}

///|
/// A read model with many rows: `keys` says which rows an event contributes
/// to, `apply` receives the key so each row interprets the event from its own
/// point of view. Rows see the full `Recorded[E]` (`recorded_at`, `meta`, `id`).
pub struct KeyedProjection[E, K, R] {
  priv keys : (Recorded[E]) -> Array[K]
  priv initial : R
  priv apply : (K, R, Recorded[E]) -> R
}

///|
/// Builds a keyed projection.
pub fn[E, K, R] KeyedProjection::KeyedProjection(
  keys~ : (Recorded[E]) -> Array[K],
  initial~ : R,
  apply~ : (K, R, Recorded[E]) -> R,
) -> KeyedProjection[E, K, R] {
  { keys, initial, apply, }
}

///|
/// The row before any event.
pub fn[E, K, R] KeyedProjection::initial(self : KeyedProjection[E, K, R]) -> R {
  self.initial
}

///|
/// The keys an event contributes to.
pub fn[E, K, R] KeyedProjection::keys_of(
  self : KeyedProjection[E, K, R],
  event : Recorded[E],
) -> Array[K] {
  (self.keys)(event)
}

///|
/// Applies one event to one row.
pub fn[E, K, R] KeyedProjection::apply(
  self : KeyedProjection[E, K, R],
  key : K,
  row : R,
  event : Recorded[E],
) -> R {
  (self.apply)(key, row, event)
}

///|
/// Folds events into a map of rows.
pub fn[E, K : Eq + Hash, R] KeyedProjection::fold(
  self : KeyedProjection[E, K, R],
  events : Iter[Recorded[E]],
) -> Map[K, R] {
  let rows : Map[K, R] = Map([])
  for event in events {
    for key in (self.keys)(event) {
      let row = rows.get(key).unwrap_or(self.initial)
      rows[key] = (self.apply)(key, row, event)
    }
  }
  rows
}

///|
/// A read model over several sources, each with its own event type and
/// selection; events are merged in global position order. No wrapper enum.
pub struct MultiProjection[V] {
  priv initial : V
  priv sources : Array[(Selection, (V, StoredEvent) -> V raise DecodeError)]
}

///|
/// Builds a multi-source projection; add sources with `..source(..)`.
pub fn[V] MultiProjection::MultiProjection(initial~ : V) -> MultiProjection[V] {
  { initial, sources: [], }
}

///|
/// Adds a source. The event is decoded with `FromJson` from the stored
/// payload (the codec has already applied upcasts by then).
pub fn[V, E : @json.FromJson] MultiProjection::source(
  self : MultiProjection[V],
  selection : Selection,
  apply : (V, Recorded[E]) -> V,
) -> Unit {
  self.sources.push(
    (
      selection,
      (view, stored) => {
        let event : E = @json.from_json(stored.data) catch {
          @json.JsonDecodeError((_, reason)) =>
            raise DecodeError(
              event_type=stored.event_type,
              position=Some(stored.position),
              reason~,
            )
        }
        apply(view, Recorded::from_stored(stored, event))
      },
    ),
  )
}

///|
/// The view before any event.
pub fn[V] MultiProjection::initial(self : MultiProjection[V]) -> V {
  self.initial
}

///|
/// The selections of all sources.
pub fn[V] MultiProjection::sources(
  self : MultiProjection[V],
) -> Array[Selection] {
  self.sources.map(source => source.0)
}

///|
/// The union of all sources (what a projector subscribes to).
pub fn[V] MultiProjection::selection(self : MultiProjection[V]) -> Selection {
  Selection::any_of(self.sources())
}

///|
/// Applies one stored event to every source whose selection matches it.
pub fn[V] MultiProjection::apply_stored(
  self : MultiProjection[V],
  view : V,
  event : StoredEvent,
) -> V raise DecodeError {
  let mut view = view
  for source in self.sources {
    let (selection, apply) = source
    if selection.matches(event_type=event.event_type, tags=event.tags) {
      view = apply(view, event)
    }
  }
  view
}
