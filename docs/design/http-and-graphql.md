# HTTP and GraphQL

::: warning Planned
Neither adapter is part of the 0.1 interface. This page records the intended mapping so that application code written
today lines up with it. The building blocks it relies on (`out.version`, `out.position`, `rt.read` paging,
`Projector::wait_for`, typed rejections) exist now.
:::

Strata will ship thin adapters for both, and the same runtime facts drive both: `out.version` is an `ETag`,
`out.position` is what you wait for, typed rejections are your error contract.

## HTTP

Optimistic concurrency extends to clients: return the version as an `ETag`, accept it back as `If-Match`. Domain
errors map to 422, conflicts to 409, idempotent replays to 200. Tag-scoped history is a paged read.

```moonbit
(POST, ["accounts", id, "deposit"]) => {
  let body : DepositBody = req.json()
  let out = @strata_http.run(res, () =>
    accounts.execute(id, Deposit(amount=body.amount),
      ctx=@strata.Context::from_http(req),
      expected=req.if_match_version(),
      idempotency_key=req.header("Idempotency-Key")))
  res..status(201)..etag(out.version)..json({ "events": out.events, "notices": out.notices })
}
(GET, ["codes", code, "history"]) => {
  let page = rt.read(@strata.Selection::tags([@strata.Tag("code:\{code}")]), after=req.cursor(), limit=50)
  let items : Array[@strata.Recorded[LedgerEvent]] = page.decode()
  res..json({ "items": items, "next": page.next })
}
```

## GraphQL

A `suberror` is a closed set of typed rejections; a GraphQL result union is exactly that. A `Selection` is a paged,
cursor-based read; a GraphQL connection is exactly that. And `rt.subscribe` is a subscription.

| Strata | GraphQL |
|---|---|
| a `suberror` (closed set of typed rejections) | a result union (`MoveResult = Moved \| Insufficient \| ...`) |
| `Selection` + `Runtime::read` (paged, cursor = `Position`) | a connection |
| `Runtime::subscribe` | a subscription |
| `Outcome.version` | `ETag` / `expectedVersion` argument |
| `Projector::wait_for(out.position)` | read-your-writes in the mutation resolver |

```graphql
type Mutation {
  move(from: ID!, to: ID!, amount: Int!, reason: String!, expectedVersion: Int): MoveResult!
}
union MoveResult = Moved | Insufficient | NotOwner | Conflict     # from LedgerError + AppendConflict

type Moved   { events: [LedgerEvent!]!, notices: [LedgerNotice!]!, version: Int!, position: Position! }
type Code {
  id: ID!
  balance: Int!                                                   # inline projection
  landing: Landing!                                               # async projection; resolver waits for position
  history(after: Cursor, first: Int): LedgerEventConnection!      # rt.read(Selection::tags([Tag("code:" + id)]))
}
type Subscription { pending: PendingBoard! }                      # rt.subscribe(Selection::…)
```

```moonbit
// resolver for Mutation.move
let out = codes.execute(Move(..), ctx=@gql.context(req), expected=@gql.expected(args.expectedVersion))
landing_projector.wait_for(out.position, timeout=@strata.Duration::seconds(2))   // read-your-writes
```

An honest note: MoonBit's `derive` covers a fixed set of traits, so the SDL and resolver skeletons will be produced by
a `moon run` tool from your enums and suberrors rather than derived at compile time. The generated code is checked in
and type-checked against your domain, so a renamed variant still fails the build, but the "no codecs, no registries"
promise of the storage format does not extend to your public schema.

Open questions: cursor encoding, N+1 over keyed projections, error mapping for `AppendConflict`.
