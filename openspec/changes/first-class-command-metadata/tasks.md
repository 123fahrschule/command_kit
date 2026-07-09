# Tasks: First-Class Command Metadata

## 1. Remove the discarded branch approach

- [x] 1.1 Confirm work starts from `main` (branch `add_metadata_to_command` is discarded, not merged); ensure none of its `CommandKit.Metadata` DSL / `Metadata.Builder` code is carried over

## 2. Metadata struct and accessor API

- [x] 2.1 Implement `CommandKit.Metadata` struct with `causation_id`, `correlation_id`, `enacted_by`, `occurred_at`, `received_at` and an internal extras container field (`@doc false`)
- [x] 2.2 Implement `get/2` and `put/3` routing known keys to struct fields and unknown keys to the container; additional keys atom-only (`ArgumentError` for non-atoms); validate `enacted_by` (binary or nil) and timestamps (`DateTime`)
- [x] 2.3 Implement the `Access` behaviour with the same routing; `pop/2` and `:pop` in `get_and_update/3` only for additional keys — fixed fields raise `ArgumentError`
- [x] 2.4 Implement `to_map/1` flattening fixed fields and extras into one flat map
- [x] 2.5 Implement a custom `Inspect` that renders one flat view without surfacing the container name
- [x] 2.6 Tests: field access, extras routing, Access, collision-free `put`, atom-only key rejection, pop restrictions, `to_map` flattening, Inspect output, `enacted_by` validation

## 3. URN and command identity

- [x] 3.1 Implement `CommandKit.URN.generate/3` (`"<source>:<name>:<id>"`)
- [x] 3.2 Add required `source:` option to `CommandKit.Core.Command` and `CommandKit.Ecto.Command` `use`; raise `ArgumentError` with an example when missing
- [x] 3.3 Generate `command_name/0` on command modules (kebab-case from module last segment) with `defoverridable command_name: 0`
- [x] 3.4 Add `command_id` to the command struct, generated as UUID in `new/1`; enforce the underscore guard on `command_name/0` at construction time (covers overrides)
- [x] 3.5 Reserve `:metadata` and `:command_id` as param names — compile-time error in the params DSL
- [x] 3.6 Tests: name derivation, override, underscore rejection, unique ids, missing `source:`, reserved params

## 4. Construction defaults and pipe API

- [x] 4.1 Build chain-start metadata in `new/1`/`new!/1` (both core and Ecto builders): causation = correlation = URN(command), `enacted_by` nil, `occurred_at` = `received_at` = `DateTime.utc_now()`
- [x] 4.2 Implement `CommandKit.Command.caused_by/2` accepting a raw CloudEvents map (`"type"`, `"id"`, `"correlation_id"`, `"causation_id"`, `"actor"`, `"time"`): causation `"type:id"`, correlation with fallback, actor, parsed UTC `occurred_at`, fresh `received_at`; preserve the event's `causation_id` as additional key `:original_causation_id`; raise a descriptive error on malformed `time`
- [x] 4.3 Implement `CommandKit.Command.enacted_by/2`, `put_metadata/3`, and bulk `put_metadata/2` (keyword or map)
- [x] 4.4 Implement `CommandKit.Metadata.caused_by_event/4` (URN from event name + id, inherit correlation/enacted_by, `occurred_at` = `received_at` = now UTC, underscore guard); the source argument accepts the prefix string or a command base module (no wrapper on the base module — receiver stays `Metadata`)
- [x] 4.5 Tests: chain-start defaults, caused_by against a fixture-shaped CloudEvents map (absence `test/fixtures/domain-events`), fallback correlation, `:original_causation_id` preservation, malformed time, bulk put_metadata, caused_by_event inheritance/timestamps/guard

## 5. Bus, pipeline, and handler signatures

- [x] 5.1 Change bus API to `dispatch(command, opts \\ [])` and `dispatch_async(command, opts \\ [])` — remove the metadata parameter from bus modules, `CommandKit.Bus`, and adapter behaviour signatures
- [x] 5.2 Make the command the single metadata source in the pipeline: remove independently writable pipeline metadata state, provide a read view plus `Pipeline.put_metadata/3` that updates `pipeline.command` (middleware changes must reach `execute/1` handlers), in both sync and async paths
- [x] 5.3 Change handler resolution to `execute/1` then `execute/2` (command, context); remove metadata-carrying arities; update `MissingHandlerFunctionError` message
- [x] 5.4 Update authorization behaviour/callbacks to (command, context) — authorizers read `command.metadata`
- [x] 5.5 Update idempotency middleware: resolve the key via `CommandKit.Metadata.get/2` (finds keys in extras) and redefine the fingerprint as hash over command module + declared params (via `__command_kit_params__/0`), explicitly excluding `command_id` and metadata
- [x] 5.6 Review telemetry, logging, error-handler middleware for metadata assumptions (struct instead of map/keyword)
- [x] 5.7 Tests: dispatch without metadata arg, handler arity resolution, middleware metadata change visible in handler, idempotency key from extras, rebuilt command fingerprints identically, authorization signature

## 6. Async serialization

