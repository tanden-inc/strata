# Preview: the same decision in the browser

Because `strata/core` has no IO, it compiles to `wasm-gc` and `js`. A `Decider` is a value, so the client can hold
the same one the server runs. Give it a state and an environment, and it will tell you what a command *would* do,
the rejection, the events, the advice, before a request is sent.

```moonbit
// in the browser, with a state fetched from the server (a live view, or a snapshot; both are `Eq`)
let preview = @strata.Preview(charge, state~, env=@strata.Env(actor=me, now=@strata.Instant(js_date_now_ms)))
let outcome = preview.of(Charge(amount=50, reference="inv-9"))
match outcome.result {
  Ok(events) => show_confirmation(events, warnings=outcome.notices)
  Err(e)     => show_inline_error(e)
}
```

`Preview::of` returns a `PreviewResult { result : Result[Array[E], Error], notices : Array[N] }`. The compiled
example is in [tutorial part 2](/tutorial/02-specs#the-same-machinery-without-a-test).

## What it is, and is not

The server remains the authority: the client's preview is over a possibly stale state, and the real `execute` may see
a newer one. But the *logic* is identical by construction, so the warning the user sees is the warning the server
would compute. There is no second implementation of the rules in the frontend to drift.

Trust it for what it is: the server's rules over a state that may be a few events behind. It cannot be wrong about the
*rules*, only about the *world*, and `execute` corrects the latter with an `AppendConflict`. Never skip the server
call because the preview said yes.

`Preview` and `@testing.spec` are the same machinery (`Decider::run`) with different ergonomics; both are pure and
target-independent.

## Getting a state to the browser

A preview needs a state. Two sources work: a live view (`rt.live` returns the state and version, which doubles as the
`ETag` to send back with the command), or a snapshot. State types derive `ToJson, FromJson`, so shipping one over HTTP
is the derived JSON.
