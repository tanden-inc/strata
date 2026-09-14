///|
let alice : @core.Actor = @core.Actor("user:alice")

///|
test "context flags" {
  let ctx = @core.Context(actor=alice)
  assert_false(ctx.flag("anonymous"))
  assert_true(ctx.with_flag("anonymous").flag("anonymous"))
  debug_inspect(
    ctx.with_idempotency_key("req-1").idempotency_key,
    content="Some(\"req-1\")",
  )
}

///|
test "context becomes metadata" {
  let ctx = @core.Context(
    actor=alice,
    tenant="t1",
    correlation_id="corr-1",
    idempotency_key="req-1",
  )
  ctx.to_metadata()
  |> debug_inspect(
    content=(
      #|{
      #|  correlation_id: Some("corr-1"),
      #|  causation_id: None,
      #|  actor: Some(Actor("user:alice")),
      #|  tenant: Some("t1"),
      #|  idempotency_key: Some("req-1"),
      #|  extra: Null,
      #|}
    ),
  )
}

///|
test "new events reject system tags" {
  let meta = @core.Metadata()
  let ok = @core.NewEvent(
    id=@core.EventId("e1"),
    event_type="Opened",
    schema=1,
    data="Opened",
    tags=[@core.Tag("code:X")],
    meta~,
  )
  inspect(ok.event_type, content="Opened")
  let rejected = try {
    @core.NewEvent(
      id=@core.EventId("e2"),
      event_type="Opened",
      schema=1,
      data="Opened",
      tags=[@core.Tag("$stream:x")],
      meta~,
    )
    |> ignore
    false
  } catch {
    @core.InvalidTag(_) => true
  }
  assert_true(rejected)
}

///|
test "recorded events derive their context for downstream commands" {
  let stored = @core.StoredEvent(
    id=@core.EventId("evt-0007"),
    position=@core.Position(41),
    stream=@core.StreamId("transfer-t-1"),
    version=1,
    event_type="Requested",
    schema=1,
    data="Requested",
    tags=[
      @core.Tag("$stream:transfer-t-1"),
      @core.Tag("$category:transfer"),
      @core.Tag("code:X"),
    ],
    meta=@core.Metadata(correlation_id="corr-9", actor=alice),
    recorded_at=@core.Instant(0),
  )
  debug_inspect(stored.user_tags(), content="[Tag(\"code:X\")]")
  let r = @core.Recorded::from_stored(stored, "Requested")
  debug_inspect(r.tags, content="[Tag(\"code:X\")]")
  inspect(r.entity_id(), content="t-1")
  let ctx = r.caused()
  debug_inspect(ctx.correlation_id, content="Some(\"corr-9\")")
  debug_inspect(ctx.causation_id, content="Some(EventId(\"evt-0007\"))")
  debug_inspect(ctx.idempotency_key, content="Some(\"evt-0007\")")
  inspect(ctx.actor, content="user:alice")
  inspect(r.caused(actor=@core.Actor("svc:pm")).actor, content="svc:pm")
}
