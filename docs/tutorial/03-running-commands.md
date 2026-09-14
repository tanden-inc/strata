# 3. Running commands

The decider is pure. Everything effectful, reading a stream, folding it, calling `decide`, appending with the version
that was read, lives in `@rt.Runtime`. This part runs the account through it.

## A runtime and a handler

`Runtime` wraps any `EventStore`. `MemoryStore` is the default implementation; in tests, `@testing.runtime()` builds
one with a fixed clock and sequential event ids so snapshots stay stable. `handler(decider)` returns a
`CommandHandler` for one decider.

<<< @/../examples/account/account_test.mbt#execute

Every `execute` does the same four steps: read the stream, fold it with `evolve`, call `decide` (and `advise`), append
the events under the version that was read. The `Outcome` it returns carries:

| Field | Meaning |
|---|---|
| `events : Array[Recorded[E]]` | what was appended, with ids, positions, tags and metadata |
| `notices : Array[N]` | [advice](/tutorial/05-advice); empty for a decider without it |
| `version : Int` | the stream version after the append; hand it out as an `ETag` |
| `position : Position` | the global log position; what async read models chase |
| `deduplicated : Bool` | whether this was an idempotent replay (below) |

Outside a test the runtime is constructed the same way, with a real clock and ULID ids by default:

```moonbit
let rt = @rt.Runtime(@store.MemoryStore())
// or, pinned for a replay:
let rt = @rt.Runtime(store, clock=@rt.Clock::parse_fixed("2026-09-13T00:00:00Z"))
```

## Context: who is asking

`execute` takes a `Context`: the actor, optionally a tenant, correlation and causation ids, an idempotency key and
flags. The runtime derives the `Env` that `decide` sees from it, and stores the rest as metadata on every event. You
supply one thing; the domain and the audit trail each get their part.

## Rejections propagate unchanged

A domain rejection is your `suberror`, raised by `decide`, and it arrives at the caller as the same value. Nothing is
wrapped.

<<< @/../examples/account/account_test.mbt#rejection

## Optimistic concurrency

The append carries the version the handler read, so a concurrent writer causes an `AppendConflict::StreamConflict`
rather than a lost update. Clients can take part: pass the version they last saw as `expected=Exact(n)`, and the store
enforces it. `ExpectedVersion` is `Any | NoStream | Exact(Int)`; `NoStream` means "create only", which is how you make
ids unique without a lookup table.

<<< @/../examples/account/account_test.mbt#conflict

Because `decide` is pure, "read again and re-decide" is always safe, so retrying on conflict is a declaration rather
than code. Retry applies to conflicts only; domain rejections are never retried:

<<< @/../examples/account/v1_test.mbt#retry

## Idempotency

Networks retry and reactors redeliver, so the same command will arrive twice. Pass an `idempotency_key` (or set it on
the `Context`) and a repeat returns the original outcome, marked `deduplicated`, without appending anything. The key is
stored in event metadata; there is no extra table.

<<< @/../examples/account/account_test.mbt#idempotency

A *different* command under a known key raises `IdempotencyConflict::KeyReused`. Reactors set the key automatically
from the event they react to ([part 7](/tutorial/07-reactors)), so in practice you only think about it at the API
boundary. The full rules are in [ADR 0004](/adr/0004-idempotency).

## Terminal streams

When `is_terminal` says a state accepts no more commands, the runtime rejects further commands right after the fold,
without calling `decide`:

<<< @/../examples/account/account_test.mbt#terminal

## Tenants

A tenant on the `Context` becomes a prefix of the stream name and a `$tenant:` system tag, so reads and read models
scoped to one tenant never see another's events:

<<< @/../examples/account/v1_test.mbt#tenant

## Loading state directly

`handler.load(id, tenant?)` returns the current state and version without running a command, which is what an API
layer needs for a conditional read.

## Next

[Part 4](/tutorial/04-read-models) folds the events this handler records into views: live, inline, and asynchronous.
