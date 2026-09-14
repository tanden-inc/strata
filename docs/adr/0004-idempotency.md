# ADR 0004: idempotency semantics

Date: 2026-09-14. Status: accepted.

- The key comes from the `execute` argument, else from `Context.idempotency_key`. The argument wins.
- Keys are stored in event metadata and indexed globally by the store (`find_idempotent`), optionally narrowed by stream.
- A repeated command under a known key returns the **original** outcome: same `version`, same `position`, the original
  events, `deduplicated = true`. Nothing is appended.
- A **different** command under a known key raises `IdempotencyConflict::KeyReused`. The comparison is on the
  encoded events the command would produce against the stored batch.
- Reactors set the key to the triggering event's id through `Recorded::caused()`, so redelivery is harmless.
