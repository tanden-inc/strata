# examples/ledger

The reference domain for dynamic consistency boundaries, advice, reversals and a keyed read model. The block below
is compiled and run by `moon test`; the tutorial imports the rest of this package by region.

```mbt check
///|
test "a move is one fact across two boundaries" {
  let alice = @strata.Actor("user:alice")
  @testing.dcb_spec(@ledger.ledger)
  .acting_as(actor=alice)
  .given([Funded(code="X", amount=100, by=alice)])
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
```
