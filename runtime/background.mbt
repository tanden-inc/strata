///|
/// An async read model: a subscription with a checkpoint, writing rows to a
/// view table. At-least-once delivery becomes effectively-once because the
/// view and its checkpoint are committed together.
pub struct Projector {
  priv runtime : Runtime
  priv name : String
  priv selection : @strata.Selection
  priv table : Ref[String]
  priv step : async (@strata.StoredEvent) -> Unit
  priv position : Ref[@strata.Position]
  priv on_forgotten : Array[(String) -> Unit]
}

///|
/// A projector for a multi-source view stored as one row (`key = "view"`).
pub fn[V : ToJson + @json.FromJson] Runtime::projector(
  self : Runtime,
  name : String,
  projection : @strata.MultiProjection[V],
  into~ : String,
) -> Projector {
  let runtime = self
  let table : Ref[String] = { val: into, }
  let position : Ref[@strata.Position] = { val: @strata.start, }
  let forgotten : Array[(String) -> Unit] = []
  async fn step(stored : @strata.StoredEvent) {
    if stored.event_type == "$strata.forgotten" {
      for f in forgotten {
        f(stored.stream.entity_id())
      }
    }
    let writes : Array[@store.ViewWrite] = []
    if is_system_event_type(stored.event_type) == false &&
      runtime.codec.is_deprecated(stored.event_type) == false {
      let (event_type, data) = runtime.codec.upgrade(
        event_type=stored.event_type,
        schema=stored.schema,
        stored.data,
      )
      if runtime.codec.is_deprecated(event_type) == false {
        let upgraded = @strata.StoredEvent(
          id=stored.id,
          position=stored.position,
          stream=stored.stream,
          version=stored.version,
          event_type~,
          schema=runtime.codec.schema_version(),
          data~,
          tags=stored.tags,
          meta=stored.meta,
          recorded_at=stored.recorded_at,
        )
        let dest = table.val
        let current = @store.ViewStore::get(
          @store.EventStore::views(runtime.store),
          table=dest,
          key="view",
        )
        let view : V = match current {
          None => projection.initial()
          Some(json) =>
            json_of(json, event_type~, position=Some(stored.position))
        }
        let next = projection.apply_stored(view, upgraded)
        writes.push(
          @store.ViewWrite(table=dest, key="view", value=Some(Json(next))),
        )
      }
    }
    @store.ViewStore::commit(
      @store.EventStore::views(runtime.store),
      writes~,
      checkpoint=@store.Checkpoint(name~, position=stored.position),
    )
    position.val = stored.position
  }

  {
    runtime: self,
    name,
    selection: projection.selection(),
    table,
    position,
    on_forgotten: forgotten,
    step,
  }
}

///|
/// A projector for a keyed view stored as one row per key.
pub fn[E : @json.FromJson, K : Show + Eq + Hash, R : ToJson + @json.FromJson] Runtime::projector_keyed(
  self : Runtime,
  name : String,
  projection : @strata.KeyedProjection[E, K, R],
  source~ : @strata.Selection,
  into~ : String,
) -> Projector {
  let runtime = self
  let table : Ref[String] = { val: into, }
  let position : Ref[@strata.Position] = { val: @strata.start, }
  let forgotten : Array[(String) -> Unit] = []
  let _rows : Map[K, R] = Map([])
  async fn step(stored : @strata.StoredEvent) {
    if stored.event_type == "$strata.forgotten" {
      for f in forgotten {
        f(stored.stream.entity_id())
      }
    }
    match runtime.codec.decode(stored) {
      Some(recorded) => {
        let dest = table.val
        let views = @store.EventStore::views(runtime.store)
        let writes : Array[@store.ViewWrite] = []
        for key in projection.keys_of(recorded) {
          let row_key = Show::to_string(key)
          let current = @store.ViewStore::get(views, table=dest, key=row_key)
          let row : R = match current {
            None => projection.initial()
            Some(json) =>
              json_of(
                json,
                event_type=stored.event_type,
                position=Some(stored.position),
              )
          }
          let next = projection.apply(key, row, recorded)
          writes.push(
            @store.ViewWrite(table=dest, key=row_key, value=Some(Json(next))),
          )
        }
        @store.ViewStore::commit(
          views,
          writes~,
          checkpoint=@store.Checkpoint(name~, position=stored.position),
        )
      }
      None =>
        @store.ViewStore::commit(
          @store.EventStore::views(runtime.store),
          writes=[],
          checkpoint=@store.Checkpoint(name~, position=stored.position),
        )
    }
    position.val = stored.position
  }

  {
    runtime: self,
    name,
    selection: source,
    table,
    position,
    on_forgotten: forgotten,
    step,
  }
}

///|
/// The projector's name (also its checkpoint key).
pub fn Projector::name(self : Projector) -> String {
  self.name
}

///|
/// The last position applied.
pub fn Projector::position(self : Projector) -> @strata.Position {
  self.position.val
}

///|
/// Starts the projector as a background task of `group`; it stops when the
/// group is cancelled.
pub fn[X] Projector::start(
  self : Projector,
  group : @async.TaskGroup[X],
) -> Unit {
  group.spawn_bg(() => Projector::run(self))
}

///|
/// Runs the projector loop in the current task until cancelled.
pub async fn Projector::run(self : Projector) -> Unit {
  Projector::catch_up(self)
  let sub = @store.EventStore::subscribe(
    self.runtime.store,
    self.selection,
    from=self.position.val,
  )
  try {
    while true {
      let batch = @store.Subscription::next(sub)
      for event in batch {
        (self.step)(event)
      }
    }
  } catch {
    err => if @async.is_cancellation_error(err) { () } else { raise err }
  }
}

