# 2. Specs: tests as specifications

A domain test in Strata is Given/When/Then over plain values: given these past events, when this command, then these
events or this rejection. `@testing.spec` runs the decider you wrote in [part 1](/tutorial/01-your-first-decider) with
a fixed environment and no store.

## Given, when, then

<<< @/../examples/account/account_test.mbt#spec-basic

`when` returns a `Result[Array[E], Error]`. Expected values are written as `debug_inspect` snapshots: run
`moon test --update` once, and the expected text is filled in for you; from then on a change in behaviour shows up as
a diff to review, not a string to retype.

The environment is part of the given. `acting_as(actor~, tenant?)` fixes who is acting, `at(instant)` fixes the
clock, and `with_env` or `with_ids` replace the whole environment or the id batch when a test needs to. Event ids in
a spec are deterministic (`evt-0001`, `evt-0002`, ...), so snapshots that contain ids stay stable.

## Threading commands and inspecting state

`when_all` runs several commands in sequence, threading the state, and stops at the first rejection. `state()` returns
the state the given history folds to, which is how you check `is_terminal` or any other derived fact.

<<< @/../examples/account/account_test.mbt#spec-when-all

## Laws

Some properties should hold for every history, not just the ones you thought of. `@testing.replay_law` checks that
replaying a history equals replaying a prefix and continuing from the resulting snapshot, which is the property
snapshots depend on:

<<< @/../examples/account/account_test.mbt#replay-law

[Concepts: Testing](/concepts/testing) lists the other ready-made laws (advice, reversals, scope closure) and how to
write your own with `moonbitlang/quickcheck`.

## The same machinery without a test

`Preview` is `spec` with different ergonomics: hand it a decider, a state and an environment, and it tells you what a
command would do. It is the piece that runs in the browser.

<<< @/../examples/account/account_test.mbt#preview

## Executable documentation

MoonBit compiles `mbt check` blocks inside `*.mbt.md` files as tests. The account example keeps its README executable,
so the snippet in the documentation can never drift from the code:

````md
# examples/account

The README's "Sixty seconds" domain, kept executable. The block below is compiled and run by `moon test`.

```mbt check
///|
test "withdrawals cannot exceed the balance" {
  let alice = @strata.Actor("user:alice")
  @testing.spec(@account.account)
  .acting_as(actor=alice)
  .given([Opened(owner=alice), Deposited(amount=50, by=alice)])
  .when(Withdraw(amount=80))
  |> debug_inspect(content="Err(Insufficient(balance=50, requested=80))")
}
```
````

## Running the suite

```bash
moon test --target js examples/account
```

Use the JavaScript target during development: a panic there fails one test, where on native it aborts the whole test
executable of that package. `moon test -u` rewrites snapshots; review them as a diff.

## Next

[Part 3](/tutorial/03-running-commands) runs the same decider against a store, with optimistic concurrency and
idempotency handled for you.
