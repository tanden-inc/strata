///|
/// A cost code such as `"ORG-CORE01"`.
pub type Code = String

///|
/// The tag that puts an event inside a code's consistency boundary.
pub fn code_tag(code : Code) -> @strata.Tag {
  @strata.Tag("code:\{code}")
}

///|
/// Budget movements between codes. Conservation is the invariant: a move
/// debits one code and credits another in a single fact.
pub(all) enum LedgerEvent {
  Moved(
    id~ : @strata.EventId,
    from~ : Code,
    to~ : Code,
    amount~ : Int,
    reason~ : String,
    by~ : @strata.Actor
  )
  Funded(code~ : Code, amount~ : Int, by~ : @strata.Actor)
  Reserved(
    id~ : @strata.EventId,
    code~ : Code,
    amount~ : Int,
    reference~ : String,
    by~ : @strata.Actor
  )
  Released(code~ : Code, reservation~ : @strata.EventId, by~ : @strata.Actor)
  Reversed(
    of~ : @strata.EventId,
    tags~ : Array[@strata.Tag],
    reason~ : String,
    by~ : @strata.Actor
  )
} derive(Eq, Debug, ToJson, FromJson)

///|
/// Ledger commands.
pub(all) enum LedgerCmd {
  Fund(code~ : Code, amount~ : Int)
  Move(from~ : Code, to~ : Code, amount~ : Int, reason~ : String)
  Reserve(code~ : Code, amount~ : Int, reference~ : String)
  Release(code~ : Code, reservation~ : @strata.EventId)
  Reverse(code~ : Code, target~ : @strata.EventId, reason~ : String)
} derive(Eq, Debug)

///|
/// What the ledger remembers about an entry so that it can be reversed.
pub(all) struct Entry {
  tags : Array[@strata.Tag]
  reversed : Bool
} derive(Eq, Debug, ToJson, FromJson)

///|
/// The partial-world state: balances and reservations for the codes the scope
/// owns, plus the entries seen.
pub(all) struct Balances {
  of : Map[Code, Int]
  reserved : Map[Code, Int]
  entries : Map[String, Entry]
} derive(Eq, Debug, ToJson, FromJson)

///|
/// No balances.
pub fn Balances::empty() -> Balances {
  { of: Map([]), reserved: Map([]), entries: Map([]), }
}

///|
/// Balance minus reservations.
pub fn Balances::available(self : Balances, code : Code) -> Int {
  self.of.get(code).unwrap_or(0) - self.reserved.get(code).unwrap_or(0)
}

///|
/// Adds to a code's balance (a copy; state stays a value).
fn Balances::credit(self : Balances, code : Code, amount : Int) -> Balances {
  let of = self.of.copy()
  of[code] = of.get(code).unwrap_or(0) + amount
  { ..self, of, }
}

///|
fn Balances::reserve(self : Balances, code : Code, amount : Int) -> Balances {
  let reserved = self.reserved.copy()
  reserved[code] = reserved.get(code).unwrap_or(0) + amount
  { ..self, reserved, }
}

///|
fn Balances::remember(
  self : Balances,
  id : @strata.EventId,
  tags : Array[@strata.Tag],
) -> Balances {
  let entries = self.entries.copy()
  entries[id.0] = { tags, reversed: false, }
  { ..self, entries, }
}

///|
/// Typed rejections.
pub(all) suberror LedgerError {
  NonPositive(amount~ : Int)
  Insufficient(code~ : Code, available~ : Int, requested~ : Int)
  UnknownReservation(reservation~ : @strata.EventId)
  UnknownEntry(target~ : @strata.EventId)
  AlreadyReversed(target~ : @strata.EventId)
} derive(Eq, Debug)

///|
/// Tags are computed from the event alone, on purpose.
pub fn ledger_tags(e : LedgerEvent) -> Array[@strata.Tag] {
  match e {
    Moved(from~, to~, ..) => [code_tag(from), code_tag(to)]
    Funded(code~, ..) | Reserved(code~, ..) | Released(code~, ..) =>
      [code_tag(code)]
    Reversed(tags~, ..) => tags
  }
}

///|
/// The boundary a command reads.
pub fn ledger_scope(cmd : LedgerCmd) -> @strata.Selection {
  match cmd {
    Move(from~, to~, ..) =>
      @strata.Selection::any_of([
        @strata.Selection::tags([code_tag(from)]),
        @strata.Selection::tags([code_tag(to)]),
      ])
    Fund(code~, ..)
    | Reserve(code~, ..)
    | Release(code~, ..)
    | Reverse(code~, ..) => @strata.Selection::tags([code_tag(code)])
  }
}

