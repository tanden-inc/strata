# 6. Dynamic consistency boundaries

Some invariants do not fit in one stream. The canonical example is not uniqueness but *conservation*: moving budget
between two cost codes must debit one and credit the other in a single atomic fact, so the total is preserved by
construction rather than repaired by a process manager afterwards.

With a dynamic consistency boundary (DCB), a command declares the set of events it reads as a
[`Selection`](/concepts/selections), and the store rejects the append if any event matching that selection appeared in
between. The [DCB specification](https://dcb.events) describes the model; Strata's `Selection` is its query and
`AppendCondition::Dcb` is its append condition.

## Codes, tags, and events

A boundary is named by tags. The ledger puts every event inside the boundaries of the codes it touches.

<<< @/../examples/ledger/ledger.mbt#code

<<< @/../examples/ledger/ledger.mbt#events

## The partial-world state

A DCB state is a fold over *only the events the scope selected*. The state therefore keeps balances for the codes the
scope owns and remembers the entries it has seen, so that they can be reversed later.

<<< @/../examples/ledger/ledger.mbt#state

<<< @/../examples/ledger/ledger.mbt#errors

## Tags and scope

Two functions map the domain onto boundaries. `ledger_tags` is computed from the event alone, on purpose: a tag that
depended on state would make the boundary depend on who was looking. `ledger_scope` says which selection a command
reads; a move reads both codes.

<<< @/../examples/ledger/ledger.mbt#boundary

## The decider

`DcbDecider` is deliberately parallel to `Decider`, with three extra pieces: `stream` picks the home stream of the
events (a move lands in the source code's stream), `scope` is the boundary, and `tags` places events in boundaries.
`decide` and `evolve` also receive the `Scope`.

<<< @/../examples/ledger/ledger.mbt#decider

Look at `evolve`. `Moved(from=X, to=Y)` matched the scope `code:X`, and its effect on `Y` must be ignored: `Y` is
outside this decision's world, its balance was not read, so it must not be written to state either.
`scope.owns(tag)` makes that discipline mechanical rather than remembered.

## Specs for a DCB decider

`@testing.dcb_spec` mirrors `spec`. Notice that the history below contains events about code `Z`, which no move
between `X` and `Y` should see.

<<< @/../examples/ledger/ledger_test.mbt#history

<<< @/../examples/ledger/ledger_test.mbt#dcb-spec

`assert_scope_closed` checks the partial-world property directly: removing every out-of-scope event from the history
must not change the resulting state. A leak is a failing test, not a subtle balance drift.

<<< @/../examples/ledger/ledger_test.mbt#partial-world

## Through the runtime

`rt.dcb_handler(decider)` returns a `DcbHandler`. Its `execute(cmd, ctx~)` takes no stream id, because the decider
derives the stream from the command. The event lands in the `ledger-X` stream *and* carries both tags, so a reactor
can follow `Selection::category("ledger")` or `Selection::tags([Tag("code:Y")])`, and a view can fold either.

<<< @/../examples/ledger/ledger_test.mbt#dcb-handler

Under the hood this is the same `EventStore::append`, with `AppendCondition::Dcb(selection~, after~)` instead of
`Stream(id, version)`; `after` is the log head the handler observed before reading its scope. A competing in-scope
write between the read and the append is an `AppendConflict::BoundaryConflict`:

<<< @/../examples/ledger/ledger_test.mbt#boundary-conflict

## Reversals

Stored events are never deleted or edited; a mistake is corrected by recording that it was a mistake. A reversal names
the entry it undoes by id (which is why `env.ids` exists) and **carries its target's tags**, so it lands inside the
same boundaries and the same views as the thing it reverses. The law that keeps this honest is
`@testing.dcb_reversal_law`:

<<< @/../examples/ledger/ledger_test.mbt#reversal-law

<<< @/../examples/ledger/ledger_test.mbt#reversal-twice

[Concepts: Reversals](/concepts/reversals) covers partial reversals, reversing a reversal, and closing periods with
open corrections.

## Streams or DCB?

Use streams by default; use DCB where the invariant crosses them. In a record-first domain DCB is rare: a *charge*
against a code that may go negative ([part 5](/tutorial/05-advice)) needs no boundary at all. Only the *move*, which
must not create money, needs one. Hot tags are handled the way hot streams are: `dcb_handler(decider, snapshot=...)`
keys snapshots by the normalised selection, and a period tag in the scope keeps the selected set small; see
[Closing the books and snapshots](/concepts/closing-and-snapshots).

## Next

[Part 7](/tutorial/07-reactors) reacts to recorded events with commands, and handles redelivery and failure.
