# Reversals

*Design note. Status: decided for 0.1.*

Stored events are never deleted or edited. A mistake is corrected by recording that it was a mistake.

## Shape

- A reversal names its target by `EventId`. This is why decisions receive `env.ids`: an entry must have an id at the
  moment it is recorded so that it can be named later.
- A reversal **carries its target's tags** (`Reversed(of~, tags~, ...)`), so it lands inside the same consistency
  boundaries and the same views as the thing it reverses.
- Tags are computed from the event alone (`tags=` on the decider). A tag that depended on state would make the boundary
  depend on who was looking.

## Law

`@testing.reversal_law` / `@testing.dcb_reversal_law` check, for every history given:

1. `tags(reversal) ⊇ tags(target)`;
2. optionally (`restores=`), that the state after the reversal relates to the state before the target as the domain
   says it should.

## Not covered yet

- Partial reversals (reverse part of an amount): model them as a new entry plus a reversal of the original.
- Reversing a reversal: allowed by the shape; the second reversal names the first.
- Closing a period with open corrections: the closing event should carry the list of open reversals; see the ledger example.
