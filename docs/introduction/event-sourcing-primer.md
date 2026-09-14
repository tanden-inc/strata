# Event sourcing in one page

This page is for readers who know MoonBit but have not built an event-sourced system. It defines the handful of words
the rest of the documentation uses.

## The log is the truth

A conventional application stores *current state* and overwrites it. An event-sourced application stores *what
happened*, as an append-only log of **events**, and derives current state from it. `Deposited(amount=100)` followed by
`Withdrawn(amount=30)` is the record; a balance of 70 is a consequence.

Because nothing is overwritten, the log answers questions state cannot: what was the balance last Tuesday, who
changed it, in what order, and why. Corrections are new events, not edits.

## Commands, decisions, state

A **command** is a request: `Withdraw(amount=80)`. Handling it means deciding whether it is allowed, given what has
happened so far, and if so which events to record. In Strata that decision is a pure function called a
[`Decider`](/concepts/deciders):

- `evolve : (S, E) -> S` folds one event into the **state**; replaying a stream is `events.fold(evolve, initial)`.
- `decide : (C, S, Env) -> Array[E] raise` maps a command and the current state to new events, or raises a typed
  rejection.

Everything effectful, reading the log and appending to it, is outside the decider.

## Streams and optimistic concurrency

Events are grouped into **streams**, one per entity: account `acc-1` has stream `account-acc-1`. Each event in a
stream has a **version**. A writer reads a stream at version *n* and appends "at version *n*"; if someone else got
there first, the append fails and the writer re-reads and re-decides. This is optimistic concurrency, and because the
decider is pure, retrying is always safe.

Some invariants span entities: moving budget between two codes must not create money. A **dynamic consistency
boundary** lets a command declare the set of events it depends on (a [selection](/concepts/selections), not a stream)
and fails the append if that set changed. See [Consistency boundaries](/concepts/consistency-boundaries).

## Read models

State folded from one stream is enough to *decide*, but not to *browse*. A **read model** (or projection) is another
fold, shaped for a screen or a query: all pending items, a balance per code, a board across categories. Read models
are derived data and therefore disposable: drop one, replay the log, and it is back. They can be computed on read,
updated in the same transaction as the write, or maintained asynchronously by a process that follows the log.

## Reactors

Some events should *cause* something: send an email, issue a command to another stream, publish to a broker. A
**reactor** follows a selection of the log and runs an effect per event. Because delivery is at-least-once, reactors
are written to be idempotent; Strata makes that mostly automatic.

## Schema evolution

Events written five years ago are still in the log, in the shape they had then. Rather than rewriting them, the
application **upcasts** old shapes to the current one when it reads them.

## Where Strata fits

Strata gives each of these a type: `Decider`, `Selection`, `Projection`, `Reactor`, `JsonCodec`. What it adds beyond
the textbook pattern is [advice](/tutorial/05-advice) beside decisions, one selection vocabulary for reads and
boundaries alike, and a compiler that checks the parts other ecosystems leave to runtime reflection. Start with
[Why Strata](/introduction/why-strata) or the [Quickstart](/guide/quickstart).
