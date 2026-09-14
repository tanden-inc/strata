# Stored format

This is the on-disk contract: what an `EventStore` holds for each event, and how the pieces are derived. It is part of
the surface that is stable at 1.0.

## One event

| Column (`StoredEvent` field) | Type | Written by | Notes |
|---|---|---|---|
| `id` | `EventId` | runtime | a ULID from `IdGenerator::ulid()`; `evt-0001` in tests. Opaque string; shape not enforced. |
| `position` | `Position` | store | global, strictly increasing, gapless in the memory store |
| `stream` | `StreamId` | runtime | `category-id`, or `tenant/category-id` |
| `version` | `Int` | store | 1-based within the stream |
| `event_type` | `String` | codec | extracted from `data` per `TagStyle`; a denormalised column for indexing |
| `schema` | `Int` | codec | the codec's `schema_version` at write time |
| `data` | `Json` | `derive(ToJson)` | the whole derived value; the codec adds nothing |
| `tags` | `Array[Tag]` | decider + store | the decider's `tags` plus the system tags below |
| `meta` | `Metadata` | runtime | from the `Context` |
| `recorded_at` | `Instant` | runtime | from the `Clock` |

## Payload layouts

`TagStyle::Flat` (the `derive(ToJson)` default):

```json
["Deposited", { "amount": 100, "by": "user:alice" }]
"Closed"
```

`TagStyle::Legacy(tag_key="$tag")` (`derive(ToJson(style="legacy"))`):

```json
{ "$tag": "Deposited", "amount": 100, "by": "user:alice" }
{ "$tag": "Closed" }
```

Identifier newtypes are plain scalars in JSON: `EventId`, `StreamId`, `Actor`, `Tag` as strings, `Position` and
`Duration` as numbers, `Instant` as an ISO-8601 string (`"2026-09-13T00:00:00.000Z"`). See
[ADR 0002](/adr/0002-json-layout).

## Metadata

```json
{
  "correlation_id": "req-7f3a",
  "causation_id": "01J...",
  "actor": "user:alice",
  "tenant": "t1",
  "idempotency_key": "req-7f3a",
  "extra": {}
}
```

Every field except `extra` is optional. The idempotency key is indexed by the store (`find_idempotent`).

## System tags

The store writes three tags on every event; user code cannot create tags starting with `$`.

| Tag | Example | Drives |
|---|---|---|
| `$stream:<name>` | `$stream:account-acc-1` | `Selection::stream` |
| `$category:<name>` | `$category:account` | `Selection::category` |
| `$tenant:<t>` | `$tenant:t1` | `Selection::category(.., tenant~)` and tenant isolation |

`Recorded.tags` shows only the event's own tags; `StoredEvent::user_tags()` strips the system ones. See
[ADR 0003](/adr/0003-ids-time-and-system-tags).

## System events

The runtime appends marker events with a `$strata.` type prefix. `JsonCodec::decode` returns `None` for them, so
folds and projections never see them; `is_system_event_type` recognises them.

| Type | Appended by | Payload |
|---|---|---|
| `$strata.forgotten` | `Runtime::forget` | the string `"$strata.forgotten"` |
| `$strata.unsealed` | `Runtime::unseal` | the string `"$strata.unsealed"`; `meta` carries the capability |

## Side tables

| Table | Key | Value |
|---|---|---|
| checkpoints | projector / reactor name | `Position` |
| snapshots | `SnapshotKey::Stream(stream, version~)` or `SnapshotKey::Dcb(selection, version~)` | `SnapshotRecord { position, version, state : Json }` |
| views | `(table, key)` | `Json` rows written by inline and async projections |
| keys | subject | per-subject key material (1.1) |

## Planned PostgreSQL schema

A single `events` table (`position bigserial`, `stream_id`, `version`, `type`, `schema`, `data jsonb`, `meta jsonb`,
`tags text[]`, `recorded_at`) with a unique `(stream_id, version)` index and a GIN index on `tags`, plus
`checkpoints`, `snapshots`, `views` and `keys`. Every `Selection` compiles to one indexed `SELECT`; migrations ship in
the package and are applied with `PgStore::migrate()`.
