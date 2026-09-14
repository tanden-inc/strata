# Selections

`Selection` is how Strata names a set of events. It follows the Dynamic Consistency Boundaries specification: a
selection is a list of items, each item is a set of event types (empty means any) *and* a set of tags that must all
be present, and the items are OR-ed together.

```moonbit
Selection::stream(StreamId("account-acc-1"))            // one stream            ($stream: system tag)
Selection::category("account")                          // every stream in a category ($category:)
Selection::category("account", tenant="t1")             // one tenant's streams ($tenant:)
Selection::tags([Tag("code:X")])                        // events tagged code:X   (tags within an item: AND)
Selection::tags([Tag("code:X"), Tag("period:2026-09")]) // events tagged with both
Selection::types(["Moved", "Reserved"], tags=[Tag("code:X")])
Selection::any_of([Selection::tags([Tag("code:X")]), Selection::tags([Tag("code:Y")])])   // items: OR
Selection::all()                                        // the global log
Selection::none()                                       // nothing; any_of([]) is none
```

## Set semantics

Constructors normalise their input, so two selections that name the same set are `Eq` and hash alike; that is what
snapshot and checkpoint keys rely on. `Selection::matches(event_type~, tags~)` is the membership test the memory
store uses, and `single_stream()` recovers the stream id when a selection is exactly one stream.

## System tags

Streams, categories and tenants are ordinary tags that the **store** writes on every event: `$stream:<name>`,
`$category:<name>`, `$tenant:<t>`. One tag index therefore serves every kind of read. User code cannot create `$` tags
(`NewEvent` raises `InvalidTag`), and `Recorded.tags` shows only the event's own tags; `StoredEvent::user_tags()`
strips the system ones. See [ADR 0003](/adr/0003-ids-time-and-system-tags).

## Three primitives

Everything on the read side is built on three consumers of a `Selection`:

```moonbit
// Paged, position-ordered reads. Decode where the type is known.
let page = rt.read(Selection::tags([Tag("code:X")]), limit=50)
let history : Array[Recorded[LedgerEvent]] = page.decode()
// page.next : Position?   — pass as `after` for the next page

// Fold a selection into a value.
let balances = rt.fold(code_balances, Selection::tags([Tag("code:X")]))

// Subscribe from a position (what projectors and reactors use underneath).
let sub = rt.subscribe(Selection::category("allocation"), from=checkpoint)
```

`rt.live(view, category~, id~)` is `rt.fold(view, Selection::stream(...))` with a nicer name, and returns the stream
version alongside the value for use as an `ETag`.

## The same value on the write side

A `DcbDecider`'s `scope` returns a `Selection`, and the handler appends under `AppendCondition::Dcb(selection~,
after~)`. Because reads and boundaries share one vocabulary, anything you can guard you can also view, and anything
you can view you can also react to. `Scope::of(selection)` wraps a selection for `evolve`; `scope.owns(tag)` answers
"is this tag part of the selection that produced these events?". See
[Consistency boundaries](/concepts/consistency-boundaries).

It is called `Selection` and not `Query` so that it can live in the same file as a GraphQL schema without a fight.
