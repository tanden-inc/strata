# Examples

Two reference domains live in the repository. They are compiled and tested by `moon test`, they are the first TDD
targets for every change, and the tutorial imports its code from them.

## `examples/account`

A guard-first, single-stream domain: the `Decider` from the [Quickstart](/guide/quickstart).

| Item | Demonstrates |
|---|---|
| `account : Decider[AccountCmd, AccountEvent, Account, Unit]` | guard-first `decide`, `env.actor` for ownership, `is_terminal` on close |
| `balance_view : Projection[AccountEvent, BalanceView]` | a single-source read model |
| `account_test.mbt` | specs (`given`/`when`/`when_all`/`state`), `replay_law`, `Preview`, `execute`, rejections, idempotency, `Exact` conflicts, `live`, terminal streams |
| `v1_test.mbt` | tenants (`t1/account-acc-1`), `Retry::on_conflict` never retrying a rejection |
| `README.mbt.md` | an executable doc block (`mbt check`) |

Source: [`examples/account`](https://github.com/tanden-inc/strata/tree/main/examples/account). Tutorial parts
[1](/tutorial/01-your-first-decider), [2](/tutorial/02-specs), [3](/tutorial/03-running-commands),
[4](/tutorial/04-read-models).

## `examples/ledger`

Two deciders in one package.

| Item | Demonstrates |
|---|---|
| `ledger : DcbDecider[LedgerCmd, LedgerEvent, Balances, Unit]` | conservation across codes with a DCB, `code_tag`, `ledger_scope`, `ledger_tags`, partial-world `evolve`, reversals by id |
| `charge : Decider[ChargeCmd, ChargeEvent, CodeLedger, ChargeNotice]` | a record-first domain with `advise` |
| `code_ledger : KeyedProjection[LedgerEvent, Code, CodeRow]` | fan-out of one `Moved` to two rows |
| `ledger_test.mbt` | `dcb_spec`, `assert_scope_closed`, `dcb_reversal_law`, `dcb_handler`, a `BoundaryConflict` produced by hand, advice specs, keyed folds |
| `README.mbt.md` | an executable doc block |

Source: [`examples/ledger`](https://github.com/tanden-inc/strata/tree/main/examples/ledger). Tutorial parts
[5](/tutorial/05-advice) and [6](/tutorial/06-dynamic-consistency-boundaries).

## Not yet in the repository

The prose mentions an `assignment` example (a two-party request/accept handshake, the reference for `state_at` over
thin events) and a `landing` multi-source view. Both are listed under *Promises without code* in the
[roadmap](/ROADMAP).

## Running them

```bash
moon test --target js examples/account examples/ledger
```
