///|
let alice : @strata.Actor = @strata.Actor("user:alice")

///|
// #region history
let history : Array[@ledger.LedgerEvent] = [
  Funded(code="X", amount=100, by=alice),
  Funded(code="Y", amount=50, by=alice),
  Funded(code="Z", amount=999, by=alice),
  Moved(
    id=@strata.EventId("m-1"),
    from="X",
    to="Z",
    amount=10,
    reason="seed",
    by=alice,
  ),
]
// #endregion history

///|
// #region dcb-spec
test "a move needs available budget on the source" {
  @testing.dcb_spec(@ledger.ledger)
  .acting_as(actor=alice)
  .given(history)
  .when(Move(from="Y", to="X", amount=60, reason="too much"))
  |> debug_inspect(
    content="Err(Insufficient(code=\"Y\", available=50, requested=60))",
  )
}

///|
test "a move debits one code and credits the other in one fact" {
  @testing.dcb_spec(@ledger.ledger)
  .acting_as(actor=alice)
  .given(history)
  .when(Move(from="X", to="Y", amount=30, reason="Q4"))
  |> debug_inspect(
    content=(
      #|Ok(
      #|  [
      #|    Moved(
      #|      id=EventId("evt-0001"),
      #|      from="X",
      #|      to="Y",
      #|      amount=30,
      #|      reason="Q4",
      #|      by=Actor("user:alice"),
      #|    ),
      #|  ],
      #|)
    ),
  )
}
// #endregion dcb-spec

///|
// #region partial-world
test "state depends only on the scope" {
  @testing.dcb_spec(@ledger.ledger)
  .given(history)
  .scope_of(Move(from="X", to="Y", amount=10, reason="t"))
  .assert_scope_closed()
}

///|
test "the scope of a move owns both codes and nothing else" {
  let scope = @ledger.ledger.scope_of(
    Move(from="X", to="Y", amount=10, reason="t"),
  )
  assert_true(scope.owns(@ledger.code_tag("X")))
  assert_true(scope.owns(@ledger.code_tag("Y")))
  assert_false(scope.owns(@ledger.code_tag("Z")))
}

///|
test "out-of-scope codes are not written to state" {
  let state = @testing.dcb_spec(@ledger.ledger)
    .given(history)
    .scope_of(Move(from="X", to="Y", amount=10, reason="t"))
    .state()
  inspect(state.available("X"), content="90")
  inspect(state.available("Y"), content="50")
  inspect(state.available("Z"), content="0")
}
// #endregion partial-world

///|
// #region reversal-law
test "reversals stay inside their target's boundary" {
  let reversal_history : Array[@ledger.LedgerEvent] = history +
    [
      Reversed(
        of=@strata.EventId("m-1"),
        tags=[@ledger.code_tag("X"), @ledger.code_tag("Z")],
        reason="oops",
        by=alice,
      ),
    ]
  @testing.dcb_reversal_law(
    @ledger.ledger,
    reverses=e => {
      match e {
        Reversed(of~, ..) => Some(of)
        _ => None
      }
    },
    identity=e => {
      match e {
        Moved(id~, ..) | Reserved(id~, ..) => Some(id)
        _ => None
      }
    },
    histories=[reversal_history],
  )
}
// #endregion reversal-law

///|
// #region reversal-twice
test "reversing twice is rejected" {
  @testing.dcb_spec(@ledger.ledger)
  .acting_as(actor=alice)
  .given(
    history +
    [
      Reversed(
        of=@strata.EventId("m-1"),
        tags=[@ledger.code_tag("X"), @ledger.code_tag("Z")],
        reason="oops",
        by=alice,
      ),
    ],
  )
  .when(Reverse(code="X", target=@strata.EventId("m-1"), reason="again"))
  |> debug_inspect(content="Err(AlreadyReversed(target=EventId(\"m-1\")))")
}
// #endregion reversal-twice

