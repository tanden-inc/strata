///|
/// Facts about an account. Actors are recorded where the domain cares.
pub(all) enum AccountEvent {
  Opened(owner~ : @strata.Actor)
  Deposited(amount~ : Int, by~ : @strata.Actor)
  Withdrawn(amount~ : Int, by~ : @strata.Actor)
  Closed(by~ : @strata.Actor)
} derive(Eq, Debug, ToJson, FromJson)

///|
/// Intents. Commands do not say who or when; that is the environment's job.
pub(all) enum AccountCmd {
  Open
  Deposit(amount~ : Int)
  Withdraw(amount~ : Int)
  Close
} derive(Eq, Debug)

///|
/// The state, a fold over events.
pub(all) struct Account {
  owner : @strata.Actor?
  balance : Int
  closed : Bool
} derive(Eq, Debug, ToJson, FromJson)

///|
/// Typed rejections.
pub(all) suberror AccountError {
  AlreadyOpened
  NotOpened
  NotOwner
  NonPositive(amount~ : Int)
  Insufficient(balance~ : Int, requested~ : Int)
  NotEmpty(balance~ : Int)
  AlreadyClosed
} derive(Eq, Debug)

///|
/// The account decider: guard-first, no advice.
pub let account : @strata.Decider[AccountCmd, AccountEvent, Account, Unit] = @strata.Decider(
  category="account",
  initial={ owner: None, balance: 0, closed: false, },
  decide=(cmd, s, env) => {
    match (cmd, s) {
      (_, { closed: true, .. }) => raise AccountError::AlreadyClosed
      (Open, { owner: Some(_), .. }) => raise AccountError::AlreadyOpened
      (Open, _) => [Opened(owner=env.actor)]
      (_, { owner: None, .. }) => raise AccountError::NotOpened
      (Withdraw(..) | Close, _) if Some(env.actor) != s.owner =>
        raise AccountError::NotOwner
      (Deposit(amount~), _) if amount <= 0 =>
        raise AccountError::NonPositive(amount~)
      (Deposit(amount~), _) => [Deposited(amount~, by=env.actor)]
      (Withdraw(amount~), _) if amount <= 0 =>
        raise AccountError::NonPositive(amount~)
      (Withdraw(amount~), _) if amount > s.balance =>
        raise AccountError::Insufficient(balance=s.balance, requested=amount)
      (Withdraw(amount~), _) => [Withdrawn(amount~, by=env.actor)]
      (Close, _) if s.balance != 0 =>
        raise AccountError::NotEmpty(balance=s.balance)
      (Close, _) => [Closed(by=env.actor)]
    }
  },
  evolve=(s, e) => {
    match e {
      Opened(owner~) => { ..s, owner: Some(owner), }
      Deposited(amount~, ..) => { ..s, balance: s.balance + amount, }
      Withdrawn(amount~, ..) => { ..s, balance: s.balance - amount, }
      Closed(..) => { ..s, closed: true, }
    }
  },
  is_terminal=s => s.closed,
)

///|
/// A live view: balance and transaction count.
pub(all) struct BalanceView {
  balance : Int
  tx_count : Int
} derive(Eq, Debug, ToJson, FromJson)

///|
/// The balance projection.
pub let balance_view : @strata.Projection[AccountEvent, BalanceView] = @strata.Projection(
  initial={ balance: 0, tx_count: 0, },
  apply=(v, e) => {
    match e {
      Deposited(amount~, ..) =>
        { balance: v.balance + amount, tx_count: v.tx_count + 1, }
      Withdrawn(amount~, ..) =>
        { balance: v.balance - amount, tx_count: v.tx_count + 1, }
      Opened(..) | Closed(..) => v
    }
  },
)
