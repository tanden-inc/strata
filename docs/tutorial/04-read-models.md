# 4. Read models

A read model is a fold over events. In Strata you write the fold once, as a pure value, and then choose where and how
often it runs. This part covers the three shapes of projection and the three places they can run.

## A projection over one selection

`Projection(initial~, apply~)` is the simplest read model: a value and a function from value and event to value. The
account example keeps a balance and a transaction count.

<<< @/../examples/account/account.mbt#view

Because it is a value, it folds anywhere, including in a plain test:

<<< @/../examples/account/account_test.mbt#view-fold

## Where it runs: live

`rt.live(view, category~, id~)` folds one stream on read and returns the stream version alongside the value, ready to
be an `ETag`. No cache, always current.

<<< @/../examples/account/account_test.mbt#live

`rt.fold(view, selection)` is the same over any [selection](/concepts/selections): a category, a set of tags, or the
whole log.

## Where it runs: inline

An inline projection is updated in the same append as the events, so it is strongly consistent with the write. Pass
it to the handler with `inline=[@rt.inline(view, into="table")]`; rows land in the store's `ViewStore`, keyed by table
and entity id. (The `counter` decider used in the runtime's own tests is a two-line domain: `Add(n)` records
`Added(n)` and the state is the sum.)

<<< @/../runtime/runtime_test.mbt#counter

<<< @/../runtime/runtime_test.mbt#inline

## Where it runs: async

An asynchronous projector subscribes to a selection from a checkpoint and folds in the background. It scales, and it
is eventually consistent. `Projector::start(group)` runs it as a task in a `moonbitlang/async` task group, so shutdown
is automatic; `wait_for(position, timeout~)` blocks until the projector has passed a position, which is how an API
layer returns a freshly updated view right after a write.

<<< @/../runtime/runtime_test.mbt#projector

Async projectors are at-least-once. Because `apply` is pure and the view rows are committed together with the
checkpoint (`ViewStore::commit`, [ADR 0005](/adr/0005-atomic-read-side-commit)), the result is effectively-once with no
dedup code. `rebuild()` replays into a fresh table and swaps it in: read models are disposable by design.

The projector above takes a `MultiProjection`, the multi-source shape described next; for a keyed projection use
`rt.projector_keyed(name, keyed, source~, into~)`.

## A keyed projection that fans out

One event often belongs to several rows: a move between two budget codes touches both. `KeyedProjection` returns
every key an event contributes to, and `apply` receives the key so each row interprets the event from its own point
of view. Keyed projections receive the full `Recorded[E]`, because rows frequently want `recorded_at`, `meta.actor`
or `id`.

<<< @/../examples/ledger/ledger.mbt#keyed

<<< @/../examples/ledger/ledger_test.mbt#keyed-fold

Through the runtime, `rt.fold_keyed(keyed, selection)` returns the map of rows for any selection.

## A view over several sources

Cross-cutting screens need events from more than one category. `MultiProjection` declares each source with its own
typed `apply`, and Strata merges them in global position order. There is no wrapper enum.

```moonbit
let board = @strata.MultiProjection(initial=Board::empty())
board.source(@strata.Selection::category("code"), (v, r : @strata.Recorded[CodeEvent]) => v.apply_code(r))
board.source(@strata.Selection::category("ledger"), (v, r : @strata.Recorded[LedgerEvent]) => v.apply_ledger(r))

let now = rt.fold_multi(board)                         // fold on read
let daemon = rt.projector("board", board, into="board") // or chase the log
```

Merging by global position is well defined because there is one log with one `Position`. If you split an
application across stores you need a merge with its own ordering semantics, which is a different tool.

## Fat or thin events

Thin events keep the log honest but leave consumers without details; fat events copy context into the fact. A
projection's `apply` is pure and cannot look anything up, so a read model that needs context needs a fat event. A
reactor or an API handler can instead ask the runtime for the writer's state as it stood when the event was recorded:

<<< @/../runtime/runtime_test.mbt#state-at

[Concepts: Read models](/concepts/read-models) discusses when each wins.

## Next

[Part 5](/tutorial/05-advice) adds a second pure function beside `decide`, for domains where the right answer is to
record and warn rather than refuse.