///|
// #region advice
test "charging past the balance is recorded and flagged" {
  let spec = @testing.spec(@ledger.charge)
    .acting_as(actor=alice)
    .given([
      Budgeted(amount=100, by=alice),
      Charged(id=@strata.EventId("c-1"), amount=80, reference="inv-1", by=alice),
    ])
  spec.when(Charge(amount=50, reference="inv-9"))
  |> debug_inspect(
    content=(
      #|Ok(
      #|  [
      #|    Charged(
      #|      id=EventId("evt-0001"),
      #|      amount=50,
      #|      reference="inv-9",
      #|      by=Actor("user:alice"),
      #|    ),
      #|  ],
      #|)
    ),
  )
  spec.advice(Charge(amount=50, reference="inv-9"))
  |> debug_inspect(content="[WillOverrun(landing=-30)]")
  spec.advice(Charge(amount=10, reference="inv-10"))
  |> debug_inspect(content="[]")
}

///|
test "a rejected command gets its error, not commentary" {
  let spec = @testing.spec(@ledger.charge).acting_as(actor=alice)
  spec.when(Charge(amount=0, reference="x"))
  |> debug_inspect(content="Err(NonPositive(amount=0))")
  spec.advice(Charge(amount=0, reference="x")) |> debug_inspect(content="[]")
}
// #endregion advice

///|
// #region keyed-fold
test "the code ledger fans a move out to both codes" {
  let rows = @ledger.code_ledger.fold(
    [
      @testing.recorded(
        (Funded(code="X", amount=100, by=alice) : @ledger.LedgerEvent),
        stream=@strata.StreamId("ledger-X"),
        version=1,
        position=@strata.Position(1),
      ),
      @testing.recorded(
        (
          Moved(
            id=@strata.EventId("m-1"),
            from="X",
            to="Y",
            amount=30,
            reason="Q4",
            by=alice,
          ) : @ledger.LedgerEvent),
        stream=@strata.StreamId("ledger-X"),
        version=2,
        position=@strata.Position(2),
      ),
    ].iter(),
  )
  debug_inspect(
    rows.get("X"),
    content="Some({ balance: 70, reserved: 0, inbound: 0, outbound: 1 })",
  )
  debug_inspect(
    rows.get("Y"),
    content="Some({ balance: 30, reserved: 0, inbound: 1, outbound: 0 })",
  )
}
// #endregion keyed-fold

///|
// #region dcb-handler
async test "moves go through the DCB handler and land in the source stream" {
  let rt = @testing.runtime()
  let codes = rt.dcb_handler(@ledger.ledger)
  let ctx = @strata.Context(actor=alice)
  codes.execute(Fund(code="X", amount=100), ctx~) |> ignore
  let out = codes.execute(Move(from="X", to="Y", amount=30, reason="Q4"), ctx~)
  inspect(out.events[0].stream, content="ledger-X")
  debug_inspect(
    out.events[0].tags,
    content="[Tag(\"code:X\"), Tag(\"code:Y\")]",
  )
  let rows = rt.fold_keyed(
    @ledger.code_ledger,
    @strata.Selection::category("ledger"),
  )
  debug_inspect(rows.get("Y").map(r => r.balance), content="Some(30)")
}
// #endregion dcb-handler

///|
// #region boundary-conflict
async test "a boundary conflict surfaces as AppendConflict" {
  let rt = @testing.runtime()
  let ctx = @strata.Context(actor=alice)
  let codes = rt.dcb_handler(@ledger.ledger)
  codes.execute(Fund(code="X", amount=100), ctx~) |> ignore
  // Simulate a writer that read the scope at position 1 and appends after a
  // competing move has landed.
  codes.execute(Move(from="X", to="Y", amount=10, reason="first"), ctx~)
  |> ignore
  let stale = @strata.NewEvent(
    id=@strata.EventId("stale"),
    event_type="Moved",
    schema=1,
    data=Json(
      (
        Moved(
          id=@strata.EventId("stale"),
          from="X",
          to="Y",
          amount=10,
          reason="second",
          by=alice,
        ) : @ledger.LedgerEvent),
    ),
    tags=[@ledger.code_tag("X"), @ledger.code_tag("Y")],
    meta=@strata.Metadata(),
  )
  let conflict = try {
    rt
    .store()
    .append(
      stream=@strata.StreamId("ledger-X"),
      condition=Dcb(
        selection=@ledger.ledger_scope(
          Move(from="X", to="Y", amount=10, reason="second"),
        ),
        after=Some(@strata.Position(1)),
      ),
      events=[stale],
      recorded_at=@strata.Instant(0),
    )
    |> ignore
    false
  } catch {
    @strata.BoundaryConflict(..) => true
    e => raise e
  }
  assert_true(conflict)
}
// #endregion boundary-conflict
