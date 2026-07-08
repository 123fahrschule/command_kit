# Design: First-Class Command Metadata

## Context

command_kit currently treats metadata as an untyped map/keyword passed separately to `dispatch/2` and threaded through the pipeline. The discarded `add_metadata_to_command` branch turned metadata into an app-defined typed schema (`use CommandKit.Metadata` + `field` macros), which guaranteed nothing about the five fields our services rely on, rejected arbitrary keys, exposed the `extra` persistence container in the public API, and broke the async path (metadata dropped by `dump_job`, structs crash `dump_metadata`, `resolve_metadata` missing in `dispatch_async`).

The reference semantics live in absence: `Shared.EventStore.Metadata` (`for_command/2`, `caused_by_event/2`), `Shared.URN`, and `extract_event_metadata/1` in the event consumer. Event fixtures under `test/fixtures/domain-events` show the CloudEvents shape (`id`, `type`, `correlation_id`, `causation_id`, `actor`, `time`).

The library is ~2 weeks old, `main` == `develop`, and no service integration exists yet — breaking changes are free.

## Goals / Non-Goals

**Goals:**
- Metadata is a library-owned struct with fixed semantics, present on every command from construction.
- Arbitrary additional metadata without any visible container concept.
- Command identity (id + name + source URN) as a command concern, not a metadata concern.
- Correlation helpers that fully replace `Shared.EventStore.Metadata` in services (both the command path and the event-listener path).
- One source of truth: metadata lives on the command; bus, middleware, serialization, and handlers all read from it.

**Non-Goals:**
- Event definition, event persistence, or event-store integration (events stay app-side; command_kit only produces the metadata map they carry).
- RabbitMQ consumption itself (only the extraction of correlation data from an already-decoded CloudEvents map).
- Migrating absence or other services (they integrate later; this change only makes the library ready).
- Persisting commands. Commands remain in-memory; that is exactly why they never appear mid-chain as `causation_id`.

## Decisions

### D1: Concrete struct, no schema DSL

`%CommandKit.Metadata{}` is defined by the library with exactly `causation_id`, `correlation_id`, `enacted_by`, `occurred_at`, `received_at`, plus one private container field (see D2). The branch's `use CommandKit.Metadata` / `field` macro DSL and `Metadata.Builder` casting layer are not carried over.

*Alternative considered:* keep the DSL and ship a base module with the five fields pre-declared. Rejected: the DSL's only job was validating app-declared field types, which fixed semantics make unnecessary; ~230 lines of macro machinery for zero benefit, and apps could still break the contract.

