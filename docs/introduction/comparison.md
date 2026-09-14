# Compared to other tools

Strata stands on ideas other communities worked out first. If you know them, here is the map.

| If you know… | Strata is… |
|---|---|
| **Emmett** (TypeScript) | the same Decider shape and PostgreSQL-first pragmatism, with the union type checked exhaustively, effects enforced by the compiler, advice beside decisions, and a read side that is a peer of the write side rather than a set of per-stream helpers. |
| **Equinox** (F#) | the same functional core; Strata trades Equinox's storage breadth for one store trait, one contract suite and a single runtime story. |
| **Marten** (.NET) | the same inline/async/live projection lifecycles over PostgreSQL, with multi-source and fan-out views as first-class values instead of subclasses, and without the document-database half. |
| **Commanded** (Elixir) | the same execute/apply split and process managers; Strata runs on structured-concurrency tasks instead of BEAM processes and is statically typed end to end. |
| **Axon** (Java) | a different philosophy: no annotations, no reflection, no server component. What Axon resolves at startup, Strata resolves at compile time. |
| **KurrentDB / EventSourcingDB** | not a competitor; Strata is a library. A KurrentDB adapter for `EventStore` is on the roadmap. |
| **The DCB specification** | implemented faithfully: `Selection` is the spec's query, `AppendCondition::Dcb` is its append condition, and the same `Selection` also drives reads and subscriptions. |

## Acknowledgements

Strata would not exist without the people who worked out the ideas: the Decider pattern as articulated by Jérémie
Chassaing; the functional event sourcing practice of the Equinox and Emmett communities; Marten's projection
lifecycles; the Dynamic Consistency Boundaries specification by Sara Pellegrini, Bastian Waidelich, and Paul
Grimshaw; the accountants, who knew about reversals and closing the books long before we did; and the MoonBit team,
for a language in which all of this could finally be checked by a compiler.
