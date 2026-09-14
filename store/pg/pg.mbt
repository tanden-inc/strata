///|
/// Read models and checkpoints of a `PgStore`, kept in the same database so
/// `commit` and inline writes share the append's transaction.
pub struct PgViewStore {
  priv url : String
}

///|
pub impl @store.ViewStore for PgViewStore with fn commit(
  self,
  writes~,
  checkpoint?,
) {
  @strata.todo("PgViewStore::commit")
}

///|
pub impl @store.ViewStore for PgViewStore with fn checkpoint(self, name) {
  @strata.todo("PgViewStore::checkpoint")
}

///|
pub impl @store.ViewStore for PgViewStore with fn get(self, table~, key~) {
  @strata.todo("PgViewStore::get")
}

///|
pub impl @store.ViewStore for PgViewStore with fn put(self, table~, key~, value) {
  @strata.todo("PgViewStore::put")
}

///|
pub impl @store.ViewStore for PgViewStore with fn delete(self, table~, key~) {
  @strata.todo("PgViewStore::delete")
}

///|
pub impl @store.ViewStore for PgViewStore with fn keys(self, table~) {
  @strata.todo("PgViewStore::keys")
}

///|
pub impl @store.ViewStore for PgViewStore with fn swap(self, from~, to~) {
  @strata.todo("PgViewStore::swap")
}

///|
/// The PostgreSQL event store.
///
/// Schema (applied by `migrate`): one `events` table (`position bigserial`,
/// `stream_id`, `version`, `type`, `schema`, `data jsonb`, `meta jsonb`,
/// `tags text[]`, `recorded_at`) with a unique `(stream_id, version)` index
/// and a GIN index on `tags`, plus `checkpoints`, `snapshots`, `views` and
/// `keys`. Every `Selection` compiles to one indexed `SELECT`; DCB
/// conditions are checked inside the insert transaction.
pub struct PgStore {
  priv url : String
  priv view_store : PgViewStore
}

///|
/// Connects to a database. `url` is a `postgres://` connection string.
pub async fn PgStore::connect(url : String) -> PgStore {
  @strata.todo("PgStore::connect")
}

///|
/// Creates or upgrades the schema. Idempotent.
pub async fn PgStore::migrate(self : PgStore) -> Unit {
  @strata.todo("PgStore::migrate")
}

///|
/// Closes the connection pool.
pub fn PgStore::close(self : PgStore) -> Unit {
  ignore(self)
}

///|
pub impl @store.EventStore for PgStore with fn append(
  self,
  stream~,
  condition~,
  events~,
  recorded_at~,
  inline?,
) {
  @strata.todo("PgStore::append")
}

///|
pub impl @store.EventStore for PgStore with fn read(
  self,
  selection,
  after?,
  limit?,
) {
  @strata.todo("PgStore::read")
}

///|
pub impl @store.EventStore for PgStore with fn read_stream(
  self,
  stream,
  from_version?,
) {
  @strata.todo("PgStore::read_stream")
}

///|
pub impl @store.EventStore for PgStore with fn head(self) {
  @strata.todo("PgStore::head")
}

///|
pub impl @store.EventStore for PgStore with fn find_idempotent(
  self,
  key~,
  stream?,
) {
  @strata.todo("PgStore::find_idempotent")
}

///|
pub impl @store.EventStore for PgStore with fn subscribe(self, selection, from~) {
  @strata.todo("PgStore::subscribe")
}

///|
pub impl @store.EventStore for PgStore with fn load_checkpoint(self, name) {
  @strata.todo("PgStore::load_checkpoint")
}

///|
pub impl @store.EventStore for PgStore with fn save_checkpoint(
  self,
  name,
  position,
) {
  @strata.todo("PgStore::save_checkpoint")
}

///|
pub impl @store.EventStore for PgStore with fn load_snapshot(self, key) {
  @strata.todo("PgStore::load_snapshot")
}

///|
pub impl @store.EventStore for PgStore with fn save_snapshot(self, key, record) {
  @strata.todo("PgStore::save_snapshot")
}

///|
pub impl @store.EventStore for PgStore with fn views(self) {
  self.view_store as &@store.ViewStore
}
