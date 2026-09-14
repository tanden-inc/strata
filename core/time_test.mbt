///|
test "instants parse and format ISO-8601 UTC" {
  let t = @core.Instant::parse("2026-09-13T00:00:00Z")
  inspect(t.0, content="1789257600000")
  inspect(t.to_iso8601(), content="2026-09-13T00:00:00.000Z")
  let f = @core.Instant::parse("2026-09-13T12:34:56.789Z")
  inspect(f.to_iso8601(), content="2026-09-13T12:34:56.789Z")
  inspect(@core.Instant(0).to_iso8601(), content="1970-01-01T00:00:00.000Z")
  let bad = try {
    @core.Instant::parse("yesterday") |> ignore
    false
  } catch {
    @core.InvalidInstant(_) => true
  }
  assert_true(bad)
}

///|
test "instant arithmetic" {
  let t = @core.Instant(1000)
  assert_eq(t.add(@core.Duration::seconds(2)), @core.Instant(3000))
  assert_eq(@core.Instant(3000).since(t), @core.Duration::millis(2000))
  inspect(@core.Duration::minutes(1).to_millis(), content="60000")
  inspect(@core.Duration::hours(1).to_millis(), content="3600000")
}

///|
test "instants serialise as ISO strings" {
  json_inspect(@core.Instant(0), content="1970-01-01T00:00:00.000Z")
  let back : @core.Instant = @json.from_json("1970-01-01T00:00:01.000Z")
  assert_eq(back, @core.Instant(1000))
}
