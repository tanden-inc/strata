# ADR 0006: id batches are sized by use; reactors have bounded retry and a dead-letter hook

Date: 2026-09-14. Status: accepted (implementation pending).

## Id batches

`IdGenerator::reserve` hands a decision a lazy `IdBatch`; a decision may take any number of ids. The 0.1 generators
advanced by one per reservation, so a two-event decision overlapped with the next batch. `IdBatch` now records the
highest index taken (`high_water`), and a generator starts the next batch strictly after the last id handed out
(`sequential`: next number; `ulid`: `last.increment()`), also when the clock runs backwards. Unused batches consume
nothing.

## Reactor failure

`@async.retry(Immediate, ..)` with no bound spun forever on a poison event. `Runtime::reactor` takes
`retry? = FixedDelay(100)`, `max_retry? = 5` (retries *after* the first attempt, so at most six invocations) and
`on_failure? : async (StoredEvent, Error) -> Unit`. The delay schedule is the one configured (`FixedDelay`,
`ExponentialDelay` with its factor and cap, or `Immediate`). Cancellation is not a handler failure: a cancelled
reactor neither retries nor dead-letters, and leaves its checkpoint where it was. After the retries are exhausted
the event goes to `on_failure` and the checkpoint advances; without a hook the reactor raises and stops, so the
failure is visible instead of silent.

`IdBatch::high_water` is relative to the batch (`offset` starts a fresh counter); a generator therefore accumulates
`start + high_water + 1` itself and must also advance past ids it handed out to a batch that took none.
