# Sealing and shredding

::: warning Declared in 0.1; encryption lands in 1.1
The declarations (`JsonCodec::shred`, `JsonCodec::seal`, the `KeyStore` trait, `Runtime::forget`, `Runtime::unseal`)
exist and are wired: `forget` destroys the key and appends a `$strata.forgotten` marker, `unseal` reads metadata with
a capability and appends a `$strata.unsealed` marker, and the key store enforces destroyed and sealed keys. Field
encryption itself is not implemented yet; until it is, marked fields are stored in clear. Do not rely on this page
for a privacy guarantee before 1.1.
:::

An immutable log and privacy are reconciled with keys, not deletion. Strata encrypts marked fields, in event bodies
*and* in metadata, with a per-subject key, and offers two things you can do with that key.

**Shredding** destroys the key. The event remains; the field becomes permanently unreadable. This is "forget me".

**Sealing** keeps the key in the key store but withholds it from ordinary reads. The field is readable only through
`rt.unseal` with an explicit capability, and every unseal is itself recorded. This is how you make a record
*anonymous to the organization* while keeping it *attributable under audit*: an anonymous piece of feedback, a
whistleblower report, a sealed bid. The log does not forget who acted; it declines to say, unless asked with
authority.

```moonbit
let codec = @codec.JsonCodec(schema_version=2)
codec
..shred(fields=[@codec.FieldPath("Opened.owner"), @codec.FieldPath("Registered.email")], redacted_as="<redacted>")
.seal(meta=["actor"], when=ctx => ctx.flag("anonymous"))
let rt = @rt.Runtime(store, codec~, keys=my_key_store)   // any `KeyStore`; MemoryKeyStore by default

rt.forget(category="account", id="acc-1")   // destroys the key, appends a $strata.forgotten marker, notifies projectors

r.meta.actor                                // => None while sealed (ordinary read)
rt.unseal(stored, capability="auditor")     // => metadata with the actor; recorded as $strata.unsealed
```

Deciders and read models never see the encryption. After shredding, `Opened(owner="<redacted>")` decodes normally;
`Projector::on_forgotten` is where you drop your own copies. Who may hold an unseal capability is your application's
decision; Strata only guarantees that using one leaves a mark.

## Key store semantics

`KeyStore` has four operations: `key_for(subject)`, `destroy(subject)`, `seal(subject)` and `unseal(subject,
capability~)`. Destroyed keys stay destroyed (`KeyDestroyed`), sealed keys are withheld from ordinary reads
(`KeySealed`), and `unseal` never lifts a seal or re-creates a key (`KeyMissing`). `MemoryKeyStore::unseals()`
returns the audit list of `(subject, capability)` pairs, which is what a test asserts on.
