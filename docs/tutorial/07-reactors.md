# 7. Reactors and process managers

Workflows that span streams are built from *react to an event, issue a command*. Failures are handled with
compensating commands, not transactions. A reactor subscribes to a `Selection`, so it can follow a category, a tag, or
a combination.

## A reactor

`rt.reactor(name, source~, handler)` takes an `async` closure over `Recorded[E]`. There is no base class and no
annotation. The runtime's own test uses the two-line `counter` domain from [part 4](/tutorial/04-read-models):

<<< @/../runtime/runtime_test.mbt#reactor

Three things in that test matter:

- **`r.caused()`** builds the `Context` for downstream commands: it inherits the correlation id, sets the causation id
  to the triggering event's id, and sets the idempotency key to the same id. A redelivered event therefore produces a
  deduplicated command, not a duplicate effect.
- **`catch_up()`** processes everything up to the current head and returns; `start(group)` runs the reactor as a task
  in a `moonbitlang/async` task group until the group ends. Tests use the former; services use the latter.
- **Checkpoints.** The reactor's position is saved in the store, so a restart resumes where it left off.

## Redelivery is harmless by construction

Three properties combine: the reactor checkpoints its position, `r.caused()` turns the triggering event's id into the
downstream idempotency key, and a decider that models a workflow is a state machine that rejects out-of-order
commands. Teams routinely write a dozen reactors without a line that mentions duplicates.

## Bounded retry and dead letters

A handler that raises is retried with the configured delay schedule, then handed to `on_failure`, after which the
checkpoint advances. Without a hook the reactor raises and stops, so a poison event cannot be silently skipped.
Defaults are `FixedDelay(100)` milliseconds and `max_retry=5` (retries after the first attempt, so at most six
invocations). `retry` accepts any `@async.RetryMethod`: `Immediate`, `FixedDelay(ms)`, or
`ExponentialDelay(initial~, factor~, maximum~)`.

<<< @/../runtime/v1_test.mbt#dead-letter

Cancellation is not a failure: a reactor cancelled by its task group neither retries nor dead-letters, and leaves its
checkpoint where it was. The rules are recorded in [ADR 0006](/adr/0006-id-batches-and-reactor-failure).

## A process manager, sketched

A transfer between accounts is the classic shape: a `transfer` decider that is a state machine, and a reactor that
drives the two account streams and compensates on failure.

::: info Illustrative
This sketch shows the shape; it is not one of the compiled examples. The `transfer` decider and the `accounts` /
`transfers` handlers are assumed.
:::

```moonbit
let transfer_pm = rt.reactor("transfer-pm", source=@strata.Selection::category("transfer"),
  (r : @strata.Recorded[TransferEvent]) => {
    let ctx = r.caused()   // inherits correlation_id; causation_id = r.id; idempotency_key = r.id
    match r.event {
      Requested(from~, amount~, ..) =>
        try {
          accounts.execute(from, Withdraw(amount~), ctx~) |> ignore
          transfers.execute(r.entity_id(), MarkDebited, ctx~) |> ignore
        } catch {
          AccountError::Insufficient(..) =>
            transfers.execute(r.entity_id(), MarkFailed(reason="insufficient"), ctx~) |> ignore
        }
      Debited => { /* credit the destination; compensate the source if that fails */ }
      Credited => transfers.execute(r.entity_id(), MarkCompleted, ctx~) |> ignore
      Completed | Failed(..) => ()
    }
  })
```

Two-party handshakes, *A requests, B accepts, nobody above them approves*, are a state machine plus `env.actor`, not
a process manager.

## Integration events

Domain events are yours to change; what leaves your service is a contract. Translate at the edge in a reactor, and
note that the event store is already a durable log: there is no separate outbox table to keep in sync. Delivery is
at-least-once, keyed by event id so consumers can dedup.

```moonbit
let publisher = rt.reactor("ledger-public", source=@strata.Selection::category("ledger"),
  (r : @strata.Recorded[LedgerEvent]) => {
    match r.event {
      Moved(from~, to~, amount~, reason~, ..) =>
        bus.publish(topic="ledger.v1", key=r.id.to_string(),
          BudgetMoved(from~, to~, amount~, reason~, at=r.recorded_at))
      _ => ()
    }
  })
```

## Next

[Part 8](/tutorial/08-schema-evolution) changes the shape of an event without rewriting what is already stored.
