///|
/// A store that forgets the append condition: the contract must catch it.
priv struct BrokenStore {
  inner : @store.MemoryStore
}

///|
impl @store.EventStore for BrokenStore with fn append(
  self,
  stream~,
  condition~,
  events~,
  recorded_at~,
  inline?,
) {
  ignore(condition)
  self.inner.append(
    stream~,
    condition=Stream(stream, Any),
    events~,
    recorded_at~,
    inline?,
  )
}

///|
impl @store.EventStore for BrokenStore with fn read(
  self,
  selection,
  after?,
  limit?,
) {
  self.inner.read(selection, after?, limit?)
}

///|
impl @store.EventStore for BrokenStore with fn read_stream(
  self,
  stream,
  from_version?,
) {
  self.inner.read_stream(stream, from_version?)
}

///|
impl @store.EventStore for BrokenStore with fn head(self) {
  self.inner.head()
}

///|
impl @store.EventStore for BrokenStore with fn find_idempotent(
  self,
  key~,
  stream?,
) {
  self.inner.find_idempotent(key~, stream?)
}

///|
impl @store.EventStore for BrokenStore with fn subscribe(self, selection, from~) {
  self.inner.subscribe(selection, from~)
}

///|
impl @store.EventStore for BrokenStore with fn load_checkpoint(self, name) {
  self.inner.load_checkpoint(name)
}

///|
impl @store.EventStore for BrokenStore with fn save_checkpoint(
  self,
  name,
  position,
) {
  self.inner.save_checkpoint(name, position)
}

///|
impl @store.EventStore for BrokenStore with fn load_snapshot(self, key) {
  self.inner.load_snapshot(key)
}

///|
impl @store.EventStore for BrokenStore with fn save_snapshot(self, key, record) {
  self.inner.save_snapshot(key, record)
}

///|
impl @store.EventStore for BrokenStore with fn views(self) {
  self.inner.views()
}

///|
async test "the contract rejects a store that ignores append conditions" {
  let failed = try {
    contract(make=() => { inner: @store.MemoryStore(), })
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}