///|
/// Applies everything currently in the log and returns (no subscription).
pub async fn Projector::catch_up(self : Projector) -> Unit {
  match @store.EventStore::load_checkpoint(self.runtime.store, self.name) {
    Some(p) => if p.0 > self.position.val.0 { self.position.val = p }
    None => ()
  }
  let events = read_all(self.runtime.store, self.selection, self.position.val)
  for event in events {
    (self.step)(event)
  }
}

///|
/// Blocks until the projector has applied `position`, or raises `WaitTimeout`.
pub async fn Projector::wait_for(
  self : Projector,
  position : @strata.Position,
  timeout~ : @strata.Duration,
) -> Unit {
  @async.with_timeout(timeout.to_millis().to_int(), () => {
    while self.position.val.0 < position.0 {
      @async.sleep(1)
    }
  }) catch {
    @async.TimeoutError =>
      raise WaitTimeout(waiting_for=position, reached=self.position.val)
    err => raise err
  }
}

///|
/// Replays into a fresh table and swaps it in.
pub async fn Projector::rebuild(self : Projector) -> Unit {
  let dest = self.table.val
  let tmp = dest + "~rebuild"
  self.table.val = tmp
  self.position.val = @strata.start
  @store.EventStore::save_checkpoint(
    self.runtime.store,
    self.name,
    @strata.start,
  )
  Projector::catch_up(self)
  @store.ViewStore::swap(
    @store.EventStore::views(self.runtime.store),
    from=tmp,
    to=dest,
  )
  self.table.val = dest
}

///|
/// Called with the entity id when a stream is forgotten; drop derived copies.
pub fn Projector::on_forgotten(self : Projector, f : (String) -> Unit) -> Unit {
  self.on_forgotten.push(f)
}

///|
/// A reactor: react to an event, issue commands. Subscribes to a selection,
/// checkpoints its position, and is redelivery-safe when downstream commands
/// use `r.caused()` for their context.
pub struct Reactor {
  priv runtime : Runtime
  priv name : String
  priv source : @strata.Selection
  priv step : async (@strata.StoredEvent) -> Unit
  priv retry : @async.RetryMethod
  priv max_retry : Int
  priv on_failure : (async (@strata.StoredEvent, Error) -> Unit)?
  priv position : Ref[@strata.Position]
}

///|
/// Builds a reactor over `source`. `handler` receives each decoded event.
///
/// A failing handler is retried according to `retry`, at most `max_retry`
/// times. When the retries are exhausted, the event is handed to
/// `on_failure` (a dead-letter hook) and the reactor moves on; without
/// `on_failure` the reactor raises and stops so the failure is visible.
pub fn[E : @json.FromJson] Runtime::reactor(
  self : Runtime,
  name : String,
  source~ : @strata.Selection,
  retry? : @async.RetryMethod = FixedDelay(100),
  max_retry? : Int = 5,
  on_failure? : async (@strata.StoredEvent, Error) -> Unit,
  handler : async (@strata.Recorded[E]) -> Unit,
) -> Reactor {
  let runtime = self
  let position : Ref[@strata.Position] = { val: @strata.start, }
  let failure = on_failure
  async fn step(stored : @strata.StoredEvent) {
    match runtime.codec.decode(stored) {
      Some(recorded) =>
        @async.retry(
          retry,
          max_retry~,
          fatal_error=@async.is_cancellation_error,
          () => handler(recorded),
        ) catch {
          err => {
            if @async.is_cancellation_error(err) {
              raise err
            }
            match failure {
              Some(hook) => hook(stored, err)
              None => raise err
            }
          }
        }
      None => ()
    }
    @store.ViewStore::commit(
      @store.EventStore::views(runtime.store),
      writes=[],
      checkpoint=@store.Checkpoint(name~, position=stored.position),
    )
    position.val = stored.position
  }

  { runtime: self, name, source, retry, max_retry, on_failure, position, step, }
}

///|
/// The reactor's name (also its checkpoint key).
pub fn Reactor::name(self : Reactor) -> String {
  self.name
}

///|
/// The last position handled.
pub fn Reactor::position(self : Reactor) -> @strata.Position {
  self.position.val
}

///|
/// Starts the reactor as a background task of `group`.
pub fn[X] Reactor::start(self : Reactor, group : @async.TaskGroup[X]) -> Unit {
  group.spawn_bg(() => Reactor::run(self))
}

///|
/// Runs the reactor loop in the current task until cancelled.
pub async fn Reactor::run(self : Reactor) -> Unit {
  Reactor::catch_up(self)
  let sub = @store.EventStore::subscribe(
    self.runtime.store,
    self.source,
    from=self.position.val,
  )
  try {
    while true {
      let batch = @store.Subscription::next(sub)
      for event in batch {
        (self.step)(event)
      }
    }
  } catch {
    err => if @async.is_cancellation_error(err) { () } else { raise err }
  }
}

///|
/// Handles everything currently in the log and returns (no subscription).
pub async fn Reactor::catch_up(self : Reactor) -> Unit {
  ignore(self.retry)
  ignore(self.max_retry)
  ignore(self.on_failure)
  match @store.EventStore::load_checkpoint(self.runtime.store, self.name) {
    Some(p) => if p.0 > self.position.val.0 { self.position.val = p }
    None => ()
  }
  let events = read_all(self.runtime.store, self.source, self.position.val)
  for event in events {
    (self.step)(event)
  }
}
