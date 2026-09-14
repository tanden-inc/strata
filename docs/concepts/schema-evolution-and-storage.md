# Schema evolution and storage

## What is stored

Strata stores exactly what `derive(ToJson)` produces, alongside a schema version:

```json
["Deposited", { "amount": 100, "by": "user:alice" }]
"Closed"
```

The event type name is read back out of that value by the codec's `TagStyle`. `Flat` is the derive default;
applications that prefer `derive(ToJson(style="legacy"))` get `{"$tag": "Deposited", ...}` and configure
`TagStyle::Legacy(tag_key="$tag")`. Identifier newtypes (`EventId`, `StreamId`, `Position`, `Instant`, `Duration`,
`Actor`, `Tag`) implement `ToJson`/`FromJson` by hand as plain scalars so payloads stay readable. You never write a
codec and you never register a type name. The full column layout is in [Stored format](/reference/stored-format) and
the decision in [ADR 0002](/adr/0002-json-layout).

## Change at read time

Stored events are never rewritten. Change happens when they are read, in three shapes:

```moonbit
let codec = @codec.JsonCodec(schema_version=2)
codec
..migrate("Withdrawn", from=1, @codec.Upcast::add_field("fee", 0))   // additive change: fill a default
..rename("Opened", to="AccountOpened")                                // stored type name → current variant
.deprecated("LegacyFeeCharged", replaced_by="Withdrawn")              // still readable, skipped by folds

let rt = @rt.Runtime(store, codec~)
```

- **Upcasts** are `Json -> Json` functions registered per type and per source schema version. `decode` applies the
  rename first, then the upcasts from the stored version up to the current one, in order. `Upcast::add_field`,
  `rename_field`, `remove_field` and `map` are the building blocks; `then` composes them. They are pure and
  unit-testable.
- **Renames** map a stored type name to the current variant name.
- **Deprecations** keep a type decodable while `decode` returns `None` for it, so folds skip it; `replaced_by`
  documents the successor.

System events (`$strata.forgotten`, `$strata.unsealed`) are skipped by `decode` the same way, so a projection never
sees them.

## Adding is a compile error

Events are closed sums. When you add `FeeCharged`, every `evolve` and every read model's `apply` that forgot it fails
to compile, and the build passes only when you have decided what each does. Cross-context evolution is handled where
it belongs, in the serialized format, so closedness costs nothing at the boundary.

## Fixtures

Keep a JSON fixture of every event shape you have ever written and let the suite prove they all still decode.
`@testing.Fixtures::from_json` takes `(event_type, schema, data)` triples; `all_decode(codec)` returns a
`FixtureReport { decoded, skipped }` and raises on the first shape that no longer decodes. See
[tutorial part 8](/tutorial/08-schema-evolution#fixtures-prove-every-historical-shape-still-decodes).
