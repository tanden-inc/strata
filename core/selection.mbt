///|
/// One item of a `Selection`: events whose type is in `types` (empty means
/// any type) *and* that carry every tag in `tags`.
pub struct SelectionItem {
  types : Array[String]
  tags : Array[Tag]
} derive(Eq, Hash, Debug, ToJson, FromJson)

///|
fn[T : Compare + Eq] sorted_unique(values : Array[T]) -> Array[T] {
  let xs = values.copy()
  xs.sort()
  xs.dedup()
  xs
}

///|
fn item_cmp(a : SelectionItem, b : SelectionItem) -> Int {
  let types = a.types.compare(b.types)
  if types != 0 {
    types
  } else {
    a.tags.compare(b.tags)
  }
}

///|
fn normalize_items(items : Array[SelectionItem]) -> Array[SelectionItem] {
  let xs = items.copy()
  xs.sort_by(item_cmp)
  xs.dedup()
  xs
}

///|
/// Builds an item; both lists are sorted and de-duplicated.
pub fn SelectionItem::SelectionItem(
  types? : Array[String] = [],
  tags? : Array[Tag] = [],
) -> SelectionItem {
  { types: sorted_unique(types), tags: sorted_unique(tags), }
}

///|
/// Names a set of events, following the Dynamic Consistency Boundaries
/// specification: a list of items OR-ed together, where each item ANDs its
/// event types and tags. An empty item list selects the whole log.
///
/// The same value drives paged reads, folds, subscriptions and the append
/// condition of a DCB write. Constructors normalise their input, so two
/// selections that name the same set are `Eq` and hash alike.
///
/// Streams and categories are expressed with system tags (`$stream:<name>`,
/// `$category:<name>`, `$tenant:<t>`) so that one index serves every read.
pub struct Selection {
  priv items : Array[SelectionItem]
  priv empty : Bool
} derive(Eq, Hash, Debug)

///|
/// The whole log.
pub fn Selection::all() -> Selection {
  { items: [], empty: false, }
}

///|
/// No events at all. `any_of([])` is `none()`, not `all()`.
pub fn Selection::none() -> Selection {
  { items: [], empty: true, }
}

///|
/// Every event of one stream.
pub fn Selection::stream(stream : StreamId) -> Selection {
  Selection::tags([Tag::kv(key="$stream", value=stream.0)])
}

///|
/// Every event of every stream in a category, optionally within one tenant.
pub fn Selection::category(name : String, tenant? : String) -> Selection {
  let tags : Array[Tag] = [Tag::kv(key="$category", value=name)]
  match tenant {
    Some(t) => tags.push(Tag::kv(key="$tenant", value=t))
    None => ()
  }
  Selection::tags(tags)
}

///|
/// Events carrying all of the given tags.
pub fn Selection::tags(tags : Array[Tag]) -> Selection {
  { items: [SelectionItem(tags~)], empty: false, }
}

///|
/// Events whose type is one of `types`, optionally also carrying all of `tags`.
/// Type names are the names the codec derives from the event value
/// (`"Deposited"` for `Deposited(..)`).
pub fn Selection::types(
  types : Array[String],
  tags? : Array[Tag] = [],
) -> Selection {
  { items: [SelectionItem(types~, tags~)], empty: false, }
}

///|
/// The union of several selections (their items are concatenated). The union
/// of nothing is `none()`.
pub fn Selection::any_of(selections : Array[Selection]) -> Selection {
  if selections.any(s => s.is_all()) {
    return Selection::all()
  }
  let items : Array[SelectionItem] = []
  for sel in selections {
    if sel.empty {
      continue
    }
    items.append(sel.items[:])
  }
  let items = normalize_items(items)
  if items.is_empty() {
    return Selection::none()
  }
  { items, empty: false, }
}

///|
/// The normalised items.
pub fn Selection::items(self : Selection) -> Array[SelectionItem] {
  self.items
}

///|
/// Whether this selection is the whole log.
pub fn Selection::is_all(self : Selection) -> Bool {
  self.empty == false && self.items.is_empty()
}

///|
/// The stream when this selection is exactly one stream (the fast path for
/// stores), otherwise `None`.
pub fn Selection::single_stream(self : Selection) -> StreamId? {
  match self.items {
    [item] =>
      if item.types.is_empty() && item.tags.length() == 1 {
        let tag = item.tags[0]
        if tag.key() == "$stream" {
          match tag.value() {
            Some(name) => Some(StreamId(name))
            None => None
          }
        } else {
          None
        }
      } else {
        None
      }
    _ => None
  }
}

///|
fn item_matches(
  item : SelectionItem,
  event_type : String,
  tags : Array[Tag],
) -> Bool {
  (item.types.is_empty() || item.types.contains(event_type)) &&
  item.tags.all(t => tags.contains(t))
}

///|
/// Whether an event with this type and these tags (system tags included)
/// belongs to the selection.
pub fn Selection::matches(
  self : Selection,
  event_type~ : String,
  tags~ : Array[Tag],
) -> Bool {
  if self.empty {
    false
  } else {
    self.is_all() ||
    self.items.any(item => item_matches(item, event_type, tags))
  }
}

///|
pub impl ToJson for Selection with fn to_json(self) {
  let obj : Map[String, Json] = Map([
    ("items", Json::array(self.items.map(item => Json(item)))),
  ])
  if self.empty {
    obj["empty"] = Json::boolean(true)
  }
  Json::object(obj)
}

///|
pub impl @json.FromJson for Selection with fn from_json(json, path) {
  guard json is Object(obj) else {
    raise @json.JsonDecodeError((path, "Selection: expected an object"))
  }
  let empty = match obj.get("empty") {
    Some(True) => true
    Some(False) | None => false
    Some(_) =>
      raise @json.JsonDecodeError((path, "Selection: empty must be a boolean"))
  }
  let items : Array[SelectionItem] = match obj.get("items") {
    None => []
    Some(value) => @json.from_json(value)
  }
  if empty {
    Selection::none()
  } else if items.is_empty() {
    Selection::all()
  } else {
    { items: normalize_items(items), empty: false, }
  }
}

///|
/// The set of events a DCB decision read: the selection its `scope` produced.
///
/// `evolve`, `decide` and `advise` receive the scope so that state updates
/// about tags outside it are simply not made ("the partial world").
pub struct Scope {
  priv selection : Selection
}

///|
/// Wraps a selection as a scope.
pub fn Scope::of(selection : Selection) -> Scope {
  { selection, }
}

///|
/// Whether `tag` is part of the selection that produced these events.
pub fn Scope::owns(self : Scope, tag : Tag) -> Bool {
  self.selection.items.any(item => item.tags.contains(tag))
}

///|
/// The underlying selection.
pub fn Scope::selection(self : Scope) -> Selection {
  self.selection
}