- [x] 6.1 Extend `dump_job` / `load_job` to round-trip `command_id` and the full metadata (fixed fields + extras) using the existing typed `dump_value`/`load_value` encoding; construction defaults must not regenerate on load
- [x] 6.2 Raise `SerializationError` for extras values outside the supported type set
- [x] 6.3 Update the Oban worker and TaskSupervisor adapter for the new signatures
- [x] 6.4 Tests: full metadata round-trip through Oban job args (identical `command_id`, causation/correlation, timestamps, extras), unsupported extras value, context still not serialized

## 7. Documentation

- [x] 7.1 Rewrite `docs/guides/metadata.md`: five fields and semantics, chain rules (commands never mid-chain), pipe construction, `caused_by`/`caused_by_event`, extras via `get`/`put`/Access (no container concept), `to_map/1` for event appends
- [x] 7.2 Update README quickstart: `source:` on the base module, `execute/1` handler, pipe-based metadata, `dispatch(command)`
- [x] 7.3 Update `docs/guides/commands.md` (constructors, identity, handler DSL, reserved params) and `docs/guides/context.md` (`execute/2` references)
- [x] 7.4 Update `docs/guides/pipelines-and-middleware.md` (pipeline metadata sourced from the command, accessor API) and `docs/guides/async.md` (no metadata argument, metadata round-trip)
- [x] 7.5 Update moduledocs of all touched public modules

## 8. Verification

- [x] 8.1 Full test suite green (`mix test`)
- [x] 8.2 Sweep for leftovers: no `dispatch(command, metadata)` call sites, no `execute/3`, no public mention of the extras container, no remaining branch DSL references in docs or code

## 9. Incremental migration guide (added during apply)

- [x] 9.1 Implement `CommandKit.Command.with_metadata/2` (attach `caused_by_event`-derived metadata to a command in listener flows) with tests
- [x] 9.2 Write `docs/guides/migration.md`: base modules/config first, then per-application-service conversion (incl. multi-event handlers and event-caused-by-event), inbound RabbitMQ consumers via `caused_by/2`, internal listeners (event → command → event) via `with_metadata/2` + `caused_by_event/4`, cleanup sweep; link from README and metadata guide

## 10. Review fixes (Codex, added during apply)

- [x] 10.1 P1: preserve integer map keys across durable serialization (maps with non-string keys dump as a tagged entry list that survives JSON) + JSON round-trip test
- [x] 10.2 P2: reject `source:` override at the command level with a compile-time `ArgumentError` (source is application-wide, configured once on the base)
- [x] 10.3 P2: validate `causation_id`/`correlation_id` as binary-or-nil on every fixed-field write (code now matches the metadata guide's "types are validated" claim)
- [x] 10.4 P3: register `docs/guides/metadata.md` and `docs/guides/migration.md` in ExDoc extras; fix `use CommandKit.Ecto.Command` example in the top-level moduledoc to include `source:`
- [x] 10.5 Migration-guide examples use `use Absence, :application_service` instead of `use Absence.Includes, :application_service`

## 11. Metadata as Enumerable (added during apply)

- [x] 11.1 Implement `Enumerable` for `CommandKit.Metadata`, enumerating exactly the flat `to_map/1` view, so `append_event(event, command.metadata)` works against stores that call `Enum.into(metadata, %{})`; no command-level or event protocol introduced
- [x] 11.2 Tests: `Enum.into(metadata, %{}) == to_map(metadata)`, simulated event-store append, count/membership over the flat view
- [x] 11.3 Guides: metadata guide explains direct append via Enumerable with `to_map/1` as explicit alternative; migration guide call sites pass `command.metadata` (helpers receive metadata, not the command)

## 12. CodeRabbit review fixes (added during apply)

- [x] 12.1 `Code.ensure_loaded?` before `function_exported?` in authorization middleware (and error-handler reporter, same defect class)
- [x] 12.2 `get_and_update/3` gets the same atom-only `ArgumentError` guard as the other Access callbacks
- [x] 12.3 Oban worker propagates `{:error, reason}` dispatch results instead of always returning `:ok`, so failed commands retry
- [x] 12.4 `from_cloud_event/2` validates the event-supplied `correlation_id` like every other fixed-field write
- [x] 12.5 Docs: migration call-site example uses `new/1` + `with` (error-tuple flow); README clarifies `enacted_by` starts as `nil`; metadata guide wording aligned with direct `append_event(event, metadata)` style
- [x] 12.6 JSON round-trip test guarded for Elixir >= 1.18 (library keeps supporting 1.17); shadow-proof test strengthened
- [x] 12.7 Oban worker handles `:unchanged` explicitly and logs non-standard dispatch results instead of silently mapping them to `:ok` (deliberately NOT failing them — unknown shapes are tolerated success per result conventions, failing would retry successful commands)
- [x] 12.8 `validate_source!` rejects whitespace-only sources; idempotency fingerprint uses `:erlang.term_to_binary([:deterministic])`
- [x] 12.9 Symmetric reserved-field test through the Ecto base; explanatory comment on the nested base `__using__/1` macro
