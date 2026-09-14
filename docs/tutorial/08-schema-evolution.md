# 8. Schema evolution

Stored events are never rewritten. Change happens at read time, in three shapes: upcast a payload, rename a type, or
deprecate one. All three are declared on a `JsonCodec` and passed to the runtime.

## What is stored

Strata stores exactly what `derive(ToJson)` produces, alongside a schema version: `["Deposited", {"amount": 100,
"by": "user:alice"}]` for a variant with a payload, `"Closed"` for one without. The event type name is read back out
of that value. You never write a codec and you never register a type name. See
[Stored format](/reference/stored-format) for the full layout.

## Upcasts, renames, deprecations

`migrate(type, from~, upcast)` applies a `Json -> Json` transformation to payloads written under schema version
`from`; `rename(stored, to~)` maps a stored type name to the current variant; `deprecated(type)` keeps a type readable
while folds skip it. `upgrade` is what `decode` calls; the test below shows the order: rename first, then upcasts in
version order.

<<< @/../codec/codec_test.mbt#upgrade

Upcasts compose with `then`, and the building blocks (`add_field`, `rename_field`, `remove_field`, `map`) are pure and
unit-testable:

<<< @/../codec/codec_test.mbt#compose

Wire the codec into the runtime once:

```moonbit
let codec = @codec.JsonCodec(schema_version=3)
codec
..migrate("Withdrawn", from=1, @codec.Upcast::add_field("fee", 0))
..rename("Debited", to="Withdrawn")
.deprecated("LegacyFeeCharged", replaced_by="Withdrawn")

let rt = @rt.Runtime(store, codec~)
```

## Tag styles

The default `TagStyle::Flat` matches MoonBit's derive default. Applications that use `derive(ToJson(style="legacy"))`
get `{"$tag": "Deposited", ...}` and configure `TagStyle::Legacy(tag_key="$tag")`. Payload-less variants work in both
styles.

<<< @/../codec/v1_test.mbt#legacy

## System events are skipped

The runtime appends `$strata.forgotten` and `$strata.unsealed` markers to a stream when data is forgotten or sealed
metadata is read ([Sealing and shredding](/concepts/sealing-and-shredding)). `decode` returns `None` for them, like
for deprecated types, so folds never see a system event.

<<< @/../codec/v1_test.mbt#system-events

## Fixtures: prove every historical shape still decodes

Keep one JSON fixture per event shape you have ever written and let the suite decode them all with the current codec.
`Fixtures::from_json` takes `(event_type, schema, data)` triples, `from_stored` takes stored events you loaded from
files, and `all_decode` raises on the first shape that no longer decodes.

```moonbit
test "every historical shape still decodes" {
  let fixtures = @testing.Fixtures::from_json([
    ("Debited", 1, ["Debited", { "amt": 10 }]),
    ("Withdrawn", 2, ["Withdrawn", { "amt": 10, "fee": 1 }]),
    ("Withdrawn", 3, ["Withdrawn", { "amount": 10, "fee": 1 }]),
  ])
  let report : @testing.FixtureReport[AccountEvent] = fixtures.all_decode(codec)
  inspect(report.decoded.length(), content="3")
  inspect(report.skipped, content="0")
}
```

## Where to go from here

You have built the whole loop: a decider, its specs, the runtime, read models, advice, boundaries, reactors, and
evolution. The [concepts](/concepts/deciders) pages explain *why* each piece is shaped the way it is, the
[design](/design/principles) pages record the decisions, and the [reference](/reference/core) lists every public type.
