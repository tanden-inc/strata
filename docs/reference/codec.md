# codec (`@codec`)

`tanden-inc/strata/codec` is pure and compiles for every target. It turns events into the stored JSON and back, and
declares how stored shapes evolve. See [Schema evolution and storage](/concepts/schema-evolution-and-storage) and
[tutorial part 8](/tutorial/08-schema-evolution).

## JsonCodec

```moonbit
pub struct JsonCodec
pub fn JsonCodec::JsonCodec(schema_version? : Int, style? : TagStyle) -> JsonCodec   // defaults: 1, Flat
```

| Method | Purpose |
|---|---|
| `schema_version()`, `style()` | the constructor arguments |
| `encode[E : ToJson](E) -> Encoded raise DecodeError` | derive the JSON and extract the type name |
| `type_of(Json) -> String raise DecodeError` | the type name a stored value carries, per `style` |
| `decode[E : FromJson](StoredEvent) -> Recorded[E]? raise DecodeError` | upgrade then decode; `None` for deprecated types and `$strata.*` system events |
| `decode_all[E](Array[StoredEvent]) -> Array[Recorded[E]] raise` | `decode` over a batch, skipping `None`s |
| `upgrade(event_type~, schema~, Json) -> (String, Json) raise` | apply the rename, then the upcasts from `schema` up to the current version |
| `migrate(type, from~ : Int, Upcast)` | register an upcast for payloads written under version `from` |
| `rename(stored, to~)` | map a stored type name to the current variant |
| `deprecated(type, replaced_by?)`, `is_deprecated(type)` | keep a type readable while folds skip it |
| `shred(fields~ : Array[FieldPath], redacted_as?)`, `shredded_fields()` | mark payload fields for per-subject encryption (1.1) |
| `seal(meta~ : Array[String], when~ : (Context) -> Bool)`, `sealed_meta()`, `seals(Context)` | mark metadata fields as sealed when the context asks (1.1) |

`migrate`, `rename`, `deprecated`, `shred` and `seal` return `Unit`, so chain them with the cascade operator `..`.

```moonbit
pub struct Encoded { event_type : String; schema : Int; data : Json }
```

## TagStyle

```moonbit
pub(all) enum TagStyle {
  Flat                        // derive default: ["Deposited", {...}] or "Closed"
  Legacy(tag_key~ : String)   // derive(ToJson(style="legacy")): {"$tag": "Deposited", ...}
}
```

## Upcast

A `Json -> Json` transformation applied to an event payload at read time. Pure and unit-testable; stored events are
never rewritten.

| Constructor / method | Effect on the payload object |
|---|---|
| `Upcast::add_field(name, default)` | add `name` if absent; never overwrites |
| `Upcast::rename_field(from~, to~)` | move a field |
| `Upcast::remove_field(name)` | drop a field |
| `Upcast::map((Json) -> Json raise)` | arbitrary transformation |
| `then(Upcast) -> Upcast` | compose, left to right |
| `run(Json) -> Json raise` | apply |

## Privacy declarations

::: warning Encryption lands in 1.1
These types are declared and wired through the runtime and key store, but fields are not yet encrypted. See
[Sealing and shredding](/concepts/sealing-and-shredding).
:::

```moonbit
pub(all) struct FieldPath(String)          // "<EventType>.<field>", e.g. "Opened.owner"
pub(all) enum Sealed[T] { Value(T); Sealed; Shredded }
```
