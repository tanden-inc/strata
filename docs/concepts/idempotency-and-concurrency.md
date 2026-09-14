# Idempotency and concurrency

## The command path

A command runs as *read → fold with `evolve` → `decide` (and `advise`) → append with the version you read*. The
runtime does this every time, so you never forget the last step.

```moonbit
let accounts = rt.handler(account)
let out = accounts.execute("acc-1", Deposit(amount=100), ctx~)
// out.events   : [Recorded[AccountEvent]]  — what was appended, with ids and positions
// out.notices  : []                        — advice
// out.version  : 2                         — stream version after the append; hand it out as an ETag
// out.position : 41                        — global position; what async read models chase
```

## Optimistic concurrency

If another writer got there first, `execute` raises `AppendConflict::StreamConflict(stream~, expected~, actual~)`.
Because `decide` is pure, "read again and re-decide" is always safe, so you can ask for it declaratively:

```moonbit
let accounts = rt.handler(account, retry=@rt.Retry::on_conflict(max=3))
```

Retry applies to conflicts only: the runtime re-runs a command when the error is an `AppendConflict`. Domain errors
are your own `suberror`s and are never retried. `Retry::on_conflict(max~, backoff?)` accepts a delay between attempts;
`Retry::none()` is the default.

Clients can participate too. Pass the version they last saw and the store enforces it:

```moonbit
accounts.execute("acc-1", Withdraw(amount=30), ctx~, expected=Exact(version_from_if_match))
```

`ExpectedVersion` is `Any | NoStream | Exact(Int)`. `NoStream` means "create only", which is how you make ids unique
without a lookup table. A DCB handler uses `AppendCondition::Dcb(selection~, after~)` instead, and a conflict there is
`BoundaryConflict`.

## Idempotency

Networks retry. Reactors redeliver. The same command *will* arrive twice, and the answer is not to teach every
`decide` about duplicates.

```moonbit
let a = accounts.execute("acc-1", Deposit(amount=100), ctx~, idempotency_key="req-7f3a")
let b = accounts.execute("acc-1", Deposit(amount=100), ctx~, idempotency_key="req-7f3a")
assert_eq(a.version, b.version)
assert_true(b.deduplicated)
```

The rules, from [ADR 0004](/adr/0004-idempotency):

- The key comes from the `execute` argument, else from `Context.idempotency_key`. The argument wins.
- Keys are stored in event metadata and indexed by the store (`find_idempotent`), optionally narrowed by stream. There
  is no extra table.
- A repeated command under a known key returns the **original** outcome: same `version`, same `position`, the original
  events, `deduplicated = true`. Nothing is appended.
- A **different** command under a known key raises `IdempotencyConflict::KeyReused`. The comparison is on the encoded
  events the command would produce against the stored batch.
- Reactors set the key to the triggering event's id through `Recorded::caused()`, so redelivery is harmless.

In practice you only think about idempotency at the API boundary, where the key is a request id or an
`Idempotency-Key` header.
