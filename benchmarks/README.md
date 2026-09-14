# Benchmarks

Run with:

```bash
moon bench benchmarks
```

Publish the numbers here (toolchain version, machine, target) before tagging a release.

| Benchmark | What it measures | Latest numbers |
|---|---|---|
| `selection matching` | `Selection::matches` over 5 tags, 1000 iterations | not published yet |
| `ulid increment` | 1000 `EventId::increment` calls | not published yet |
| `replay 1000 + decide` | the pure half of `execute`: fold 1000 events, run `decide`/`advise` | not published yet |

Still missing: an end-to-end `CommandHandler::execute` benchmark over `MemoryStore`. `@bench.T::bench` takes a
synchronous closure, so it needs either an `async` bench harness or a driver in `cmd/` that times a loop of
`execute` calls under `with_task_group`.
