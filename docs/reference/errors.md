# Errors

Strata's own errors are `pub(all) suberror`s; domain rejections are *your* `suberror`s and propagate through the
runtime unchanged. Catch a specific one with `try ... catch { @strata.StreamConflict(..) => ... }`.

## core

| Error | Raised by | Meaning |
|---|---|---|
| `AppendConflict::StreamConflict(stream~, expected~, actual~)` | `EventStore::append`, `CommandHandler::execute` | the stream is not at the expected version; safe to re-read and re-decide (`Retry::on_conflict`) |
| `AppendConflict::BoundaryConflict(selection~, after~, at~)` | `EventStore::append`, `DcbHandler::execute` | an event matching the scope landed at `at`, after the head `after` the handler observed |
| `IdempotencyConflict::KeyReused(key~, stream~)` | `execute` | a *different* command was submitted under a known idempotency key |
| `DecodeError(event_type~, position~, reason~)` | `JsonCodec::decode`, `Page::decode`, folds | a stored payload does not decode as the current type; `position` is `None` when encoding |
| `InvalidStreamId(String)` | `StreamId::parse` | not `category-id` or `tenant/category-id` |
| `InvalidInstant(String)` | `Instant::parse`, `Clock::parse_fixed` | not a valid ISO-8601 instant (rejects `:60`, hour 24, impossible dates) |
| `InvalidTag(Tag)` | `NewEvent::NewEvent`, `append` | user code tried to create a `$`-prefixed system tag |
| `NotImplemented(String)` | `todo(name)` | a stub; today only `store/pg` |

## store

| Error | Raised by | Meaning |
|---|---|---|
| `KeySealed(subject~)` | `KeyStore::key_for` | the key exists but is withheld; read through `Runtime::unseal` |
| `KeyDestroyed(subject~)` | `KeyStore::key_for`, `unseal` | the subject was forgotten; permanent |
| `KeyMissing(subject~)` | `KeyStore::unseal` | no key was ever created; `unseal` never creates one |

## runtime

| Error | Raised by | Meaning |
|---|---|---|
| `StreamTerminal::Terminal(stream~)` | `CommandHandler::execute` | the folded state is `is_terminal`; `decide` was not called |
| `WaitTimeout(waiting_for~, reached~)` | `Projector::wait_for` | the projector did not pass the position in time |

## Cancellation

`moonbitlang/async` cancellation is not an error a handler should catch. Reactors treat it as a stop, not a failure:
no retry, no dead letter, checkpoint unchanged.
