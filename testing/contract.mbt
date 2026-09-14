///|
fn contract_event(
  id : String,
  tags? : Array[@strata.Tag] = [],
  event_type? : String = "Ev",
  key? : String,
) -> @strata.NewEvent raise {
  let meta = match key {
    Some(key) => @strata.Metadata(idempotency_key=key)
    None => @strata.Metadata()
  }
  @strata.NewEvent(
    id=@strata.EventId(id),
    event_type~,
    schema=1,
    data=Json::string(event_type),
    tags~,
    meta~,
  )
}

///|
/// The `EventStore` contract suite. `make` must return a fresh, empty store;
/// it is called once per case. Covers: append semantics and versions;
/// `Any`/`NoStream`/`Exact`; DCB conditions; selection semantics including
/// system tags; ordering of `read`; idempotency lookup; subscriptions;
/// checkpoints; snapshots; inline view writes; rejection of user `$` tags.
#callsite(autofill(loc))
pub async fn[St : @store.EventStore] contract(
  make~ : async () -> St,
  loc~ : SourceLoc,
) -> Unit {
  let at = @strata.Instant(0)
  let stream = @strata.StreamId::of(category="account", id="a")
  let other = @strata.StreamId::of(category="account", id="b")
  let code = @strata.Tag("code:X")

  // append assigns positions and versions
  {
    let store = make()
    let r = store.append(
      stream~,
      condition=Stream(stream, NoStream),
      events=[contract_event("e1"), contract_event("e2")],
      recorded_at=at,
    )
    assert_eq(r.version, 2, loc~)
    assert_eq(r.events[0].version, 1, loc~)
    assert_eq(r.events[1].version, 2, loc~)
    assert_eq(r.events[0].position, @strata.Position(1), loc~)
    assert_eq(r.events[1].position, @strata.Position(2), loc~)
    assert_eq(r.position, @strata.Position(2), loc~)
    assert_eq(store.head(), @strata.Position(2), loc~)
  }

  // expected NoStream rejects existing stream
  {
    let store = make()
    store.append(
      stream~,
      condition=Stream(stream, NoStream),
      events=[contract_event("e1")],
      recorded_at=at,
    )
    |> ignore
    let conflict = try {
      store.append(
        stream~,
        condition=Stream(stream, NoStream),
        events=[contract_event("e2")],
        recorded_at=at,
      )
      |> ignore
      false
    } catch {
      @strata.StreamConflict(expected=NoStream, ..) => true
      err => raise err
    }
    assert_true(conflict, loc~)
  }

  // expected Exact rejects stale version
  {
    let store = make()
    store.append(
      stream~,
      condition=Stream(stream, Any),
      events=[contract_event("e1")],
      recorded_at=at,
    )
    |> ignore
    let conflict = try {
      store.append(
        stream~,
        condition=Stream(stream, Exact(0)),
        events=[contract_event("e2")],
        recorded_at=at,
      )
      |> ignore
      false
    } catch {
      @strata.StreamConflict(expected=Exact(0), actual=1, ..) => true
      err => raise err
    }
    assert_true(conflict, loc~)
  }

  // expected Any always appends
  {
    let store = make()
    store.append(
      stream~,
      condition=Stream(stream, Any),
      events=[contract_event("e1")],
      recorded_at=at,
    )
    |> ignore
    let r = store.append(
      stream~,
      condition=Stream(stream, Any),
      events=[contract_event("e2")],
      recorded_at=at,
    )
    assert_eq(r.version, 2, loc~)
  }

  // dcb condition rejects events after `after`
  {
    let store = make()
    let selection = @strata.Selection::tags([code])
    store.append(
      stream~,
      condition=Stream(stream, Any),
      events=[contract_event("e1", tags=[code])],
      recorded_at=at,
    )
    |> ignore
    let conflict = try {
      store.append(
        stream=other,
        condition=Dcb(selection~, after=Some(@strata.Position(0))),
        events=[contract_event("e2", tags=[code])],
        recorded_at=at,
      )
      |> ignore
      false
    } catch {
      @strata.BoundaryConflict(at=@strata.Position(1), ..) => true
      err => raise err
    }
    assert_true(conflict, loc~)
  }

  // dcb condition with after=None requires empty scope
  {
    let store = make()
    let selection = @strata.Selection::tags([code])
    store.append(
      stream~,
      condition=Stream(stream, Any),
      events=[contract_event("e1", tags=[code])],
      recorded_at=at,
    )
    |> ignore
    let conflict = try {
      store.append(
        stream=other,
        condition=Dcb(selection~, after=None),
        events=[contract_event("e2", tags=[code])],
        recorded_at=at,
      )
      |> ignore
      false
    } catch {
      @strata.BoundaryConflict(after=None, ..) => true
      err => raise err
    }
    assert_true(conflict, loc~)
  }

  // read returns global order strictly after position
  {
    let store = make()
    store.append(
      stream~,
      condition=Stream(stream, Any),
      events=[contract_event("e1"), contract_event("e2")],
      recorded_at=at,
    )
    |> ignore
    store.append(
      stream=other,
      condition=Stream(other, Any),
      events=[contract_event("e3")],
      recorded_at=at,
    )
    |> ignore
    let page = store.read(@strata.Selection::all(), after=@strata.Position(1))
    assert_eq(page.map(e => e.id.0), ["e2", "e3"], loc~)
  }

  // read_stream returns one stream from version
  {
    let store = make()
    store.append(
      stream~,
      condition=Stream(stream, Any),
      events=[contract_event("e1"), contract_event("e2")],
      recorded_at=at,
    )
    |> ignore
    store.append(
      stream=other,
      condition=Stream(other, Any),
      events=[contract_event("e3")],
      recorded_at=at,
    )
    |> ignore
    let page = store.read_stream(stream, from_version=2)
    assert_eq(page.map(e => e.id.0), ["e2"], loc~)
  }

  // stream and category selections use system tags
  {
    let store = make()
    store.append(
      stream~,
      condition=Stream(stream, Any),
      events=[contract_event("e1")],
      recorded_at=at,
    )
    |> ignore
    let by_stream = store.read(@strata.Selection::stream(stream))
    assert_eq(by_stream.length(), 1, loc~)
    let by_cat = store.read(@strata.Selection::category("account"))
    assert_eq(by_cat.length(), 1, loc~)
    assert_true(
      by_stream[0].tags.contains(@strata.Tag("$stream:account-a")),
      loc~,
    )
    assert_true(
      by_stream[0].tags.contains(@strata.Tag("$category:account")),
      loc~,
    )
  }

  // user tags cannot start with $
  {
    let rejected = try {
      contract_event("e1", tags=[@strata.Tag("$stream:x")]) |> ignore
      false
    } catch {
      @strata.InvalidTag(_) => true
      err => raise err
    }
    assert_true(rejected, loc~)
  }

  // find_idempotent returns the original batch
  {
    let store = make()
    store.append(
      stream~,
      condition=Stream(stream, Any),
      events=[
        contract_event("e1", key="req-1"),
        contract_event("e2", key="req-1"),
      ],
      recorded_at=at,
    )
    |> ignore
    let found = store.find_idempotent(key="req-1")
    assert_eq(found.map(e => e.id.0), ["e1", "e2"], loc~)
    let scoped = store.find_idempotent(key="req-1", stream=other)
    assert_eq(scoped.length(), 0, loc~)
  }

  // subscribe delivers appended events in order
  {
    let store = make()
    store.append(
      stream~,
      condition=Stream(stream, Any),
      events=[contract_event("e1")],
      recorded_at=at,
    )
    |> ignore
    let sub = store.subscribe(@strata.Selection::all(), from=@strata.start)
    let first = sub.next(timeout=@strata.Duration::seconds(1))
    assert_eq(first.map(e => e.id.0), ["e1"], loc~)
    store.append(
      stream~,
      condition=Stream(stream, Any),
      events=[contract_event("e2")],
      recorded_at=at,
    )
    |> ignore
    let second = sub.next(timeout=@strata.Duration::seconds(1))
    assert_eq(second.map(e => e.id.0), ["e2"], loc~)
    sub.close()
  }

  // checkpoints round-trip
  {
    let store = make()
    assert_eq(store.load_checkpoint("proj"), None, loc~)
    store.save_checkpoint("proj", @strata.Position(7))
    assert_eq(store.load_checkpoint("proj"), Some(@strata.Position(7)), loc~)
  }

  // snapshots round-trip and are keyed by selection
  {
    let store = make()
    let sel = @strata.Selection::tags([code])
    let record = @store.SnapshotRecord(
      position=@strata.Position(3),
      version=1,
      state=Json::number(1.0),
    )
    store.save_snapshot(@store.SnapshotKey::Dcb(sel, version=1), record)
    let loaded = store.load_snapshot(@store.SnapshotKey::Dcb(sel, version=1))
    assert_eq(loaded, Some(record), loc~)
    let missing = store.load_snapshot(
      @store.SnapshotKey::Dcb(@strata.Selection::all(), version=1),
    )
    assert_eq(missing, None, loc~)
  }

  // inline view writes are atomic with the append
  let store = make()
  store.append(
    stream~,
    condition=Stream(stream, Any),
    events=[contract_event("e1")],
    recorded_at=at,
    inline=[
      @store.ViewWrite(
        table="balances",
        key="a",
        value=Some(Json::number(42.0)),
      ),
    ],
  )
  |> ignore
  assert_eq(
    store.views().get(table="balances", key="a"),
    Some(Json::number(42.0)),
    loc~,
  )

  // a failed append leaves inline views untouched
  {
    let store = make()
    let conflicted = try {
      store.append(
        stream~,
        condition=Stream(stream, Exact(5)),
        events=[contract_event("e1")],
        recorded_at=at,
        inline=[
          @store.ViewWrite(
            table="balances",
            key="a",
            value=Some(Json::number(1.0)),
          ),
        ],
      )
      |> ignore
      false
    } catch {
      @strata.StreamConflict(..) => true
      e => raise e
    }
    assert_true(conflicted, loc~)
    assert_eq(store.views().get(table="balances", key="a"), None, loc~)
    assert_eq(store.head(), @strata.start, loc~)
  }

  // commit applies rows and checkpoint together
  {
    let store = make()
    store
    .views()
    .commit(
      writes=[
        @store.ViewWrite(table="t", key="k1", value=Some(Json::number(1.0))),
        @store.ViewWrite(table="t", key="k2", value=Some(Json::number(2.0))),
      ],
      checkpoint=@store.Checkpoint(name="p", position=@strata.Position(7)),
    )
    assert_eq(
      store.views().get(table="t", key="k1"),
      Some(Json::number(1.0)),
      loc~,
    )
    assert_eq(
      store.views().get(table="t", key="k2"),
      Some(Json::number(2.0)),
      loc~,
    )
    assert_eq(store.load_checkpoint("p"), Some(@strata.Position(7)), loc~)
    store
    .views()
    .commit(writes=[@store.ViewWrite(table="t", key="k1", value=None)])
    assert_eq(store.views().get(table="t", key="k1"), None, loc~)
    assert_eq(store.load_checkpoint("p"), Some(@strata.Position(7)), loc~)
  }

  // read honours limit and pages by position
  {
    let store = make()
    store.append(
      stream~,
      condition=Stream(stream, Any),
      events=[contract_event("e1"), contract_event("e2"), contract_event("e3")],
      recorded_at=at,
    )
    |> ignore
    let first = store.read(@strata.Selection::stream(stream), limit=2)
    assert_eq(first.length(), 2, loc~)
    let rest = store.read(
      @strata.Selection::stream(stream),
      after=first[1].position,
      limit=2,
    )
    assert_eq(rest.map(e => e.id.0), ["e3"], loc~)
  }

  // category selections are tenant-aware
  {
    let store = make()
    let t1 = @strata.StreamId::of(category="account", id="a", tenant="t1")
    let t2 = @strata.StreamId::of(category="account", id="a", tenant="t2")
    store.append(
      stream=t1,
      condition=Stream(t1, Any),
      events=[contract_event("e1")],
      recorded_at=at,
    )
    |> ignore
    store.append(
      stream=t2,
      condition=Stream(t2, Any),
      events=[contract_event("e2")],
      recorded_at=at,
    )
    |> ignore
    assert_eq(
      store.read(@strata.Selection::category("account")).length(),
      2,
      loc~,
    )
    assert_eq(
      store
      .read(@strata.Selection::category("account", tenant="t1"))
      .map(e => e.id.0),
      ["e1"],
      loc~,
    )
    assert_eq(store.read(@strata.Selection::none()).length(), 0, loc~)
  }

  // types selections match the stored event type
  {
    let store = make()
    store.append(
      stream~,
      condition=Stream(stream, Any),
      events=[contract_event("e1")],
      recorded_at=at,
    )
    |> ignore
    assert_eq(store.read(@strata.Selection::types(["Ev"])).length(), 1, loc~)
    assert_eq(store.read(@strata.Selection::types(["Other"])).length(), 0, loc~)
  }

  // subscription next times out with an empty batch
  let store = make()
  let sub = store.subscribe(@strata.Selection::all(), from=@strata.start)
  assert_eq(sub.next(timeout=@strata.Duration::millis(20)).length(), 0, loc~)
  sub.close()
}

///|
/// The names of the contract cases, in the order `contract` runs them.
pub fn contract_cases() -> Array[String] {
  [
    "append assigns positions and versions", "expected NoStream rejects existing stream",
    "expected Exact rejects stale version", "expected Any always appends", "dcb condition rejects events after `after`",
    "dcb condition with after=None requires empty scope", "read returns global order strictly after position",
    "read_stream returns one stream from version", "stream and category selections use system tags",
    "user tags cannot start with $", "find_idempotent returns the original batch",
    "subscribe delivers appended events in order", "checkpoints round-trip", "snapshots round-trip and are keyed by selection",
    "inline view writes are atomic with the append", "a failed append leaves inline views untouched",
    "commit applies rows and checkpoint together", "read honours limit and pages by position",
    "category selections are tenant-aware", "types selections match the stored event type",
    "subscription next times out with an empty batch",
  ]
}
