# ADR 0002: stored JSON is the derive default

Date: 2026-09-14. Status: accepted.

## Context

The README claimed the storage format is `{"$tag": "Deposited", ...}`. Verified against `moonc v0.10.12`:
`derive(ToJson)` on an enum produces `["Deposited", {"amount": 100, "by": "user:alice"}]` (payload-less variants
become the bare string `"Closed"`); `{"$tag": ...}` requires `derive(ToJson(style="legacy"))` on every event type.
Tuple structs derive as `["Id", "evt-1"]`.

## Decision

- `StoredEvent.data` is the whole value `derive(ToJson)` produces. The codec adds nothing.
- The event type name is a denormalised column that the codec extracts according to `TagStyle`:
  `Flat` (default) or `Legacy(tag_key="$tag")`.
- Identifier newtypes (`EventId`, `StreamId`, `Position`, `Instant`, `Duration`, `Actor`, `Tag`) implement
  `ToJson`/`FromJson` by hand as plain scalars so payloads stay readable.

## Consequences

Users write `derive(Eq, Debug, ToJson, FromJson)` and nothing else. Applications that prefer the flat-object layout
set `style="legacy"` on their enums and `JsonCodec(style=Legacy(tag_key="$tag"))`.
