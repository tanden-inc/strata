///|
#warnings("-unused_value")
priv enum Ev {
  Opened(owner~ : String)
  Withdrawn(amount~ : Int, fee~ : Int)
  Closed
} derive(Eq, Debug, ToJson, FromJson)

///|
#warnings("-unused_value")
priv enum LegacyEv {
  Opened(owner~ : String)
  Closed
} derive(Eq, Debug, ToJson(style="legacy"), FromJson(style="legacy"))

///|
fn stored(
  event_type : String,
  schema : Int,
  data : Json,
) -> @strata.StoredEvent {
  @strata.StoredEvent(
    id=@strata.EventId("e1"),
    position=@strata.Position(1),
    stream=@strata.StreamId("account-a"),
    version=1,
    event_type~,
    schema~,
    data~,
    meta=@strata.Metadata(),
    recorded_at=@strata.Instant(0),
  )
}

///|
test "flat style: the type name is the head of the derived array or the bare string" {
  let codec = @codec.JsonCodec()
  let e = codec.encode(Ev::Withdrawn(amount=10, fee=0))
  inspect(e.event_type, content="Withdrawn")
  inspect(e.schema, content="1")
  json_inspect(e.data, content=["Withdrawn", { "amount": 10, "fee": 0 }])
  inspect(codec.encode(Ev::Closed).event_type, content="Closed")
  json_inspect(codec.encode(Ev::Closed).data, content="Closed")
}

///|
test "legacy style: the type name is the $tag field" {
  let codec = @codec.JsonCodec(style=Legacy(tag_key="$tag"))
  let e = codec.encode(LegacyEv::Opened(owner="alice"))
  inspect(e.event_type, content="Opened")
  json_inspect(e.data, content={ "$tag": "Opened", "owner": "alice" })
  inspect(codec.encode(LegacyEv::Closed).event_type, content="Closed")
}

///|
test "type_of rejects shapes without a tag" {
  let codec = @codec.JsonCodec()
  let bad = try {
    codec.type_of({ "amount": 1 }) |> ignore
    false
  } catch {
    @strata.DecodeError(..) => true
  }
  assert_true(bad)
}

///|
test "decode round-trips an encoded event" {
  let codec = @codec.JsonCodec()
  let e = codec.encode(Ev::Opened(owner="alice"))
  let r : @strata.Recorded[Ev]? = codec.decode(
    stored(e.event_type, e.schema, e.data),
  )
  debug_inspect(r.map(x => x.event), content="Some(Opened(owner=\"alice\"))")
}

///|
// #region upgrade
test "upgrade applies the rename, then upcasts in version order" {
  let codec = @codec.JsonCodec(schema_version=3)
  codec
  ..migrate("Withdrawn", from=1, @codec.Upcast::add_field("fee", 0))
  ..migrate(
    "Withdrawn",
    from=2,
    @codec.Upcast::rename_field(from="amt", to="amount"),
  )
  .rename("Debited", to="Withdrawn")
  let (event_type, data) = codec.upgrade(event_type="Debited", schema=1, [
    "Debited",
    { "amt": 10 },
  ])
  inspect(event_type, content="Withdrawn")
  json_inspect(data, content=["Withdrawn", { "fee": 0, "amount": 10 }])
  // hmm: rename_field runs at from=2, after add_field (from=1); amt is renamed then
  let (_, data2) = codec.upgrade(event_type="Debited", schema=2, [
    "Debited",
    { "amt": 10, "fee": 1 },
  ])
  json_inspect(data2, content=["Withdrawn", { "fee": 1, "amount": 10 }])
}
// #endregion upgrade

///|
// #region compose
test "upcasts compose and add_field does not overwrite" {
  let up = @codec.Upcast::add_field("fee", 0).then(
    @codec.Upcast::remove_field("legacy"),
  )
  json_inspect(up.run({ "fee": 5, "legacy": true }), content={ "fee": 5 })
  json_inspect(up.run({}), content={ "fee": 0 })
}
// #endregion compose

///|
test "decode skips deprecated types and reports the position on failure" {
  let codec = @codec.JsonCodec()
  codec.deprecated("LegacyFeeCharged", replaced_by="Withdrawn")
  assert_true(codec.is_deprecated("LegacyFeeCharged"))
  let skipped : @strata.Recorded[Ev]? = codec.decode(
    stored("LegacyFeeCharged", 1, ["LegacyFeeCharged", { "fee": 1 }]),
  )
  debug_inspect(skipped, content="None")
  let failed = try {
    let _ : @strata.Recorded[Ev]? = codec.decode(
      stored("Withdrawn", 1, ["Withdrawn", { "amount": "ten" }]),
    )
    None
  } catch {
    @strata.DecodeError(event_type~, position~, ..) =>
      Some((event_type, position))
  }
  debug_inspect(failed, content="Some((\"Withdrawn\", Some(Position(1))))")
}

///|
test "decode_all keeps order and drops deprecated events" {
  let codec = @codec.JsonCodec()
  codec.deprecated("Gone")
  let all : Array[@strata.Recorded[Ev]] = codec.decode_all([
    stored("Opened", 1, ["Opened", { "owner": "a" }]),
    stored("Gone", 1, "Gone"),
    stored("Closed", 1, "Closed"),
  ])
  debug_inspect(all.map(r => r.event), content="[Opened(owner=\"a\"), Closed]")
}

///|
test "privacy markings are recorded on the codec" {
  let codec = @codec.JsonCodec()
  codec
  ..shred(fields=[@codec.FieldPath("Opened.owner")])
  .seal(meta=["actor"], when=ctx => ctx.flag("anonymous"))
  debug_inspect(
    codec.shredded_fields(),
    content="[FieldPath(\"Opened.owner\")]",
  )
  debug_inspect(codec.sealed_meta(), content="[\"actor\"]")
  assert_true(
    codec.seals(
      @strata.Context(actor=@strata.Actor("u")).with_flag("anonymous"),
    ),
  )
  assert_false(codec.seals(@strata.Context(actor=@strata.Actor("u"))))
}
