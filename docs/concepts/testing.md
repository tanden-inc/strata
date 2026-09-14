# Testing

Strata treats tests as the primary interface for reading a domain.

## Specifications

Given past events, when a command, then events or an error, and, separately, advice. Values in, values out. The
environment is part of the given; event ids are deterministic.

```moonbit
test "close requires zero balance, then succeeds" {
  let spec = @testing.spec(account).acting_as(actor=alice)
    .given([Opened(owner=alice), Deposited(amount=50, by=alice)])
  spec.when(Close)                            |> debug_inspect(content="Err(NotEmpty(balance=50))")
  spec.when_all([Withdraw(amount=50), Close]) |> debug_inspect(content="Ok([...])")
}
```

`debug_inspect` snapshots mean `moon test --update` writes the expected events and you review them as a diff. One
rule, ten lines; put the same blocks in a `README.mbt.md` and your documentation is executable.
[Tutorial part 2](/tutorial/02-specs) covers the `Spec` API; `@testing.dcb_spec` is the same for a `DcbDecider`,
plus `scope_of` and `assert_scope_closed`.

## Laws

Properties that must hold for every history. Ready-made:

| Law | Checks |
|---|---|
| `replay_law(decider, events)` | replay equals snapshot plus tail, for every split point |
| `advice_law(decider, histories~, commands~)` | advice is a pure function of command, state and environment |
| `reversal_law` / `dcb_reversal_law(decider, reverses~, identity~, histories~, restores?)` | a reversal carries its target's tags, the target exists, and optionally the effect is undone |
| `dcb_spec(...).assert_scope_closed()` | out-of-scope events do not change a DCB state |

Write your own with `moonbitlang/quickcheck`; `@testing.arbitrary_selection`, `arbitrary_env` and `arbitrary_tag`
are generators for Strata's own types:

```moonbit
test "replay equals snapshot plus tail" {
  @qc.quick_check((events : Array[AccountEvent]) => {
    let k = events.length() / 2
    account.replay(events.iter()) ==
      account.replay_from(account.replay(events.iter().take(k)), events.iter().drop(k))
  })
}
```

## Runtime tests

`@testing.runtime(clock?, ids?, codec?)` returns a `Runtime` over a fresh `MemoryStore` with a fixed clock and
sequential ids (`evt-0001`, ...). `async test` blocks run handlers, projectors (`catch_up`, `wait_for`) and reactors
(`catch_up`) against it and snapshot what the log contains afterwards. `@testing.recorded(...)` and
`@testing.stored(...)` build envelopes by hand for projection tests.

## Contracts

Every `EventStore` implementation runs the same suite: append semantics, expected versions, DCB conditions, selection
semantics, subscription ordering, idempotency scopes, checkpoints, snapshots, atomic inline writes.

```moonbit
async test "store contract" {
  @testing.contract(make=() => @store.MemoryStore())
}
```

`@testing.contract_cases()` lists the twenty-one case names in the order they run, which is the checklist for writing
your own store.

## Fixtures

`@testing.Fixtures::from_json([...]).all_decode(codec)` proves every historical event shape still decodes with the
current codec. See [Schema evolution](/concepts/schema-evolution-and-storage#fixtures).

## Proofs

::: info Planned
For the invariants you cannot afford to get wrong, `decide` and `evolve` are pure and therefore admissible to
`moon prove`. The plan for `examples/ledger` is to prove that the sum of balances across all codes is invariant under
every accepted `Move` and every `Reversed`. This integration is experimental and not part of 0.1.
:::
