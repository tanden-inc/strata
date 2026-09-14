# Read models

A read model is a fold over events. Write the fold once; choose where and how often it runs.
[Tutorial part 4](/tutorial/04-read-models) walks through the compiled examples; this page explains the shapes and
the lifecycles.

## Three shapes

**A view over one selection.** `Projection(initial~, apply~)` with `apply : (V, E) -> V`. Folds one stream (`rt.live`)
or any selection (`rt.fold`).

**A keyed view that fans out.** One event often belongs to several rows: a transfer touches the source and the
destination. `KeyedProjection(keys~, initial~, apply~)`: `keys` returns every key the event contributes to, and
`apply` receives the key so each row can interpret the event from its own point of view. Keyed projections receive the
full `Recorded[E]`, because rows frequently want `recorded_at`, `meta.actor`, or `id`. `rt.fold_keyed` returns a
`Map[K, R]`.

**A view over several sources.** Cross-cutting screens, everything pending, projected landing balances, need events
from more than one category. `MultiProjection(initial~)` with `..source(selection, apply)` per source, each with its
own typed `apply`; Strata merges them in global position order. No wrapper enum. `rt.fold_multi` folds it on read.

Merging sources by global position is well-defined because there is one log with one `Position`. That is a
definition, not a limitation Strata intends to lift: if you split an application across stores, you need a merge with
its own ordering semantics, which is a different tool.

## Three lifecycles

```moonbit
// Live: fold on read. No cache, always current.
let (view, version) = rt.live(balance_view, category="account", id="acc-1")
let ledger = rt.fold_keyed(code_ledger, Selection::tags([Tag("period:2026-09")]))

// Inline: updated in the same append as the events. Strongly consistent.
let accounts = rt.handler(account, inline=[@rt.inline(balance_view, into="balances")])

// Async: a subscription with a checkpoint. Scales; eventually consistent.
let daemon = rt.projector("landing", landing, into="landing")
@async.with_task_group(g => { daemon.start(g); serve(g) })
```

| | Consistency | Cost per read | Cost per write | Use when |
|---|---|---|---|---|
| Live | always current | a fold | none | the stream is short or the read is rare |
| Inline | same append as the write | a row lookup | a row write in the append | a screen must reflect the write immediately |
| Async | eventually; `wait_for(position)` to catch up | a row lookup | none on the write path | many sources, heavy folds, or fan-out |

Rows live in the store's `ViewStore` (`rt.views()`), keyed by table name and row key. The PostgreSQL store keeps them
in the same database so inline writes share the append's transaction.

## Effectively-once

Async projectors are at-least-once. Because `apply` is pure and the view rows are committed together with the
checkpoint in one `ViewStore::commit` ([ADR 0005](/adr/0005-atomic-read-side-commit)), the result is
effectively-once without any dedup code. `Projector::rebuild()` replays into a fresh table and swaps it in
(`ViewStore::swap`); read models are disposable by design. `wait_for(position, timeout~)` blocks until the projector
has passed a position, the piece an API layer needs to return a freshly updated view after a write, and raises
`WaitTimeout` otherwise.

## Fat or thin events

A **thin** event records only what changed (`Accepted(by~)`); a **fat** event copies the context a consumer will need
(`Accepted(by~, request~ : RequestSnapshot)`).

| | Thin | Fat |
|---|---|---|
| Log honesty | high: only facts | lower: derived data is repeated |
| Consumer convenience | needs the writer's state | self-contained |
| Schema evolution | few fields to upcast | copied fields must evolve everywhere |
| Storage | small | larger |

Strata supports both:

- Thin events plus `Runtime::state_at(decider, recorded)`: a deterministic replay of the writer's stream up to the
  event's version. It is `async`, so it is available to **reactors** and to code that runs after a read, not inside a
  pure projection `apply`.
- Fat events when a **projection** needs the context: projections are pure folds and cannot call `state_at`.

Rule of thumb: keep events thin when the consumer is a reactor or an API handler. Make an event fat when a read model
needs the context and the copied data is genuinely part of the fact ("accepted *this* request as it was at that
moment").

## Forgotten subjects

When `rt.forget` destroys a subject's key ([Sealing and shredding](/concepts/sealing-and-shredding)), projectors are
told through `Projector::on_forgotten(f)`, which is where you drop your own copies of the redacted data.
