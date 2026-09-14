# Closing the books and snapshots

Streams and tags that grow forever, accounts, root cost codes, are closed per period, the way accountants have always
done it. The closing event carries the summary; the next period opens with it, and the period becomes part of the
stream name or the tag set.

```moonbit
(ClosePeriod(next~), { period: Some(p), .. }) =>
  [PeriodClosed(period=p, closing_balance=s.balance, next~, by=env.actor)]

// DCB: put the period in the scope so the selected set stays bounded
scope=cmd => Selection::tags([Tag("code:\{cmd.code}"), Tag("period:\{cmd.period}")])
```

A reactor opens the next period with `expected=NoStream`, so a redelivered close cannot open it twice. `is_terminal`
lets the runtime reject commands on a closed stream right after the fold, before `decide` runs. Reach for this before
you reach for snapshots.

## Snapshots

Snapshots are a cache of state, never the truth. They live beside the log (`EventStore::load_snapshot` /
`save_snapshot`), carry a version stamp so you can invalidate them by changing one number, and work for both kinds of
decider:

```moonbit
let accounts = rt.handler(account, snapshot=@rt.SnapshotPolicy::every(200, version=3))
let codes    = rt.dcb_handler(ledger, snapshot=@rt.SnapshotPolicy::every(500, version=1))
```

`SnapshotPolicy::every(n, version~)` saves a snapshot every `n` events; `SnapshotPolicy::never()` is the default. The
key is `SnapshotKey::Stream(stream, version~)` for a stream decider and `SnapshotKey::Dcb(selection, version~)` for a
DCB decider, where the selection is the normalised scope, which is why `Selection` has set semantics. A different
`version` is a different key, so bumping it after changing `evolve` discards stale state without deleting anything.

The DCB boundary holds on the snapshot path: the handler reads the log head before the snapshot and the tail, so a
competing in-scope write between them still surfaces as a `BoundaryConflict`.

`@testing.replay_law` is the property snapshots depend on: replaying a history equals replaying a prefix and
continuing from the resulting state with `replay_from`.
