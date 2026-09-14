# Reactors and process managers

Workflows that span streams are built from *react to an event, issue a command*. Failures are handled with
compensating commands, not transactions. A reactor subscribes to a `Selection`, so it can follow a category, a tag, or
a combination.

```moonbit
let reactor = rt.reactor("echo", source=@strata.Selection::category("counter"),
  (r : @strata.Recorded[Ev]) => {
    let ctx = r.caused()          // correlation inherited; causation_id = r.id; idempotency_key = r.id
    other_handler.execute(r.entity_id(), SomeCommand, ctx~) |> ignore
  })
```

A reactor is an `async` closure over `Recorded[E]`: no base class, no annotations. `start(group)` runs it as a task
in a `moonbitlang/async` task group, `catch_up()` processes to the head and returns, `position()` is its checkpoint.
[Tutorial part 7](/tutorial/07-reactors) walks through the compiled example.

## Why redelivery is harmless

Three properties combine:

1. The reactor checkpoints its position in the store, so a restart resumes rather than replays.
2. `r.caused()` turns the triggering event's id into the downstream command's idempotency key, so a redelivered event
   yields a deduplicated command, not a second effect.
3. A decider that models a workflow is a state machine that rejects out-of-order commands.

Teams routinely write a dozen reactors without a single line that mentions duplicates.

## Failure

A handler that raises is retried with the configured `@async.RetryMethod` (`Immediate`, `FixedDelay(ms)`,
`ExponentialDelay(initial~, factor~, maximum~)`), at most `max_retry` times after the first attempt, then handed to
`on_failure(stored, error)`, after which the checkpoint advances. Without an `on_failure` hook the reactor raises and
stops, so a poison event is never silently skipped. Defaults: `FixedDelay(100)`, five retries. Cancellation by the
task group is not a failure: no retry, no dead letter, checkpoint untouched. See
[ADR 0006](/adr/0006-id-batches-and-reactor-failure).

## Process managers

A process manager is a reactor plus a decider that is a state machine: *Requested → Debited → Credited → Completed*,
with `Failed` reachable from the middle states. Each transition is a command to the process's own stream; each step
towards the outside world is a command to another stream; each failure is a compensating command. The
[sketch in the tutorial](/tutorial/07-reactors#a-process-manager-sketched) shows the shape.

Two-party handshakes, *A requests, B accepts, nobody above them approves*, are a state machine plus `env.actor`, not a
process manager.

## Integration events

Domain events are yours to change; what leaves your service is a contract. Translate at the edge in a reactor, and
note that the event store is already a durable log, so there is no separate outbox table to keep in sync. Delivery is
at-least-once, keyed by event id so consumers can dedup.

## Reaching for state

Thin events keep the log honest but leave consumers without the details they need. A reactor can ask for the writer's
state as it stood when the event was recorded:

```moonbit
let state = rt.state_at(assignment, r)   // replay pinned to (r.stream, r.version): deterministic
```

`state_at` is a runtime call, so it is available to reactors and API handlers; a projection's `apply` is pure and
needs a fat event instead. See [Read models](/concepts/read-models#fat-or-thin-events).
