# Installation

Strata is a MoonBit module. It is developed against the 0.10 line of the MoonBit toolchain and
`moonbitlang/async` 0.21.

```bash
moon add tanden-inc/strata
```

## Importing the packages

Strata is split into five packages. Import the ones you need in your package's `moon.pkg`; the aliases below are the
ones every example and this documentation use.

```moonbit
// moon.pkg
import {
  "tanden-inc/strata/core" @strata,     // Decider, Selection, Env, ids, time, projections, Preview
  "tanden-inc/strata/store" @store,     // EventStore trait + the in-memory MemoryStore
  "tanden-inc/strata/runtime" @rt,      // Runtime, handlers, reads, projectors, reactors
  "moonbitlang/async",
}

import {
  "tanden-inc/strata/testing" @testing, // spec, dcb_spec, laws, store contract, test runtime
} for "test"
```

`tanden-inc/strata/codec` is only needed when you configure schema evolution or a non-default JSON tag style; the
`Runtime` creates a default `JsonCodec` otherwise.

| Package | Alias | Purity | Targets | Contents |
|---|---|---|---|---|
| `core` | `@strata` | pure | native, js, wasm, wasm-gc | `Decider`, `DcbDecider`, `Env`, `Selection`, `Scope`, ids, time, `Recorded`, `Context`, `Outcome`, projections, `Preview` |
| `codec` | `@codec` | pure | native, js, wasm, wasm-gc | `JsonCodec`, `TagStyle`, `Upcast`, sealing and shredding declarations |
| `store` | `@store` | async | native, js, wasm | `EventStore`, `ViewStore`, `KeyStore`, `Subscription` traits; `MemoryStore` |
| `runtime` | `@rt` | async | native, js, wasm | `Runtime`, command handlers, reads and folds, projectors, reactors, `Clock`, `IdGenerator` |
| `testing` | `@testing` | mixed | native, js, wasm | `spec`, `dcb_spec`, laws, store `contract`, test runtime helpers |

Dependency direction is strictly `core <- codec <- store <- runtime <- testing`. `core` and `codec` never import
`moonbitlang/async`, which is why they compile for `wasm-gc` and can run in a browser; see [Preview](/concepts/preview).

## Targets

| | native | js | wasm-gc |
|---|---|---|---|
| Domain code, read models, `Preview` | ✓ | ✓ | ✓ |
| `MemoryStore`, runtime, `@testing` | ✓ | ✓ | wasm only (`moonbitlang/async` does not target wasm-gc) |
| PostgreSQL store | planned | planned (host driver) | — |
| Async projectors and reactors | ✓ | ✓ | — |

Declare the targets a package supports in its `moon.pkg` when it uses the async packages:

```moonbit
supported_targets = "+native+js+wasm"
```

## Running the tests

Domain tests are ordinary `test` blocks; runtime tests are `async test` blocks. Both run with `moon test`. During
development the JavaScript target isolates a panic to the single test that hit it, which makes it the friendlier
target for a red/green loop:

```bash
moon test --target js
```

Next: the [Quickstart](/guide/quickstart) defines a domain, tests it, and runs it against the in-memory store in about
sixty seconds.
