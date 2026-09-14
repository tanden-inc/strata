# Architecture

```
            commands (+ Context)                                      selections
                    │                                                     │
       ┌────────────▼─────────────┐                    ┌──────────────────▼──────────────────┐
       │  CommandHandler          │                    │  read(sel) · fold(view, sel)         │
       │  reserve ids → read(scope)│                   │  live(view, id) · wait_for(position) │
       │  → replay → decide/advise│                    │  Projection · KeyedProjection        │
       │  → append(condition, es) │                    │  MultiProjection(..)..source(sel)    │
       └────────────┬─────────────┘                    └──────────────────▲──────────────────┘
                    │  Stream(id, version) | Dcb(selection, after)        │ subscribe(sel, from)
       ┌────────────▼─────────────────────────────────────────────────────┴───────────────────┐
       │                          EventStore  (trait)                                         │
       │             MemoryStore (default) │ postgres (native, planned) │ js host (planned)     │
       └───────────────────────────────────────────────────────────────────────────────────────┘
                    ▲
                    │ Recorded[E]   (+ state_at, unseal)
       ┌────────────┴─────────────┐
       │  reactor(source=sel)     │──── commands (r.caused()) ────▶ other handlers
       │  process managers        │──── integration events ───────▶ outside world
       └──────────────────────────┘

  pure (any target, incl. browser): core, codec, Preview
  async (native, js, wasm): store, runtime, testing; later http, graphql
```

## Packages

| Package | Import alias | Effects | Targets | Contents |
|---|---|---|---|---|
| `strata/core` | `@strata` | none | all | `Decider`, `DcbDecider`, `Env`, `IdBatch`, `Scope`, `Selection`, `Projection`, `KeyedProjection`, `MultiProjection`, `Recorded`, `Context`, `Outcome`, `AppendCondition`, `Preview`, ids and time |
| `strata/codec` | `@codec` | none | all | `JsonCodec`, `TagStyle`, `Upcast`, shredding and sealing declarations |
| `strata/store` | `@store` | `async` | native, js, wasm | `EventStore`, `Subscription`, `ViewStore`, `KeyStore` traits; `MemoryStore` |
| `strata/store/pg` | `@store_pg` | `async` | native (planned) | PostgreSQL adapter, tag index, inline views, key store |
| `strata/runtime` | `@rt` | `async` | native, js, wasm | `Runtime`, handlers, `read`/`fold`/`live`, projectors (`wait_for`, `rebuild`), reactors, `state_at`, `unseal`, snapshots, retry, clock |
| `strata/testing` | `@testing` | mixed | native, js, wasm | `spec`, `dcb_spec`, laws, `Fixtures`, `contract`, `runtime()` test harness, generators |
| `strata/http` | | `async` | planned | `Context::from_http`, `If-Match`/`ETag`, cursors, error mapping |
| `strata/graphql` | | `async` | planned | context, result unions, connections over `Selection`, subscriptions, `gen graphql` |

Dependency direction is strictly `core <- codec <- store <- runtime <- testing`. `core` and `codec` must keep
compiling for `wasm-gc` and never import `moonbitlang/async`.

## The command path

1. The handler reserves an `IdBatch` from the runtime's `IdGenerator`, so `decide` can name the events it is about to
   emit (`env.ids.at(i)`).
2. It reads the stream (or, for a DCB handler, the log head and then the scope's selection) and replays it with
   `evolve`, starting from a snapshot when a policy is configured.
3. If `is_terminal` holds, it raises `StreamTerminal` without deciding.
4. It calls `decide`; on success it calls `advise`.
5. It encodes the events with the codec, attaches the `Context` as metadata and the decider's `tags`, and appends
   under `Stream(id, version)` or `Dcb(selection, after)`, with any inline view writes in the same append.
6. On `AppendConflict`, if a `Retry` policy is set, it goes back to step 2.

## The read path

`read` returns a `Page` of stored events after a position, in global order. `fold`, `fold_keyed`, `fold_multi` and
`live` decode and fold. `subscribe` returns a `Subscription` that `next()`s batches from a position; projectors and
reactors are built on it, checkpoint through the store, and are started as tasks in a `moonbitlang/async` task group.

## Stores

Any type that implements `EventStore` (and `ViewStore` for inline read models) can be passed to `Runtime`. Run
`@testing.contract(make=...)` against it; the twenty-one cases cover append semantics, expected versions, DCB
conditions, selection semantics, subscription ordering, idempotency, checkpoints, snapshots and atomic inline writes.
See [Stores and targets](/introduction/status-and-stability#stores-and-targets).
