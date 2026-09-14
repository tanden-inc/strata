---
layout: home

hero:
  name: Strata
  text: Event sourcing for MoonBit
  tagline: Where the type checker does the bookkeeping. Describe a domain as plain enums and pure functions; Strata takes care of persistence, concurrency, idempotency, read models, process managers and schema evolution.
  image:
    src: /strata.svg
    alt: Strata
  actions:
    - theme: brand
      text: Get started
      link: /guide/quickstart
    - theme: alt
      text: Why Strata
      link: /introduction/why-strata
    - theme: alt
      text: GitHub
      link: https://github.com/tanden-inc/strata

features:
  - icon: ✍️
    title: Writes are decisions
    details: A Decider turns a command and a state into events or a typed rejection. It is a pure function by construction, so it compiles to native, JavaScript and WebAssembly unchanged.
    link: /concepts/deciders
    linkText: Deciders
  - icon: 💬
    title: Most decisions are to record
    details: Beside the decision, a Decider can offer advice — warnings and forecasts computed from the same state, returned to the caller, never persisted. Inform without blocking.
    link: /tutorial/05-advice
    linkText: Advice
  - icon: 🔎
    title: Reads are selections
    details: Every read model, reactor and consistency boundary is expressed with one Selection type — a stream, a category, a set of tags, or a combination — so the read side is as expressive as the write side.
    link: /concepts/selections
    linkText: Selections
---

## One value is your entire aggregate

The account decider below is the whole write model for a bank account: what is rejected, what is recorded, and how
state is folded from the record. There is no base class, no lifecycle, and no `async`. It is compiled and tested in
[`examples/account`](https://github.com/tanden-inc/strata/tree/main/examples/account).

<<< @/../examples/account/account.mbt#decider

Everything else on this site is about what Strata does with that value: [running it](/tutorial/03-running-commands)
against a store with optimistic concurrency and idempotency, [folding read models](/tutorial/04-read-models) from the
events it records, [reacting](/tutorial/07-reactors) to them, guarding invariants that cross streams with
[dynamic consistency boundaries](/tutorial/06-dynamic-consistency-boundaries), and
[evolving the schema](/tutorial/08-schema-evolution) without rewriting the log.

::: tip Status
The 0.1 interface of `core`, `codec`, `store` (in-memory), `runtime` and `testing` is implemented and green. The
PostgreSQL store, sealing encryption, HTTP and GraphQL adapters are planned; see
[Status and stability](/introduction/status-and-stability) and the [roadmap](/ROADMAP).
:::
