///|
test "stream ids are category-id, optionally prefixed by tenant" {
  let s = @core.StreamId::of(category="account", id="acc-1")
  inspect(s, content="account-acc-1")
  inspect(s.category(), content="account")
  inspect(s.entity_id(), content="acc-1")
  debug_inspect(s.tenant(), content="None")
  let t = @core.StreamId::of(category="account", id="acc-1", tenant="t1")
  inspect(t, content="t1/account-acc-1")
  debug_inspect(t.tenant(), content="Some(\"t1\")")
  inspect(t.entity_id(), content="acc-1")
}

///|
test "stream ids parse and round-trip, ids may contain dashes" {
  let s = @core.StreamId::parse("ledger-ORG-CORE01")
  inspect(s.category(), content="ledger")
  inspect(s.entity_id(), content="ORG-CORE01")
  let t = @core.StreamId::parse("t1/account-acc-1")
  debug_inspect(t.tenant(), content="Some(\"t1\")")
  assert_eq(t, @core.StreamId::of(category="account", id="acc-1", tenant="t1"))
  let bad = try {
    @core.StreamId::parse("nodash") |> ignore
    false
  } catch {
    @core.InvalidStreamId(_) => true
  }
  assert_true(bad)
}

///|
test "ulids encode the timestamp and increment monotonically" {
  let at = @core.Instant(1_757_721_600_000L)
  let random = b"\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a"
  let id = @core.EventId::ulid(timestamp=at, random~)
  inspect(id.0.length(), content="26")
  assert_true(id.is_ulid())
  debug_inspect(id.timestamp(), content="Some(Instant(1757721600000))")
  let next = id.increment()
  assert_true(next > id)
  debug_inspect(next.timestamp(), content="Some(Instant(1757721600000))")
  assert_false(@core.EventId("evt-0001").is_ulid())
  debug_inspect(@core.EventId("evt-0001").timestamp(), content="None")
}

///|
test "deterministic id batches count from one" {
  let ids = @core.IdBatch::deterministic()
  inspect(ids.at(0), content="evt-0001")
  inspect(ids.at(1), content="evt-0002")
  inspect(@core.IdBatch::deterministic(prefix="cmd-").at(9), content="cmd-0010")
}

///|
test "ulid batches increment from the base" {
  let base = @core.EventId::ulid(
    timestamp=@core.Instant(0),
    random=b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
  )
  let ids = @core.IdBatch::from(base)
  assert_eq(ids.at(0), base)
  assert_eq(ids.at(2), base.increment().increment())
}

///|
test "tags split on the first colon and know system tags" {
  let t = @core.Tag::kv(key="code", value="X:Y")
  inspect(t, content="code:X:Y")
  inspect(t.key(), content="code")
  debug_inspect(t.value(), content="Some(\"X:Y\")")
  debug_inspect(@core.Tag("plain").value(), content="None")
  assert_false(t.is_system())
  assert_true(@core.Tag("$stream:account-acc-1").is_system())
}

///|
test "identifier newtypes serialise as plain JSON scalars" {
  json_inspect(@core.EventId("evt-0001"), content="evt-0001")
  json_inspect(@core.StreamId("account-acc-1"), content="account-acc-1")
  json_inspect(@core.Position(41), content=41)
  json_inspect(@core.Actor("user:alice"), content="user:alice")
  json_inspect(@core.Tag("code:X"), content="code:X")
  json_inspect(@core.Duration::seconds(2), content=2000)
  let back : @core.Position = @json.from_json(41)
  assert_eq(back, @core.Position(41))
}
