# Deciders

A domain in Strata is a `Decider[C, E, S, N]`: a category, an initial state, `decide`, `evolve`, and optionally
`advise`, `tags` and `is_terminal`. This page explains why it is shaped that way; [tutorial part 1](/tutorial/01-your-first-decider)
shows how to write one.

## Deciders, not aggregates

There is no base class, no `apply` method to override, no lifecycle. A decider is a value built with labelled
arguments:

```moonbit
pub let account : @strata.Decider[AccountCmd, AccountEvent, Account, Unit] = @strata.Decider(
  category="account",
  initial={ owner: None, balance: 0, closed: false },
  decide=(cmd, s, env) => match (cmd, s) { ... },
  evolve=(s, e) => match e { ... },
  is_terminal=s => s.closed,
)
```

This is the functional formulation that the F# and TypeScript event sourcing communities converged on, and it fits
MoonBit better than it fits either of those: enums give you the closed event set, `raise` gives you typed rejection,
and immutability makes `evolve` a fold with no aliasing questions. The table of *what is rejected and what is
recorded* that you drew on the whiteboard is the `match` in `decide`.

## The pieces

| Piece | Type | Role |
|---|---|---|
| `category` | `String` | prefix of the stream name; `account` + `acc-1` is `account-acc-1` |
| `initial` | `S` | the state of an empty stream |
| `decide` | `(C, S, Env) -> Array[E] raise` | what is recorded, or why not |
| `evolve` | `(S, E) -> S` | fold one event into state |
| `advise` | `(C, S, Env) -> Array[N]` | what the caller should know; see [Advice](/tutorial/05-advice) |
| `tags` | `(E) -> Array[Tag]` | the boundaries and views an event belongs to; see [Selections](/concepts/selections) |
| `is_terminal` | `(S) -> Bool` | states that accept no further commands |

`Decider[C, E, S, N]` always names its notice type; a decider without advice uses `Unit`. Because the struct is
readonly and constructed through a function with labelled arguments, Strata can add capabilities in a minor release
without breaking a call site.

## Two kinds of domain, one shape

Some domains are *guard-first*: a bank account rejects an overdraft, and `decide` is the gatekeeper. Others are
*record-first*: an expense system records the overspend, flags it, and leaves the judgement to a person, and `decide`
rarely raises at all. Most real systems are both, in different places.

Strata gives one shape to both. `decide` answers exactly one question and stays two-valued. `advise` runs beside it
over the same command and state and answers a different one. Notices are returned in the `Outcome`, never appended to
the log, and never able to block. Keeping the two apart keeps `decide` provable and keeps the log honest: a warning
is a derivation, and derivations do not belong in the source of truth.

## Why `raise` and not `Result`

`raise` is checked and cheap, and it lets `decide` say what can go wrong in its signature without wrapping every
return. Domain rejections are your own `suberror`s and propagate unchanged through the runtime. Where you want a
value, `try ... catch` gives you one; `@testing.spec` and `Preview` return `Result` for exactly this reason.

## What a decider can do on its own

`replay(events)` folds a history; `replay_from(state, events)` continues from a snapshot; `run(cmd, state, env)`
executes `decide` and `advise` together and returns a `Decision { events, notices }`. Specs, `Preview` and the
runtime are all built on these three, which is why a rule tested in a spec is the rule the server runs and the rule
the browser previews.

## Terminal states

`is_terminal` lets the runtime reject commands on a closed stream right after the fold, before `decide` runs, with
`StreamTerminal`. Reach for it before you reach for snapshots: a closed account or a closed period is the natural end
of a stream. See [Closing the books and snapshots](/concepts/closing-and-snapshots).

## DcbDecider

`DcbDecider` is the same shape for invariants that cross streams: it adds `stream`, `scope` and `tags` as required
arguments, and `decide`, `evolve` and `advise` receive a `Scope`. See [Consistency boundaries](/concepts/consistency-boundaries).