Validation is minimal and semantic: `enacted_by` must be a binary or `nil` (mirrors absence's guard), timestamps must be `DateTime`.

### D2: Internal extras container behind an accessor API

Additional metadata lives in an internal map field on the struct (e.g. `__extra__`, `@doc false`). "Internal" is honest rather than literal hiding — a struct field stays visible to pattern matching, `inspect`, and `Map.from_struct/1`; the contract is that it is not part of the documented API and its shape may change. The accessor surface:

- `CommandKit.Metadata.get(meta, key)` / `put(meta, key, value)` — known keys route to struct fields, unknown keys route to the container. Collisions are impossible by construction. Additional keys are atom-only (`is_atom` guard, matching absence's `Shared.EventStore.Metadata.set/3`); this prevents `"enacted_by"` vs `:enacted_by` ambiguity at persistence boundaries.
- The `Access` behaviour with the same routing, so `meta[:tenant_id]` works. `fetch/2` reads both kinds of keys. `pop/2` and the `:pop` branch of `get_and_update/3` work only for additional keys — popping a fixed field raises `ArgumentError`, because the five fields are structural and must not be removable via `pop_in/2`.
- `CommandKit.Metadata.to_map/1` flattens fixed fields and container into one flat map for event-store persistence. The container never appears as a nested key.
- An `Enumerable` implementation enumerates exactly the flat `to_map/1` view, so event stores that normalize metadata with `Enum.into(metadata, %{})` (as ours do) accept `%CommandKit.Metadata{}` directly: `append_event(event, command.metadata)`. Application-service helpers receive the metadata, not the whole command — metadata is the append/envelope context of a persisted event, never part of the domain event. `to_map/1` stays public and documented for stores that expect a plain map. Deliberately NOT introduced: any protocol on commands (commands stay commands) and any event protocol for attaching metadata to events.
- A custom `Inspect` implementation renders one flat view (fixed fields plus additional pairs) so the container name does not surface in logs and IEx output.

Docs never mention the container; it appears only in the struct definition, the `Inspect` and `Enumerable` implementations, and the serializer.

### D3: Command identity on the command, not in metadata

- `command_id`: UUID string generated inside `new/1` (commands are not persisted, so the id is created inline — events get theirs from the event store). Generated via `Ecto.UUID.generate()`; note that `ecto` is `optional: true` in mix.exs, so a core-only consumer must declare ecto itself — acceptable, since every fahrschule service already depends on ecto. A tiny `:crypto`-based v4 generator stays the documented fallback if that constraint ever bites.
- `command_name/0`: generated on each command module from the module's last segment, kebab-case (`RecordPayout` → `"record-payout"`), declared `defoverridable command_name: 0`. A guard raises `ArgumentError` when a name contains underscores (same rule as absence), including overridden names — checked at construction time so overrides are covered.
- `source:` option on the command base module (`use CommandKit.Ecto.Command, source: "de.123fahrschule:absence"`, same for `CommandKit.Core.Command`). Required when the base is used; the URN is `"<source>:<command_name>:<command_id>"`, built by a small public `CommandKit.URN` module (`generate/3`, `generate/2` for name+id against an explicit source).

*Alternative considered:* app-level `Application` config for the source. Rejected in favor of the base-module option (explicit, one obvious place, no global state); helpers that need a source outside a command context get it via generated wrappers on the base module (D5).

`:metadata` and `:command_id` become reserved param names — the params DSL raises at compile time if a command declares them.

### D4: Chain rules and construction defaults

`new/1` always builds metadata (never `nil`):

|                               | `causation_id`       | `correlation_id`                           | `enacted_by`    | `occurred_at`                | `received_at` |
| ----------------------------- | -------------------- | ------------------------------------------ | --------------- | ---------------------------- | ------------- |
| Chain start (default)         | URN(command)         | URN(command)                               | `nil`           | now (UTC)                    | now (UTC)     |
| After `caused_by(cmd, event)` | `"type:id"` of event | event's `correlation_id`, else `"type:id"` | event's `actor` | event's `time` (parsed, UTC) | now (UTC)     |

`caused_by/2` accepts the raw decoded CloudEvents map (`"type"`, `"id"`, `"correlation_id"`, `"actor"`, `"time"`) — the library absorbs absence's `extract_event_metadata/1` so services stop rewriting it. When the event carries its own `causation_id`, `caused_by/2` preserves it as the additional key `:original_causation_id` in the extras container (not a sixth fixed field — mirrors absence's `original_causation_id`). Commands never appear mid-chain: downstream events always inherit the command's metadata verbatim (`to_map/1`), so a command caused by an event passes the *event's* identity on, and only a chain-start command contributes its own URN.

### D5: Pipe-based API, centralized in `CommandKit.Command`

```elixir
RecordPayout.new!(params)
|> CommandKit.Command.caused_by(event)
|> CommandKit.Command.enacted_by("user-123")
|> CommandKit.Command.put_metadata(:tenant_id, "abc")
```

Functions live in one module (import-friendly), not as generated delegates on every command module — less macro surface, one place to document. `new/1` takes params only; there is no `new/2` metadata argument and no inline `:metadata` key (avoids the branch's reserved-key bug and keeps a single construction style). Beyond `put_metadata/3`, a bulk `put_metadata/2` accepts a keyword list or map (`put_metadata(command, tenant_id: "abc", locale: "de")`), so call sites like `put_metadata(command, current_metadata(socket))` don't degrade into pipe chains. `with_metadata/2` replaces the command's metadata with an already-built `%CommandKit.Metadata{}` — the primitive listener flows need to attach `caused_by_event`-derived metadata to a command before dispatching it.

For the event-listener path (event → event, no command involved), `CommandKit.Metadata.caused_by_event(metadata, event_name, event_id, source)` mirrors absence's `caused_by_event/2`: new causation = `URN(source, event_name, event_id)`, `correlation_id`/`enacted_by` inherited, name guard applied. `occurred_at` and `received_at` are both set to now (UTC): the follow-up event is a new fact occurring at derivation time, and the triggering event's own time stays reachable through the causation chain. The `source` argument accepts either the URN prefix string or a command base module (read via `__command_kit_source__/0`), so the prefix stays configured in one place and call sites read `Metadata.caused_by_event(meta, "employee-absence-added", event_id, MyApp.Command)`.

*Alternative considered:* a generated `caused_by_event/3` wrapper on the command base module with `source:` pre-applied. Rejected in review (2026-07-08): the receiver says "Command" while the return value is metadata — not discoverable — and it puts an event-to-event concern on a module whose job is defining commands. Keeping `CommandKit.Metadata` as the receiver makes the return type obvious.

### D6: Metadata parameter removed from bus, pipeline, and handlers

- `dispatch(command, opts \\ [])` and `dispatch_async(command, opts \\ [])` — no metadata argument.
- The command stays the single source of truth inside the pipeline too. `Pipeline` loses independently writable metadata state: middleware reads via `pipeline.command.metadata` (or a read-only `Pipeline.metadata/1` view) and writes only through `Pipeline.put_metadata/3`, which updates the command in the pipeline. This closes the gap where middleware would edit `pipeline.metadata` while an `execute/1` handler reads the untouched `command.metadata` — middleware changes are now visible to the handler by construction.
- Handler resolution: `execute/1` (command), else `execute/2` (command, context). `execute/3` and the metadata-carrying `execute/2` are removed; `MissingHandlerFunctionError` otherwise.
- Authorization behaviour signatures drop metadata analogously (authorizers read `command.metadata`).
- Idempotency middleware resolves its key via `CommandKit.Metadata.get/2` on the command's metadata so keys in the extras container are found. Its command fingerprint is redefined: hash over command module + declared params (via `__command_kit_params__/0`), explicitly excluding `command_id` and metadata. Today's whole-struct `term_to_binary` hash would make every freshly built command unique once `command_id` and timestamps exist, silently disabling idempotency for retries.

*Alternative considered:* keep an optional dispatch metadata argument merged over command metadata. Rejected: it recreates the two-sources-of-truth problem the branch had (`resolve_metadata` guard divergence between handler and middleware views).

### D7: Serialization round-trips identity and metadata

`dump_job/3` gains `"command_id"` and `"metadata"` (five fields plus flattened extras, keys tagged as today). `load_job/1` rebuilds the command via `new/1`-equivalent construction and then restores `command_id` and the metadata struct verbatim — defaults must not regenerate on load (a re-generated `command_id` would silently change chain-start causation semantics across the async hop). Extras values are restricted to the existing `dump_value/1` types; anything else raises `SerializationError`.

## Risks / Trade-offs

- [Extras values are unvalidated] → Intentional: opaque pass-through data. Keys are atom-only; values are constrained only at the serialization boundary (dump_value types), failing loudly.
- [`source:` required on base modules is a new compile-time obligation] → Clear `ArgumentError` at `use` time with an example; only one place per app.
- [CloudEvents `time` parsing may encounter offsets/garbage] → Parse with `DateTime.from_iso8601`, shift to UTC; raise a descriptive error on malformed input rather than storing `nil` silently.
- [Access behaviour on a struct can surprise (e.g. `meta[:causation_id]` vs `meta.causation_id`)] → Both work by design; docs show struct access for fixed fields and `get/2`/`[]` for extras.
- [Middleware that previously received caller-supplied dispatch metadata loses that channel] → By design; the replacement is `put_metadata/3` on the command before dispatch. Documented in the middleware guide.

## Migration Plan

None required: no service consumes command_kit yet. The `add_metadata_to_command` branch is discarded without merging; this change is implemented fresh from `main`. Rollback is `git revert` of the change commits.

## Open Questions

None — all decisions settled with Andreas (2026-07-08):

- `received_at` means "when the trigger reached the service": set at construction, serialized verbatim across async dispatch, never `nil`, never re-stamped. Execution time is already captured by the event store timestamp on resulting events; the Oban queue lag stays visible as store-timestamp minus `received_at`.
- `caused_by_event/4` sets `occurred_at = received_at = now` — a follow-up event is a new fact. The command flow deliberately differs: `caused_by/2` keeps the triggering event's time as `occurred_at` because the resulting domain event is the same real-world fact translated into our domain, matching absence's current behavior.
