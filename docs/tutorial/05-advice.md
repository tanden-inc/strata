# 5. Advice: informing without blocking

A budget code that may be overspent, a timesheet that may exceed the plan, a shipment that may miss its window: in
many domains the correct behaviour is to record the fact and tell someone, not to refuse. Writing that with `raise` is
wrong because it blocks; writing it as an event is wrong because it puts a derivation in the log. `advise` is the
third option.

## A record-first domain

The ledger example's `charge` decider records charges against a cost code even when they overrun. The only rejection
is malformed input. A second enum names what the caller should know.

<<< @/../examples/ledger/charge.mbt#types

`advise` receives exactly what `decide` receives, so a notice can be as informed as a rejection. It returns notices;
it cannot raise and it cannot record.

<<< @/../examples/ledger/charge.mbt#decider

The fourth type parameter of `Decider[C, E, S, N]` names the notice type. The account decider from part 1 has no
advice, so its `N` is `Unit`.

## Rules of advice

- Notices come back in `out.notices`. They are not stored, not replayed, not part of any read model.
- `advise` is evaluated only when `decide` succeeds. A rejected command gets its error, not commentary.
- If a fact deserves to persist, *the responsible person explained the overrun*, that is an event, recorded by a
  command (`Explain` above).
- `advise` is free to be heuristic, to change weekly, to differ per deployment. `decide` is the function you prove
  things about and whose output the store persists; keeping them apart keeps the proof surface small.

## Advice in specs

Advice is a first-class expectation alongside events. `spec.advice(cmd)` returns the notices, and a spec for a
rejected command returns none:

<<< @/../examples/ledger/ledger_test.mbt#advice

`spec.decision(cmd)` returns both at once as a `Decision { events, notices }`.

## Raise, advise, or record?

`raise` when the fact must not exist: money created from nothing, an action by someone who cannot take it. `advise`
when the fact may exist but someone should know: an overspend, a late entry, an unusual amount. Record an event when a
*person* responds to that knowledge: an explanation, an acknowledgement, a correction. The log holds what happened;
advice holds what is worth noticing; neither pretends to be the other.

## Next

[Part 6](/tutorial/06-dynamic-consistency-boundaries) moves to the `ledger` decider in the same package, where the
invariant, conservation of budget, crosses streams.
