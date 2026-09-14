///|
let code_x : @core.Tag = @core.Tag("code:X")

///|
let code_y : @core.Tag = @core.Tag("code:Y")

///|
test "the empty selection is the whole log" {
  assert_true(@core.Selection::all().is_all())
  assert_true(@core.Selection::all().matches(event_type="Anything", tags=[]))
  assert_false(@core.Selection::tags([code_x]).is_all())
}

///|
test "tags within an item are ANDed, items are ORed" {
  let both = @core.Selection::tags([code_x, code_y])
  assert_true(both.matches(event_type="Moved", tags=[code_x, code_y]))
  assert_false(both.matches(event_type="Moved", tags=[code_x]))
  let either = @core.Selection::any_of([
    @core.Selection::tags([code_x]),
    @core.Selection::tags([code_y]),
  ])
  assert_true(either.matches(event_type="Moved", tags=[code_x]))
  assert_true(either.matches(event_type="Moved", tags=[code_y]))
  assert_false(either.matches(event_type="Moved", tags=[@core.Tag("code:Z")]))
}

///|
test "types restrict within an item, empty types mean any" {
  let sel = @core.Selection::types(["Moved", "Reserved"], tags=[code_x])
  assert_true(sel.matches(event_type="Moved", tags=[code_x]))
  assert_false(sel.matches(event_type="Released", tags=[code_x]))
  assert_false(sel.matches(event_type="Moved", tags=[code_y]))
  assert_true(
    @core.Selection::types(["Moved"]).matches(event_type="Moved", tags=[]),
  )
}

///|
test "streams and categories are system tags" {
  let stream = @core.StreamId("account-acc-1")
  let sel = @core.Selection::stream(stream)
  debug_inspect(
    sel.single_stream(),
    content="Some(StreamId(\"account-acc-1\"))",
  )
  assert_true(
    sel.matches(event_type="Opened", tags=[
      @core.Tag("$stream:account-acc-1"),
      @core.Tag("$category:account"),
    ]),
  )
  assert_false(
    sel.matches(event_type="Opened", tags=[@core.Tag("$category:account")]),
  )
  let cat = @core.Selection::category("account")
  debug_inspect(cat.single_stream(), content="None")
  assert_true(
    cat.matches(event_type="Opened", tags=[@core.Tag("$category:account")]),
  )
  let tenant = @core.Selection::category("account", tenant="t1")
  assert_false(
    tenant.matches(event_type="Opened", tags=[@core.Tag("$category:account")]),
  )
  assert_true(
    tenant.matches(event_type="Opened", tags=[
      @core.Tag("$category:account"),
      @core.Tag("$tenant:t1"),
    ]),
  )
}

///|
test "constructors normalise so equal sets are equal values" {
  let a = @core.Selection::any_of([
    @core.Selection::tags([code_x, code_y]),
    @core.Selection::types(["Moved"]),
  ])
  let b = @core.Selection::any_of([
    @core.Selection::types(["Moved"]),
    @core.Selection::tags([code_y, code_x, code_x]),
  ])
  assert_eq(a, b)
  assert_eq(a.hash(), b.hash())
  inspect(a.items().length(), content="2")
}

///|
test "selections round-trip through JSON" {
  let sel = @core.Selection::types(["Moved"], tags=[code_x])
  let back : @core.Selection = @json.from_json(Json(sel))
  assert_eq(back, sel)
}

///|
test "a scope owns exactly the tags of its selection" {
  let scope = @core.Scope::of(
    @core.Selection::any_of([
      @core.Selection::tags([code_x]),
      @core.Selection::tags([code_y]),
    ]),
  )
  assert_true(scope.owns(code_x))
  assert_true(scope.owns(code_y))
  assert_false(scope.owns(@core.Tag("code:Z")))
}
