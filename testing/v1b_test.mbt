///|
priv enum BareEv {
  Entry(id~ : @strata.EventId)
  Undo(of~ : @strata.EventId)
} derive(Eq, Debug)

///|
let bare : @strata.DcbDecider[Unit, BareEv, Int, Unit] = @strata.DcbDecider(
  category="bare",
  stream=_ => "x",
  scope=_ => @strata.Selection::all(),
  tags=_ => [],
  initial=0,
  decide=(_c, _s, _e, _scope) => [],
  evolve=(s, _e, _scope) => s,
)

///|
test "dcb_reversal_law rejects a target that has no boundary at all" {
  let failed = try {
    @testing.dcb_reversal_law(
      bare,
      reverses=e => {
        match e {
          Undo(of~) => Some(of)
          _ => None
        }
      },
      identity=e => {
        match e {
          Entry(id~) => Some(id)
          _ => None
        }
      },
      histories=[
        [Entry(id=@strata.EventId("e1")), Undo(of=@strata.EventId("e1"))],
      ],
    )
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}
