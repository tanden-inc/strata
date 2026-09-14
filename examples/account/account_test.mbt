///|
let alice : @strata.Actor = @strata.Actor("user:alice")

///|
let mallory : @strata.Actor = @strata.Actor("user:mallory")

///|
test "withdrawals cannot exceed the balance" {
  @testing.spec(@account.account)
  .acting_as(actor=alice)
  .given([Opened(owner=alice), Deposited(amount=50, by=alice)])
  .when(Withdraw(amount=80))
  |> debug_inspect(content="Err(Insufficient(balance=50, requested=80))")
}

///|
test "only the owner can withdraw" {
  @testing.spec(@account.account)
  .acting_as(actor=mallory)
  .given([Opened(owner=alice), Deposited(amount=50, by=alice)])
  .when(Withdraw(amount=10))
  |> debug_inspect(content="Err(NotOwner)")
}

///|
test "close requires zero balance, then succeeds" {
  let spec = @testing.spec(@account.account)
    .acting_as(actor=alice)
    .given([Opened(owner=alice), Deposited(amount=50, by=alice)])
  spec.when(Close) |> debug_inspect(content="Err(NotEmpty(balance=50))")
  spec.when_all([Withdraw(amount=50), Close])
  |> debug_inspect(
    content=(
      #|Ok(
      #|  [
      #|    Withdrawn(amount=50, by=Actor("user:alice")),
      #|    Closed(by=Actor("user:alice")),
      #|  ],
      #|)
    ),
  )
}

///|
test "a closed account is terminal" {
  let spec = @testing.spec(@account.account)
    .acting_as(actor=alice)
    .given([Opened(owner=alice), Closed(by=alice)])
  assert_true(@account.account.is_terminal(spec.state()))
  spec.when(Deposit(amount=1)) |> debug_inspect(content="Err(AlreadyClosed)")
}

///|
test "replay equals snapshot plus tail" {
  let events : Array[@account.AccountEvent] = [
    @account.Opened(owner=alice),
    @account.Deposited(amount=50, by=alice),
    @account.Withdrawn(amount=20, by=alice),
    @account.Deposited(amount=5, by=alice),
  ]
  @testing.replay_law(@account.account, events)
}

///|
test "preview runs the same rules without a store" {
  let preview = @strata.Preview(
    @account.account,
    state={ owner: Some(alice), balance: 50, closed: false, },
    env=@testing.env(actor=alice),
  )
  preview.of(Withdraw(amount=80)).result
  |> debug_inspect(content="Err(Insufficient(balance=50, requested=80))")
  preview.of(Withdraw(amount=20)).result
  |> debug_inspect(
    content="Ok([Withdrawn(amount=20, by=Actor(\"user:alice\"))])",
  )
}

///|
test "the balance view folds deposits and withdrawals" {
  let events : Array[@account.AccountEvent] = [
    @account.Opened(owner=alice),
    @account.Deposited(amount=50, by=alice),
    @account.Withdrawn(amount=20, by=alice),
  ]
  @account.balance_view.fold(events.iter())
  |> debug_inspect(content="{ balance: 30, tx_count: 2 }")
}

///|
async test "execute appends and returns the stream version" {
  let rt = @testing.runtime()
  let accounts = rt.handler(@account.account)
  let ctx = @strata.Context(actor=alice)
  accounts.execute("acc-1", Open, ctx~) |> ignore
  let out = accounts.execute("acc-1", Deposit(amount=100), ctx~)
  inspect(out.version, content="2")
  out.events.map(r => r.event)
  |> debug_inspect(content="[Deposited(amount=100, by=Actor(\"user:alice\"))]")
  inspect(out.events[0].id, content="evt-0002")
  inspect(out.events[0].stream, content="account-acc-1")
}

///|
async test "domain rejections propagate unchanged" {
  let rt = @testing.runtime()
  let accounts = rt.handler(@account.account)
  let ctx = @strata.Context(actor=alice)
  accounts.execute("acc-1", Open, ctx~) |> ignore
  let rejected = try {
    accounts.execute("acc-1", Withdraw(amount=1), ctx~) |> ignore
    None
  } catch {
    @account.Insufficient(balance~, requested~) => Some((balance, requested))
    e => raise e
  }
  debug_inspect(rejected, content="Some((0, 1))")
}

///|
async test "idempotent replay returns the original outcome" {
  let rt = @testing.runtime()
  let accounts = rt.handler(@account.account)
  let ctx = @strata.Context(actor=alice)
  accounts.execute("acc-1", Open, ctx~) |> ignore
  let a = accounts.execute(
    "acc-1",
    Deposit(amount=100),
    ctx~,
    idempotency_key="req-7f3a",
  )
  let b = accounts.execute(
    "acc-1",
    Deposit(amount=100),
    ctx~,
    idempotency_key="req-7f3a",
  )
  assert_eq(a.version, b.version)
  assert_eq(a.position, b.position)
  assert_false(a.deduplicated)
  assert_true(b.deduplicated)
  let (state, version) = accounts.load("acc-1")
  inspect(version, content="2")
  inspect(state.balance, content="100")
}

///|
async test "a stale expected version conflicts" {
  let rt = @testing.runtime()
  let accounts = rt.handler(@account.account)
  let ctx = @strata.Context(actor=alice)
  accounts.execute("acc-1", Open, ctx~) |> ignore
  accounts.execute("acc-1", Deposit(amount=100), ctx~) |> ignore
  let conflict = try {
    accounts.execute("acc-1", Withdraw(amount=10), ctx~, expected=Exact(1))
    |> ignore
    None
  } catch {
    @strata.StreamConflict(expected~, actual~, ..) => Some((expected, actual))
    e => raise e
  }
  debug_inspect(conflict, content="Some((Exact(1), 2))")
}

///|
async test "live folds the stream on read and returns the version" {
  let rt = @testing.runtime()
  let accounts = rt.handler(@account.account)
  let ctx = @strata.Context(actor=alice)
  accounts.execute("acc-1", Open, ctx~) |> ignore
  accounts.execute("acc-1", Deposit(amount=100), ctx~) |> ignore
  accounts.execute("acc-1", Withdraw(amount=30), ctx~) |> ignore
  let (view, version) = rt.live(
    @account.balance_view,
    category="account",
    id="acc-1",
  )
  debug_inspect((view, version), content="({ balance: 70, tx_count: 2 }, 3)")
}

///|
async test "a terminal stream rejects further commands without deciding" {
  let rt = @testing.runtime()
  let accounts = rt.handler(@account.account)
  let ctx = @strata.Context(actor=alice)
  accounts.execute("acc-1", Open, ctx~) |> ignore
  accounts.execute("acc-1", Close, ctx~) |> ignore
  let terminal = try {
    accounts.execute("acc-1", Deposit(amount=1), ctx~) |> ignore
    false
  } catch {
    @rt.Terminal(..) => true
    e => raise e
  }
  assert_true(terminal)
}
