///|
/// Selection matching is on the hot path of every in-memory read and of the
/// DCB condition check.
test "selection matching" (b : @bench.T) {
  let selection = @strata.Selection::any_of([
    @strata.Selection::tags([
      @strata.Tag("code:X"),
      @strata.Tag("period:2026-09"),
    ]),
    @strata.Selection::types(["Moved"], tags=[@strata.Tag("code:Y")]),
  ])
  let tags = [
    @strata.Tag("$stream:ledger-X"),
    @strata.Tag("$category:ledger"),
    @strata.Tag("code:X"),
    @strata.Tag("code:Y"),
    @strata.Tag("period:2026-09"),
  ]
  b.bench(name="matches", fn() {
    for _ in 0..<1000 {
      b.keep(selection.matches(event_type="Moved", tags~))
    }
  })
}

///|
test "ulid increment" (b : @bench.T) {
  let base = @strata.EventId::ulid(
    timestamp=@strata.Instant(0),
    random=b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
  )
  b.bench(name="increment", fn() {
    let mut id = base
    for _ in 0..<1000 {
      id = id.increment()
    }
    b.keep(id)
  })
}
