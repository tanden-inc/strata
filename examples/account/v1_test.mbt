///|
// #region tenant
async test "tenants prefix the stream name and scope reads" {
  let rt = @testing.runtime()
  let accounts = rt.handler(@account.account)
  let ctx = @strata.Context(actor=alice, tenant="t1")
  let out = accounts.execute("acc-1", Open, ctx~)
  inspect(out.events[0].stream, content="t1/account-acc-1")
  accounts.execute("acc-1", Deposit(amount=10), ctx~) |> ignore
  let (view, version) = rt.live(
    @account.balance_view,
    category="account",
    id="acc-1",
    tenant="t1",
  )
  debug_inspect((view, version), content="({ balance: 10, tx_count: 1 }, 2)")
  inspect(
    rt.read(@strata.Selection::category("account", tenant="t2")).events.length(),
    content="0",
  )
}
// #endregion tenant

///|
// #region retry
async test "retry on conflict never retries a domain rejection" {
  let rt = @testing.runtime()
  let accounts = rt.handler(
    @account.account,
    retry=@rt.Retry::on_conflict(max=3),
  )
  let ctx = @strata.Context(actor=alice)
  accounts.execute("acc-1", Open, ctx~) |> ignore
  let rejected = try {
    accounts.execute("acc-1", Withdraw(amount=1), ctx~) |> ignore
    false
  } catch {
    @account.Insufficient(..) => true
    e => raise e
  }
  assert_true(rejected)
  let (state, version) = accounts.load("acc-1")
  inspect(version, content="1")
  inspect(state.balance, content="0")
}
// #endregion retry
