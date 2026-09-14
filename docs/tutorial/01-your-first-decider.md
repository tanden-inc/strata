# 1. Your first decider

This tutorial builds a bank account, then a budget ledger, one Strata idea at a time. Every code block is imported
from [`examples/account`](https://github.com/tanden-inc/strata/tree/main/examples/account) or
[`examples/ledger`](https://github.com/tanden-inc/strata/tree/main/examples/ledger), which `moon test` compiles and
runs, so what you read here is what actually executes.

In this part you write the whole write model of an account: four types and one value.

## Events are facts

An event records something that happened. Events are a closed enum, derive `ToJson`/`FromJson` because the derived
JSON *is* the stored format, and carry the actor where the domain cares who did it.

<<< @/../examples/account/account.mbt#events

## Commands are intents

A command says what someone wants. It does not say who or when: those are facts about the invocation, and they arrive
separately (see [part 3](/tutorial/03-running-commands) and
[Environment, identity, and time](/concepts/environment-identity-and-time)).

<<< @/../examples/account/account.mbt#commands

## State is a fold

State is an immutable value. It is never constructed by hand in production; it is always the result of folding events
over an initial value.

<<< @/../examples/account/account.mbt#state

## Rejections are typed

What can go wrong is a `suberror`. Checked errors let `decide` say what can be rejected in its signature, and a
rejection propagates to the caller as a value they can match on.

<<< @/../examples/account/account.mbt#errors

## The decider

`Decider(...)` ties the four together. Three arguments are required: `category` (the prefix of the stream name, so
account `acc-1` lives in stream `account-acc-1`), `initial`, `decide` and `evolve`. `is_terminal`, `advise` and `tags`
are optional.

<<< @/../examples/account/account.mbt#decider

Read `decide` as the table you would draw on a whiteboard: for each command and state, *what is recorded, or why
not*. Each arm either returns the events to append or raises a rejection. `evolve` is the fold: given a state and one
event, produce the next state. `is_terminal` marks states that accept no further commands, so the runtime can reject
them without calling `decide` at all.

Three properties follow from the types alone:

- **No effects.** `decide` is `(C, S, Env) -> Array[E] raise`. It is neither `async` nor given a store, so it cannot
  read a clock, generate an id, or query a database. The runtime supplies those facts as values in `env`.
- **Exhaustiveness.** Events are a closed sum. When you add a variant, every `evolve` and every read model's `apply`
  that forgot it fails to compile.
- **Portability.** `strata/core` compiles to native, JavaScript and `wasm-gc`, so this exact value can run in the
  browser to [preview](/concepts/preview) a command before it is sent.

## What the decider gives you

Because a `Decider` is a value, its pieces are callable directly. `replay` folds a history into a state,
`replay_from` continues from a snapshot, and `run` executes `decide` and `advise` together:

```moonbit
let state = account.replay([Opened(owner=alice), Deposited(amount=50, by=alice)].iter())
// state == { owner: Some(alice), balance: 50, closed: false }
let decision = account.run(Withdraw(amount=20), state, env)   // Decision { events, notices } or raises
```

You rarely call these yourself. [Specs](/tutorial/02-specs), [`Preview`](/concepts/preview) and the
[runtime](/tutorial/03-running-commands) are all built on them.

## Next

[Part 2](/tutorial/02-specs) tests this decider without a database, a runtime, or `async`.
