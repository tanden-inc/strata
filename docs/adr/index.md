# Architecture decision records

Decisions that changed the design after the README was written. Each record states the context, the decision, and its
consequences; "implementation pending" means the interface is in place and the roadmap names the red test.

| ADR | Decision | Status |
|---|---|---|
| [0001](/adr/0001-store-as-trait) | The event store is a trait, not a virtual package | accepted |
| [0002](/adr/0002-json-layout) | Stored JSON is the derive default | accepted |
| [0003](/adr/0003-ids-time-and-system-tags) | Identifiers, time, and system tags | accepted |
| [0004](/adr/0004-idempotency) | Idempotency semantics | accepted |
| [0005](/adr/0005-atomic-read-side-commit) | The read side commits rows and checkpoint together | accepted (implementation pending) |
| [0006](/adr/0006-id-batches-and-reactor-failure) | Id batches are sized by use; reactors have bounded retry and a dead-letter hook | accepted (implementation pending) |

New records go in `docs/adr/` with the next number and the same three headings.
