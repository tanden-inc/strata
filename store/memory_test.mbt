///|
fn new_event(id : String, tags : Array[@strata.Tag]) -> @strata.NewEvent raise {
  @strata.NewEvent(
    id=@strata.EventId(id),
    event_type="Ev",
    schema=1,
    data="Ev",
    tags~,
    meta=@strata.Metadata(idempotency_key=id),
  )
}

///|
async test "the memory store passes the contract" {
  @testing.contract(make=() => @store.MemoryStore())
}

///|
async test "append assigns positions, versions and system tags" {
  let store = @store.MemoryStore()
  let stream = @strata.StreamId::of(category="account", id="a", tenant="t1")
  let r = store.append(
    stream~,
    condition=Stream(stream, NoStream),
    events=[new_event("e1", [@strata.Tag("code:X")]), new_event("e2", [])],
    recorded_at=@strata.Instant(0),
  )
  inspect(r.version, content="2")
  inspect(r.position, content="2")
  debug_inspect(
    r.events[0].tags,
    content=(
      #|[
      #|  Tag("code:X"),
      #|  Tag("$stream:t1/account-a"),
      #|  Tag("$category:account"),
      #|  Tag("$tenant:t1"),
      #|]
    ),
  )
  inspect(store.length(), content="2")
  inspect(store.head(), content="2")
}

///|
async test "expected versions are enforced" {
  let store = @store.MemoryStore()
  let stream = @strata.StreamId("account-a")
  store.append(
    stream~,
    condition=Stream(stream, NoStream),
    events=[new_event("e1", [])],
    recorded_at=@strata.Instant(0),
  )
  |> ignore
  let conflict = try {
    store.append(
      stream~,
      condition=Stream(stream, Exact(0)),
      events=[new_event("e2", [])],
      recorded_at=@strata.Instant(0),
    )
    |> ignore
    None
  } catch {
    @strata.StreamConflict(actual~, ..) => Some(actual)
    e => raise e
  }
  debug_inspect(conflict, content="Some(1)")
}

///|
async test "subscriptions wake up on append" {
  let store = @store.MemoryStore()
  let stream = @strata.StreamId("account-a")
  let seen : Array[String] = []
  @async.with_task_group(g => {
    g.spawn_bg(() => {
      let sub = store.subscribe(
        @strata.Selection::category("account"),
        from=@strata.start,
      )
      let batch = sub.next(timeout=@strata.Duration::seconds(5))
      for e in batch {
        seen.push(e.id.0)
      }
      sub.close()
    })
    @async.sleep(10)
    store.append(
      stream~,
      condition=Stream(stream, Any),
      events=[new_event("e1", [])],
      recorded_at=@strata.Instant(0),
    )
    |> ignore
  })
  debug_inspect(seen, content="[\"e1\"]")
}

///|
async test "inline view writes land in the store's view store" {
  let store = @store.MemoryStore()
  let stream = @strata.StreamId("account-a")
  store.append(
    stream~,
    condition=Stream(stream, Any),
    events=[new_event("e1", [])],
    recorded_at=@strata.Instant(0),
    inline=[@store.ViewWrite(table="balances", key="a", value=Some(42))],
  )
  |> ignore
  debug_inspect(
    store.views().get(table="balances", key="a"),
    content="Some(Number(42))",
  )
}
