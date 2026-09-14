# ADR 0003: identifiers, time, and system tags

Date: 2026-09-14. Status: accepted.

## Identifiers

- `EventId` is an opaque string; the runtime mints ULIDs, tests use `evt-0001`. The type does not enforce the shape.
- The runtime reserves an `IdBatch` before calling `decide`; `env.ids.at(i)` is the id of the i-th emitted event.

## Time

The standard library has no instant type; `moonbitlang/x/time` is comprehensive but fallible in every operation and
has no JSON form. Strata defines `Instant` (unix milliseconds, ISO-8601 in JSON) and `Duration` (milliseconds) in
`core`, and keeps the `Clock` in `runtime`.

## System tags

Streams, categories and tenants are expressed as tags the **store** writes on every event:
`$stream:<name>`, `$category:<name>`, `$tenant:<t>`. One `Selection` type and one tag index therefore serve reads,
subscriptions and DCB boundaries. User code cannot create `$` tags (`NewEvent` raises `InvalidTag`);
`Recorded.tags` shows user tags only, `StoredEvent.tags` shows all. `Selection` constructors normalise their input
so equal sets are equal values (snapshot and checkpoint keys rely on this).
