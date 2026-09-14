# Quickstart

This page is the whole loop in sixty seconds: define a domain, test it without a database, run it against the
in-memory store. Every block is lifted from [`examples/account`](https://github.com/tanden-inc/strata/tree/main/examples/account),
which `moon test` compiles and runs.

## Define the domain

Events are facts, commands are intents, state is a fold, and rejections are a `suberror`.

<<< @/../examples/account/account.mbt#events

<<< @/../examples/account/account.mbt#commands

<<< @/../examples/account/account.mbt#state

<<< @/../examples/account/account.mbt#errors

The `Decider` ties them together. `decide` answers exactly one question, *what is recorded, or why not*; `evolve` folds
an event into the state; `is_terminal` tells the runtime when a stream accepts no further commands.

<<< @/../examples/account/account.mbt#decider

Two things to notice. Nothing here is `async` and nothing takes a store: `decide` cannot call a clock or a database
because its type does not allow it. And the actor comes in through `env`, not through the command, because *who* is a
fact about the invocation rather than about the intent. Both are explained in
[Environment, identity, and time](/concepts/environment-identity-and-time).

## Test it without a database

`@testing.spec` is Given/When/Then over plain values. Expected values are snapshots, so `moon test --update` writes
them and you review them as a diff.

<<< @/../examples/account/account_test.mbt#spec-basic

## Run it

`@rt.Runtime` wraps any `EventStore`. It reads the stream, folds it with `evolve`, calls `decide`, and appends with the
version it read. The in-memory store is the default; `@testing.runtime()` is the same thing with a fixed clock and
sequential event ids so that snapshots stay stable.

<<< @/../examples/account/account_test.mbt#execute

Outside a test, the same code is:

```moonbit
async fn main {
  let rt = @rt.Runtime(@store.MemoryStore())
  let accounts = rt.handler(account)
  let ctx = @strata.Context(actor=@strata.Actor("user:alice"))
  accounts.execute("acc-1", Open, ctx~) |> ignore
  let out = accounts.execute("acc-1", Deposit(amount=100), ctx~)
  println("v\{out.version}: \{Repr(out.events.map(r => r.event))}")
}
```

Switching to another store means passing another `EventStore` implementation to `Runtime`; nothing above changes.

::: warning Planned
The PostgreSQL store (`tanden-inc/strata/store/pg`) is a skeleton whose methods raise `NotImplemented`. It is the
first item under *Promises without code* in the [roadmap](/ROADMAP).
:::

## Where next

- The [tutorial](/tutorial/01-your-first-decider) builds this domain up step by step, then moves to a ledger with
  advice, dynamic consistency boundaries and reversals.
- [Why Strata](/introduction/why-strata) explains what the library is reacting against.
- The [reference](/reference/core) lists every public type and function.
