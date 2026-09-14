# ADR 0001: the event store is a trait, not a virtual package

Date: 2026-09-14. Status: accepted.

## Context

The README described build-time store selection through a MoonBit virtual package. The only virtual package in the
standard library (`moonbitlang/core/abort`) exposes a single function; we found no example of a virtual package whose
interface is a type with methods, and could not verify the semantics for one.

## Decision

`@store.EventStore` is a `pub(open) trait` with async methods. `Runtime::Runtime` is generic over the trait
(`fn[St : EventStore]`) and stores the implementation as `&EventStore`. `MemoryStore` is the default implementation;
PostgreSQL will be `store/pg`.

## Consequences

- Swapping the store is one argument: `Runtime(@store_pg.PgStore::connect(url))`.
- Dispatch is dynamic per store call; negligible against a database round-trip.
- Build-time selection can still be added later as a thin virtual package that returns `&EventStore`.
