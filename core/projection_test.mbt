///|
#warnings("-unused_value")
priv enum BoxEv {
  Added(Int)
  Removed(Int)
} derive(Eq, Debug, ToJson, FromJson)

///|
let total : @core.Projection[BoxEv, Int] = @core.Projection(initial=0, apply=(
  v,
  e,
) => {
  match e {
    Added(n) => v + n
    Removed(n) => v - n
  }
})

///|
fn rec(e : BoxEv, position : Int) -> @core.Recorded[BoxEv] {
  @core.Recorded(
    id=@core.EventId("e\{position}"),
    position=@core.Position(position.to_int64()),
    stream=@core.StreamId("box-b1"),
    version=position,
    event_type="BoxEv",
    event=e,
    recorded_at=@core.Instant(0),
    meta=@core.Metadata(),
  )
}

///|
test "projections fold" {
  inspect(total.fold([BoxEv::Added(5), BoxEv::Removed(2)].iter()), content="3")
  inspect(total.apply(10, Added(1)), content="11")
}

///|
test "keyed projections fan out" {
  let by_parity : @core.KeyedProjection[BoxEv, String, Int] = @core.KeyedProjection(
    keys=r => {
      match r.event {
        Added(n) | Removed(n) =>
          if n % 2 == 0 {
            ["even", "all"]
          } else {
            ["odd", "all"]
          }
      }
    },
    initial=0,
    apply=(_k, row, r) => {
      match r.event {
        Added(n) => row + n
        Removed(n) => row - n
      }
    },
  )
  let rows = by_parity.fold(
    [rec(Added(2), 1), rec(Added(3), 2), rec(Removed(1), 3)].iter(),
  )
  debug_inspect(rows.get("even"), content="Some(2)")
  debug_inspect(rows.get("odd"), content="Some(2)")
  debug_inspect(rows.get("all"), content="Some(4)")
}

///|
test "multi projections merge typed sources" {
  let view = @core.MultiProjection(initial=0)
  view
  ..source(@core.Selection::category("box"), (v, r : @core.Recorded[BoxEv]) => {
    match r.event {
      Added(n) => v + n
      Removed(n) => v - n
    }
  })
  .source(@core.Selection::category("other"), (v, _r : @core.Recorded[BoxEv]) => {
    v + 100
  })
  inspect(view.sources().length(), content="2")
  assert_eq(
    view.selection(),
    @core.Selection::any_of([
      @core.Selection::category("box"),
      @core.Selection::category("other"),
    ]),
  )
  let stored = @core.StoredEvent(
    id=@core.EventId("e1"),
    position=@core.Position(1),
    stream=@core.StreamId("box-b1"),
    version=1,
    event_type="Added",
    schema=1,
    data=Json(BoxEv::Added(5)),
    tags=[@core.Tag("$stream:box-b1"), @core.Tag("$category:box")],
    meta=@core.Metadata(),
    recorded_at=@core.Instant(0),
  )
  inspect(view.apply_stored(0, stored), content="5")
}
