# Events: fat or thin

*Design note. Status: decided for 0.1, may be revisited.*

A **thin** event records only what changed (`Accepted(by~)`); a **fat** event copies the context a consumer will need
(`Accepted(by~, request~ : RequestSnapshot)`).

## The trade-off

| | Thin | Fat |
|---|---|---|
| Log honesty | high: only facts | lower: derived data is repeated |
| Consumer convenience | needs the writer's state | self-contained |
| Schema evolution | few fields to upcast | copied fields must evolve everywhere |
| Storage | small | larger |

## What Strata offers

- Thin events plus `Runtime::state_at(decider, recorded)`: a deterministic replay of the writer's stream up to the
  event's version. It is `async`, so it is available to **reactors** and to code that runs after a read, not inside a
  pure projection `apply`.
- Fat events when a **projection** needs the context: projections are pure folds and cannot call `state_at`.

## Rule of thumb

Keep events thin when the consumer is a reactor or an API handler. Make an event fat when a read model needs the
context and the copied data is genuinely part of the fact ("accepted *this* request as it was at that moment").
