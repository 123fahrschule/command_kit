# First-Class Command Metadata

## Why

Commands need correlation metadata (who acted, what caused them, when) to participate in the causation/correlation chains our services build across the event store and RabbitMQ (see absence's `Shared.EventStore.Metadata`). The `add_metadata_to_command` branch attempted this as an app-defined typed-field DSL, which inverts the model: the five core fields are not guaranteed, arbitrary extra metadata is rejected, the `extra` persistence container leaks into the public API, and the async path silently loses or crashes on metadata. That branch is discarded; this change replaces it with metadata as a fixed, always-present, library-owned concept.

## What Changes

- New `%CommandKit.Metadata{}` struct owned by the library with exactly five semantic fields: `causation_id`, `correlation_id`, `enacted_by`, `occurred_at`, `received_at`. No app-defined metadata schema DSL.
- Arbitrary additional metadata is supported via a hidden container reachable only through `get`/`put`/Access; the container never appears in the public API. `Metadata.to_map/1` flattens it transparently for event-store persistence.
- Every command carries metadata from construction — never `nil`. Chain-start defaults: `causation_id = correlation_id = URN(command)`, `occurred_at = received_at = now`.
- Commands gain an identity: `command_id` (UUID generated in `new/1`; commands are not persisted) and `command_name` (kebab-case, derived from the module name, overridable via `defoverridable`). A `source:` option on the command base module supplies the URN prefix.
- Chain rule: commands never appear mid-chain as `causation_id` (dead link — commands are not persisted). A command caused by an external event takes `causation_id = "type:id"` of the event and inherits `correlation_id`/`enacted_by`.
- Pipe-based construction API in `CommandKit.Command`: `caused_by/2` (accepts a raw CloudEvents map), `enacted_by/2`, `put_metadata/3`.
- Correlation helpers replacing absence's `Shared.EventStore.Metadata` for both paths: command-mediated correlation (metadata inherited verbatim by events) and event-listener correlation (`caused_by_event`: causation = URN from event name + event id).
- **BREAKING**: The separate metadata parameter is removed everywhere. `dispatch(command)` replaces `dispatch(command, metadata)`; handlers become `execute/1` or `execute/2` (command, context); `pipeline.metadata` is populated from `command.metadata`.
- **BREAKING**: Async serialization dumps and reloads `command.metadata` (today the Oban path drops it, and metadata structs crash `dump_metadata`).
- Middleware (idempotency, authorization, telemetry, logging, error handler) reads metadata through the metadata accessor API; middleware metadata changes go through the pipeline onto the command itself, so handlers always see them.
- The idempotency fingerprint is redefined to command module + declared params (excluding `command_id` and metadata) — the current whole-struct hash would make every rebuilt command unique once identity and timestamps exist.
- All guides updated: README, commands, new metadata guide, async, pipelines-and-middleware, context.

Breaking changes are acceptable: the library is ~2 weeks old and not yet integrated into any service. `main` and `develop` point at the same commit; the `add_metadata_to_command` branch is discarded, not merged.

## Capabilities

### New Capabilities

- `command-metadata`: The `%CommandKit.Metadata{}` struct — five fixed fields, hidden extras container with accessor API, chain-start defaults, CloudEvents extraction (`caused_by`), event-listener correlation (`caused_by_event`), `to_map/1` flattening, and command identity (`command_id`, `command_name`, `source:` URN prefix).

### Modified Capabilities

- `command-definition`: Commands always carry metadata from `new/1`; command base modules accept a `source:` option; command modules expose an overridable `command_name/0` and a generated `command_id`.
- `command-dispatch`: `dispatch/1` (plus opts) without a metadata parameter; handler resolution changes to `execute/1` then `execute/2` (command, context); `pipeline.metadata` comes from the command.
- `command-middleware`: Middleware contracts read metadata from the command-sourced pipeline metadata via the accessor API (notably idempotency key lookup).
- `async-dispatch`: Job serialization round-trips `command.metadata` (fixed fields plus extras) alongside params.
- `library-documentation`: Guides document the metadata concept, the new dispatch/handler signatures, and correlation helpers.

## Impact

- **Code**: `lib/command_kit/metadata.ex` and `lib/command_kit/metadata/` (new implementation replaces the branch's DSL approach), `core/command/schema.ex`, `core/command/builder.ex`, `ecto/command/builder.ex`, `bus.ex`, `pipeline.ex`, `serialization.ex`, `middleware/*.ex`, `async/*`.
- **APIs**: `dispatch/2`→`dispatch/1` (metadata param removed), handler behaviour arities, command constructor semantics (identity + metadata defaults). All breaking, all pre-integration.
- **Docs**: README plus all guides under `docs/guides/`.
- **Downstream**: absence (and later services) will replace `Shared.EventStore.Metadata`, `Shared.URN` usage in application services, and `extract_event_metadata/1` in event consumers with the library equivalents when they integrate command_kit; no service integration exists yet, so no migration is required now.
