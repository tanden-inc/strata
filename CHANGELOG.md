# Changelog

All notable changes to Strata are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project follows semantic versioning.

## [Unreleased]

### Added
- Round 3: `ViewStore::checkpoint`, `KeyMissing`, red tests for id uniqueness across many decisions, reactor
  cancellation and backoff, key-store and reversal-law edge cases; `benchmarks/README.md` and a pure command-path benchmark.
- Round 2 interface pieces for 1.0: `ViewStore::commit` + `Checkpoint` (atomic read side), `Selection::none`,
  `IdBatch::high_water`, `is_system_event_type`, reactor `max_retry`/`on_failure`, `KeySealed`/`KeyDestroyed`,
  the `store/pg` skeleton, and the red tests that drive them (see `docs/ROADMAP.md`).
- Project scaffolding on the MoonBit `moon.mod` / `moon.pkg` toolchain.
- Working 0.1 implementation of `core`, `codec`, `store` (`MemoryStore`), `runtime`, and `testing` against the frozen public API.
- Test suites per package and the `examples/account` and `examples/ledger` reference domains.
