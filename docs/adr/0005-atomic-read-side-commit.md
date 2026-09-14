# ADR 0005: the read side commits rows and checkpoint together

Date: 2026-09-14. Status: accepted (implementation pending).

## Context

The README's effectively-once argument for projectors rests on "the view is committed with its checkpoint in one
transaction". The 0.1 runtime writes rows with `ViewStore::put` and then calls `EventStore::save_checkpoint`: two
calls, two transactions on any real store. Likewise `MemoryStore::append` mutated the log before validating inline
writes, so a failure mid-way left partial state.

## Decision

- `ViewStore` gains `commit(writes~ : Array[ViewWrite], checkpoint? : Checkpoint)`, atomic by contract. Projectors
  and reactors that own views use it; reactors without views keep `save_checkpoint`.
- `EventStore::append` validates the condition, the events and the inline writes before any mutation. A failed
  append leaves the log, the head and the views untouched (contract case).
- `MemoryStore` owns its `MemoryViewStore` and checkpoint table, so `commit` can update both under one mutation
  step; the PostgreSQL store runs both in one SQL transaction.

## Consequences

`put`/`delete` remain for ad-hoc writes but carry no atomicity across calls. Contract cases enforce the new rules on
every adapter.
