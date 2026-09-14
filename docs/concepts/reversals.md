# Reversals

Stored events are never deleted or edited. A mistake is corrected by recording that it was a mistake. In
ledger-shaped domains this is not an edge case but a daily operation, so Strata gives it a shape and a law.

## Shape

- A reversal names its target by `EventId`. This is why decisions receive `env.ids`: an entry must have an id at the
  moment it is recorded so that it can be named later.
- A reversal **carries its target's tags** (`Reversed(of~, tags~, ...)`), so it lands inside the same consistency
  boundaries and the same views as the thing it reverses.
- Tags are computed from the event alone (`tags=` on the decider). A tag that depended on state would make the
  boundary depend on who was looking.

```moonbit
(Reverse(target~, reason~), _) => match s.entries.get(target) {
  None        => raise LedgerError::UnknownEntry(target~)
  Some(entry) if entry.reversed => raise LedgerError::AlreadyReversed(target~)
  Some(entry) => [Reversed(of=target, tags=entry.tags, reason~, by=env.actor)]
}
```

Because the reversal is itself an event, the fact that a correction happened, who made it, and why, are as permanent
as the entry that was corrected.

## Law

`@testing.reversal_law` (for a `Decider`) and `@testing.dcb_reversal_law` (for a `DcbDecider`) check, for every
history given:

1. `tags(reversal) ⊇ tags(target)`, and the target exists in the history; a target without a boundary fails the law;
2. optionally (`restores=`), that the state after the reversal relates to the state before the target as the domain
   says it should.

```moonbit
test "reversals stay inside their target's boundary" {
  @testing.dcb_reversal_law(
    ledger,
    reverses=e => match e { Reversed(of~, ..) => Some(of); _ => None },
    identity=e => match e { Moved(id~, ..) | Reserved(id~, ..) => Some(id); _ => None },
    histories=[history_with_reversal],
  )
}
```

The compiled version is in [tutorial part 6](/tutorial/06-dynamic-consistency-boundaries#reversals).

## Not covered yet

- Partial reversals (reverse part of an amount): model them as a new entry plus a reversal of the original.
- Reversing a reversal: allowed by the shape; the second reversal names the first.
- Closing a period with open corrections: the closing event should carry the list of open reversals; see
  [Closing the books](/concepts/closing-and-snapshots).
