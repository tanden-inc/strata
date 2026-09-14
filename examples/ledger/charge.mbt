///|
/// A record-first domain: charges against a code are recorded even when they
/// overrun; the caller is told.
pub(all) enum ChargeEvent {
  Budgeted(amount~ : Int, by~ : @strata.Actor)
  Charged(
    id~ : @strata.EventId,
    amount~ : Int,
    reference~ : String,
    by~ : @strata.Actor
  )
  OverrunExplained(reason~ : String, landing~ : Int, by~ : @strata.Actor)
} derive(Eq, Debug, ToJson, FromJson)

///|
/// Charge commands.
pub(all) enum ChargeCmd {
  Budget(amount~ : Int)
  Charge(amount~ : Int, reference~ : String)
  Explain(reason~ : String, landing~ : Int)
} derive(Eq, Debug)

///|
/// Advice: returned to the caller, never stored.
pub(all) enum ChargeNotice {
  WillOverrun(landing~ : Int)
  UnfundedCode
} derive(Eq, Debug, ToJson)

///|
/// A code's budget and what is left of it.
pub(all) struct CodeLedger {
  budget : Int
  balance : Int
} derive(Eq, Debug, ToJson, FromJson)

///|
/// Malformed input is the only rejection.
pub(all) suberror ChargeError {
  NonPositive(amount~ : Int)
} derive(Eq, Debug)

///|
/// The charge decider: `decide` records, `advise` warns.
pub let charge : @strata.Decider[
  ChargeCmd,
  ChargeEvent,
  CodeLedger,
  ChargeNotice,
] = @strata.Decider(
  category="code",
  initial={ budget: 0, balance: 0, },
  decide=(cmd, _s, env) => {
    match cmd {
      Budget(amount~) | Charge(amount~, ..) if amount <= 0 =>
        raise ChargeError::NonPositive(amount~)
      Budget(amount~) => [Budgeted(amount~, by=env.actor)]
      Charge(amount~, reference~) =>
        [Charged(id=env.ids.at(0), amount~, reference~, by=env.actor)]
      Explain(reason~, landing~) =>
        [OverrunExplained(reason~, landing~, by=env.actor)]
    }
  },
  advise=(cmd, s, _env) => {
    match cmd {
      Charge(..) if s.budget == 0 => [UnfundedCode]
      Charge(amount~, ..) if s.balance - amount < 0 =>
        [WillOverrun(landing=s.balance - amount)]
      _ => []
    }
  },
  evolve=(s, e) => {
    match e {
      Budgeted(amount~, ..) =>
        { budget: s.budget + amount, balance: s.balance + amount, }
      Charged(amount~, ..) => { ..s, balance: s.balance - amount, }
      OverrunExplained(..) => s
    }
  },
)