///|
/// The ledger decider.
pub let ledger : @strata.DcbDecider[LedgerCmd, LedgerEvent, Balances, Unit] = @strata.DcbDecider(
  category="ledger",
  stream=cmd => {
    match cmd {
      Move(from~, ..) => from
      Fund(code~, ..)
      | Reserve(code~, ..)
      | Release(code~, ..)
      | Reverse(code~, ..) => code
    }
  },
  scope=ledger_scope,
  tags=ledger_tags,
  initial=Balances::empty(),
  decide=(cmd, s, env, _scope) => {
    match cmd {
      Fund(amount~, ..) | Move(amount~, ..) | Reserve(amount~, ..) if amount <=
        0 => raise LedgerError::NonPositive(amount~)
      Fund(code~, amount~) => [Funded(code~, amount~, by=env.actor)]
      Move(from~, to~, amount~, reason~) =>
        if s.available(from) < amount {
          raise LedgerError::Insufficient(
            code=from,
            available=s.available(from),
            requested=amount,
          )
        } else {
          [Moved(id=env.ids.at(0), from~, to~, amount~, reason~, by=env.actor)]
        }
      Reserve(code~, amount~, reference~) =>
        if s.available(code) < amount {
          raise LedgerError::Insufficient(
            code~,
            available=s.available(code),
            requested=amount,
          )
        } else {
          [Reserved(id=env.ids.at(0), code~, amount~, reference~, by=env.actor)]
        }
      Release(code~, reservation~) =>
        if !s.entries.contains(reservation.0) {
          raise LedgerError::UnknownReservation(reservation~)
        } else {
          [Released(code~, reservation~, by=env.actor)]
        }
      Reverse(target~, reason~, ..) =>
        match s.entries.get(target.0) {
          None => raise LedgerError::UnknownEntry(target~)
          Some({ reversed: true, .. }) =>
            raise LedgerError::AlreadyReversed(target~)
          Some(entry) =>
            [Reversed(of=target, tags=entry.tags, reason~, by=env.actor)]
        }
    }
  },
  evolve=(s, e, scope) => {
    match e {
      Funded(code~, amount~, ..) =>
        if scope.owns(code_tag(code)) {
          s.credit(code, amount)
        } else {
          s
        }
      Moved(id~, from~, to~, amount~, ..) => {
        let s1 = if scope.owns(code_tag(from)) {
          s.credit(from, -amount)
        } else {
          s
        }
        let s2 = if scope.owns(code_tag(to)) {
          s1.credit(to, amount)
        } else {
          s1
        }
        s2.remember(id, ledger_tags(e))
      }
      Reserved(id~, code~, amount~, ..) =>
        if scope.owns(code_tag(code)) {
          s.reserve(code, amount).remember(id, ledger_tags(e))
        } else {
          s
        }
      Released(code~, reservation~, ..) =>
        match s.entries.get(reservation.0) {
          Some(_) if scope.owns(code_tag(code)) => {
            let amount = s.reserved.get(code).unwrap_or(0)
            let entries = s.entries.copy()
            entries[reservation.0] = { tags: [code_tag(code)], reversed: true, }
            { ..s.reserve(code, -amount), entries, }
          }
          _ => s
        }
      Reversed(of~, ..) =>
        match s.entries.get(of.0) {
          Some(entry) => {
            let entries = s.entries.copy()
            entries[of.0] = { ..entry, reversed: true, }
            { ..s, entries, }
          }
          None => s
        }
    }
  },
)

///|
/// One row per code for the ledger board.
pub(all) struct CodeRow {
  balance : Int
  reserved : Int
  inbound : Int
  outbound : Int
} derive(Eq, Debug, ToJson, FromJson)

///|
/// The per-code read model: a move fans out to both codes.
pub let code_ledger : @strata.KeyedProjection[LedgerEvent, Code, CodeRow] = @strata.KeyedProjection(
  keys=r => {
    match r.event {
      Moved(from~, to~, ..) => [from, to]
      Funded(code~, ..) | Reserved(code~, ..) | Released(code~, ..) => [code]
      Reversed(tags~, ..) =>
        tags.filter(t => t.key() == "code").map(t => t.value().unwrap_or(""))
    }
  },
  initial={ balance: 0, reserved: 0, inbound: 0, outbound: 0, },
  apply=(code, row, r) => {
    match r.event {
      Funded(amount~, ..) => { ..row, balance: row.balance + amount, }
      Moved(from~, amount~, ..) if code == from =>
        { ..row, balance: row.balance - amount, outbound: row.outbound + 1, }
      Moved(amount~, ..) =>
        { ..row, balance: row.balance + amount, inbound: row.inbound + 1, }
      Reserved(amount~, ..) => { ..row, reserved: row.reserved + amount, }
      Released(..) | Reversed(..) => row
    }
  },
)
