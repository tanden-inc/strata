///|
priv enum LegacyAccount {
  Opened(owner~ : String)
  Closed
} derive(Debug, ToJson(style="legacy"), FromJson(style="legacy"))

///|
test "legacy style decodes, upgrades, and handles payload-less variants" {
  let codec = @codec.JsonCodec(style=Legacy(tag_key="$tag"), schema_version=2)
  codec.migrate("Opened", from=1, @codec.Upcast::add_field("owner", "unknown"))
  let e = codec.encode(LegacyAccount::Opened(owner="alice"))
  let r : @strata.Recorded[LegacyAccount]? = codec.decode(
    stored(e.event_type, e.schema, e.data),
  )
  debug_inspect(r.map(x => x.event), content="Some(Opened(owner=\"alice\"))")
  let old : @strata.Recorded[LegacyAccount]? = codec.decode(
    stored("Opened", 1, { "$tag": "Opened" }),
  )
  debug_inspect(
    old.map(x => x.event),
    content="Some(Opened(owner=\"unknown\"))",
  )
  let closed : @strata.Recorded[LegacyAccount]? = codec.decode(
    stored("Closed", 2, { "$tag": "Closed" }),
  )
  debug_inspect(closed.map(x => x.event), content="Some(Closed)")
}

///|
test "system events ($strata.*) are skipped by decode like deprecated types" {
  let codec = @codec.JsonCodec()
  let marker : @strata.Recorded[LegacyAccount]? = codec.decode(
    stored("$strata.forgotten", 1, "$strata.forgotten"),
  )
  debug_inspect(marker, content="None")
  let all : Array[@strata.Recorded[LegacyAccount]] = codec.decode_all([
    stored("$strata.unsealed", 1, "$strata.unsealed"),
  ])
  inspect(all.length(), content="0")
}
