///|
test "instants reject second 60 and impossible dates, and accept leap days" {
  for
    bad in [
      "2026-09-13T00:00:60Z", "2026-02-30T00:00:00Z", "2100-02-29T00:00:00Z", "2026-13-01T00:00:00Z",
      "2026-09-13T24:00:00Z",
    ] {
    let rejected = try {
      @core.Instant::parse(bad) |> ignore
      false
    } catch {
      @core.InvalidInstant(_) => true
    }
    assert_true(rejected, msg=bad)
  }
  inspect(
    @core.Instant::parse("2024-02-29T12:00:00Z").to_iso8601(),
    content="2024-02-29T12:00:00.000Z",
  )
  inspect(
    @core.Instant::parse("2000-02-29T00:00:00Z").to_iso8601(),
    content="2000-02-29T00:00:00.000Z",
  )
}

///|
test "none selects nothing; the union of nothing is none, not all" {
  let none = @core.Selection::none()
  assert_false(none.is_all())
  assert_false(
    none.matches(event_type="Anything", tags=[@core.Tag("$category:x")]),
  )
  assert_eq(@core.Selection::any_of([]), none)
  assert_true(@core.Selection::any_of([@core.Selection::all()]).is_all())
  assert_true(@core.Selection::all() != none)
  let back : @core.Selection = @json.from_json(Json(none))
  assert_eq(back, none)
  debug_inspect(none.single_stream(), content="None")
}

///|
test "a multi projection with no sources subscribes to nothing" {
  let view : @core.MultiProjection[Int] = @core.MultiProjection(initial=0)
  assert_eq(view.selection(), @core.Selection::none())
}

///|
test "id batches remember the highest index taken" {
  let ids = @core.IdBatch::deterministic()
  inspect(ids.high_water(), content="-1")
  ids.at(0) |> ignore
  ids.at(2) |> ignore
  ids.at(1) |> ignore
  inspect(ids.high_water(), content="2")
  let offset = ids.offset(5)
  inspect(offset.at(0), content="evt-0006")
  inspect(offset.high_water(), content="0")
}

///|
test "system event types are recognisable" {
  assert_true(@core.Tag("$strata.forgotten").is_system())
  assert_true(@core.is_system_event_type("$strata.forgotten"))
  assert_false(@core.is_system_event_type("Deposited"))
}
