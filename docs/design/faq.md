# FAQ

**Should I event-source everything?**
No. Event-source the parts of the system where history is the product: money, inventory, allocation, audit, anything
you will be asked to explain later. Strata is comfortable living next to a CRUD service in the same process.

**When do I `raise`, when do I `advise`, and when do I record an event?**
`raise` when the fact must not exist: money created from nothing, an action by someone who cannot take it. `advise`
when the fact may exist but someone should know: an overspend, a late entry, an unusual amount. Record an event when a
*person* responds to that knowledge: an explanation, an acknowledgement, a correction. The log holds what happened;
advice holds what is worth noticing; neither pretends to be the other.

**Why is `advise` separate from `decide` instead of one function returning both?**
Because they answer different questions and are held to different standards. `decide` is the function you prove
things about and the one whose output the store persists; keeping it two-valued keeps those obligations small.
`advise` is free to be heuristic, to change weekly, to differ per deployment. Bundling them would make the proof
surface include the heuristics.

**Why closed enums? I want plugins to add events.**
Because exhaustiveness is the feature. A bounded context owns its event set; other contexts consume the serialized
form, which is open by nature. If you need extension inside a context, that is usually two contexts.

**Why does `decide` take an `Env` instead of putting the actor in every command?**
Because the actor, the tenant, and the time are facts about the *invocation*, not about the intent. Commands stay
pure intents. Events, being facts, *do* carry the actor where the domain cares (`decide` copies it from `env.actor`)
and `meta.actor` records it regardless, for audit. Three roles, three places, no drift.

**Why does the runtime reserve event ids before `decide` runs?**
Because a decision often needs to *name* what it is recording, a reservation to settle later, an entry to reverse
later, and `decide` is not allowed to generate anything. Reserving ids up front costs nothing (ULIDs are cheap, unused
ones are discarded) and gives `decide` a stable, test-deterministic way to refer to its own output. `evolve` stays a
fold over plain events because the ids are *in* the events.

**Why `raise` instead of `Result`?**
Because `raise` is checked and cheap, and because it lets `decide` say what can go wrong in its signature without
wrapping every return. Where you want a value, `try ... catch` gives you one. `testing.spec` and `Preview` return
`Result` for exactly this reason.

**Streams or DCB?**
Streams when one entity owns the invariant. DCB when the invariant is a relationship between entities: conservation,
exclusivity, a cap across a group. Both go through the same `append`, the same `Selection`, and the same read side, so
choosing late is cheap. Record-first domains need DCB less often than you expect: an entry that is allowed to go
negative needs no boundary.

**Is Preview safe to trust in the client?**
Trust it for what it is: the server's rules over a state that may be a few events behind. It cannot be wrong about
the *rules*, only about the *world*, and `execute` corrects the latter with an `AppendConflict`. Never skip the server
call because the preview said yes.

**Who can see what? Does Strata do authorization?**
No. The log is one log; `Selection` selects, it does not authorize. Visibility rules (*members of this account may
read its observations*) belong in your API layer, typically backed by a projection that answers membership questions.
Sealing is the one privacy primitive Strata does provide, because it has to be applied at the storage layer to mean
anything.

**Can I use my own store?**
Yes. Implement the `@store.EventStore` trait (and `ViewStore` for inline read models), run
`@testing.contract(make=...)` against it, and pass it to `Runtime(store)`.

**Does Strata replace a message broker?**
No. The event store is your system of record and your outbox; a broker is how other systems hear about it. Reactors
bridge the two.

**How fast is it?**
The command path is one indexed read and one insert per command; the in-memory store is bound by the fold, and the
PostgreSQL store by the database. Benchmarks and methodology live in
[`benchmarks/`](https://github.com/tanden-inc/strata/tree/main/benchmarks) and will be published with the first
implemented release.
