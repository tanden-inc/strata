# examples/account

The README's "Sixty seconds" domain, kept executable. The block below is compiled and run by `moon test`.

```mbt check
///|
test "withdrawals cannot exceed the balance" {
  let alice = @strata.Actor("user:alice")
  @testing.spec(@account.account)
  .acting_as(actor=alice)
  .given([Opened(owner=alice), Deposited(amount=50, by=alice)])
  .when(Withdraw(amount=80))
  |> debug_inspect(content="Err(Insufficient(balance=50, requested=80))")
}
```
