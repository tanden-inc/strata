# Consistency boundaries

Some invariants do not fit in one stream. The canonical example is not uniqueness but *conservation*: moving budget
between two cost codes must debit one and credit the other in a single, atomic fact, so the total is preserved by
construction rather than repaired by a process manager.

With a dynamic consistency boundary (DCB), a command declares the set of events it reads as a
[`Selection`](/concepts/selections), and the store rejects the append if any event matching that selection appeared in
between. [Tutorial part 6](/tutorial/06-dynamic-consistency-boundaries) walks through the compiled ledger; this page
explains the model.

## Streams by default, DCB where the invariant crosses them

Streams when one entity owns the invariant. DCB when the invariant is a relationship between entities: conservation,
exclusivity, a cap across a group. Both go through the same `append`, the same `Selection`, and the same read side,
so choosing late is cheap.

Notice that in a record-first domain, DCB is rare: a *charge* against a code that may go negative needs no boundary
at all; it is an append to the code's stream with a [notice](/tutorial/05-advice). Only the *move*, which must not
create money, needs the boundary. Most record-first ledgers are DCB-light.

## The shape

`DcbDecider` is deliberately parallel to `Decider`, with three extra pieces:

| Piece | Type | Role |
|---|---|---|
| `stream` | `(C) -> String` | the home stream of the events a command records (a move lands in the source code's stream) |
| `scope` | `(C) -> Selection` | the boundary: the events this decision reads and must not be overtaken on |
| `tags` | `(E) -> Array[Tag]` | which boundaries an event belongs to; computed from the event alone |

`decide`, `evolve` and `advise` receive the `Scope` as an extra argument.

Under the hood the handler reads the log head, reads the scope's selection, replays it, decides, and appends under
`AppendCondition::Dcb(selection~, after~)` where `after` is the head it observed. The event lands in its home stream
*and* carries its tags, so a reactor can follow the category or a tag, and a view can fold either. The PostgreSQL
store will index tags with GIN and check the condition inside the insert transaction.

## The partial world

A DCB state is a fold over *only the events the scope selected*. That is what makes the boundary small and the append
cheap, and it has one consequence worth stating plainly: an event may mention things the scope does not own.
`Moved(from=X, to=Y)` matched the scope `code:X`, and its effect on `Y` must be ignored: `Y` is outside this decision's
world, its balance is not being read, so it must not be written to state either.

Strata makes this discipline mechanical rather than remembered:

- `evolve` receives the `Scope`. `scope.owns(tag)` answers "is this tag part of the selection that produced these
  events?" State updates for anything else are simply not made.
- `@testing.dcb_spec(...).assert_scope_closed()` checks the property directly: removing every out-of-scope event from
  the history must not change the resulting state. A leak is a failing test, not a subtle balance drift.
- `Scope` is also available to `decide` and `advise`, so a rule can refuse to act, or warn, about a code it did not
  read.

## Hot tags

A root code that appears in thousands of moves is handled the same way hot streams are. DCB handlers accept
`snapshot=`, keyed by the normalised selection and a version stamp, and period tags (`period:2026-Q4`) in the scope
keep the selected set small. The boundary still holds on the snapshot path: the handler reads the head before the
scope's tail, always. See [Closing the books and snapshots](/concepts/closing-and-snapshots).

## Reversals inside the boundary

A reversal carries its target's tags, so it lands inside the same boundaries and the same views as the thing it
reverses. `@testing.dcb_reversal_law` checks that for every history. See [Reversals](/concepts/reversals).
