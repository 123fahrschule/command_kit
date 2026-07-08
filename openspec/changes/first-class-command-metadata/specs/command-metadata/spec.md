# command-metadata Delta

## ADDED Requirements

### Requirement: Fixed metadata struct
The library SHALL define `%CommandKit.Metadata{}` with exactly five semantic fields: `causation_id`, `correlation_id`, `enacted_by`, `occurred_at`, and `received_at`. Applications MUST NOT be able to redefine, remove, or re-type these fields; there SHALL be no app-defined metadata schema DSL. Writes to fixed fields MUST be validated: `causation_id`, `correlation_id`, and `enacted_by` accept binaries or `nil`; `occurred_at` and `received_at` accept `DateTime`.

#### Scenario: Metadata struct exposes the five fields
- **WHEN** application code holds a `%CommandKit.Metadata{}` value
- **THEN** it can read `causation_id`, `correlation_id`, `enacted_by`, `occurred_at`, and `received_at` as struct fields

#### Scenario: enacted_by is validated
- **WHEN** metadata receives an `enacted_by` value that is neither a binary nor `nil`
- **THEN** the operation raises an `ArgumentError` identifying the invalid value

#### Scenario: Correlation ids are validated
- **WHEN** metadata receives a `causation_id` or `correlation_id` that is neither a binary nor `nil`, such as `put_metadata(command, :correlation_id, 123)`
- **THEN** the operation raises an `ArgumentError` identifying the invalid value

### Requirement: Metadata is always present on commands
Every command struct SHALL carry a `%CommandKit.Metadata{}` from construction. Chain-start defaults MUST be `causation_id = correlation_id = URN(command)`, `enacted_by = nil`, and `occurred_at = received_at =` the construction time in UTC.

#### Scenario: Freshly constructed command has chain-start metadata
- **WHEN** a command is built via `new/1` without any correlation input
- **THEN** its metadata has `causation_id` and `correlation_id` both equal to the command's URN, `enacted_by` is `nil`, and `occurred_at` equals `received_at`

#### Scenario: Metadata is never nil
- **WHEN** any command struct exists
- **THEN** `command.metadata` is a `%CommandKit.Metadata{}`, never `nil`

### Requirement: Arbitrary additional metadata behind an accessor API
Metadata SHALL accept arbitrary additional key-value pairs through `CommandKit.Metadata.get/2`, `CommandKit.Metadata.put/3`, and the `Access` behaviour. Additional keys MUST be atoms. The storage container for additional pairs MUST NOT be part of the documented API: known keys route to the fixed struct fields and unknown keys route to the internal container, so collisions between the two are impossible. The five fixed fields MUST NOT be removable: `pop/2` and the `:pop` branch of `get_and_update/3` work only for additional keys and raise `ArgumentError` for fixed fields. The struct's `Inspect` implementation SHALL render one flat view of fixed fields and additional pairs without surfacing the container name.

#### Scenario: Additional key is written and read
- **WHEN** application code calls `Metadata.put(meta, :tenant_id, "abc")` and later `Metadata.get(meta, :tenant_id)` or `meta[:tenant_id]`
- **THEN** it receives `"abc"` without referencing any container field

#### Scenario: Fixed key routes to the struct field
- **WHEN** application code calls `Metadata.put(meta, :enacted_by, "user-1")`
- **THEN** `meta.enacted_by` returns `"user-1"` and no duplicate entry exists in the internal container

#### Scenario: Access behaviour works for fixed and additional keys
- **WHEN** application code reads `meta[:causation_id]` or `meta[:tenant_id]`
- **THEN** the `Access` implementation returns the fixed field value or the additional value respectively

#### Scenario: String key is rejected
- **WHEN** application code calls `Metadata.put(meta, "tenant_id", "abc")`
- **THEN** the call raises an `ArgumentError` naming the atom-only rule

#### Scenario: Popping a fixed field raises
- **WHEN** application code calls `pop_in(meta[:causation_id])`
- **THEN** the operation raises an `ArgumentError`; popping an additional key like `meta[:tenant_id]` succeeds

#### Scenario: Inspect shows a flat view
- **WHEN** a metadata struct with additional pairs is passed to `inspect/1`
- **THEN** the output shows fixed fields and additional pairs together without the internal container name

### Requirement: Flat persistence map
`CommandKit.Metadata.to_map/1` SHALL return a single flat map containing the five fixed fields and all additional pairs at the top level, suitable for event-store persistence. The hidden container MUST NOT appear as a nested key. The struct SHALL additionally implement `Enumerable`, enumerating exactly the same flat view, so append functions that normalize metadata with `Enum.into(metadata, %{})` accept `%CommandKit.Metadata{}` directly. `to_map/1` remains public for stores that expect a plain map.

#### Scenario: Metadata with extras is flattened
- **WHEN** `to_map/1` is called on metadata with `enacted_by: "user-1"` and an additional `tenant_id: "abc"`
- **THEN** the result is a flat map containing both `enacted_by` and `tenant_id` as top-level keys and no container key

#### Scenario: Enumerable view equals the flat map
- **WHEN** application code calls `Enum.into(metadata, %{})`
- **THEN** the result equals `CommandKit.Metadata.to_map(metadata)` exactly

#### Scenario: Metadata passes directly to an append function
- **WHEN** an application service calls `append_event(event, command.metadata)` against an event store that collects metadata via `Enum.into/2`
- **THEN** the store persists the flat five-fields-plus-extras map without the caller flattening anything

### Requirement: Command caused by an external event
`CommandKit.Command.caused_by/2` SHALL accept a command and a raw decoded CloudEvents map (keys `"type"`, `"id"`, `"correlation_id"`, `"causation_id"`, `"actor"`, `"time"`) and set `causation_id = "type:id"` of the event, `correlation_id` to the event's `correlation_id` (falling back to `"type:id"`), `enacted_by` to the event's `actor`, `occurred_at` to the event's parsed UTC time, and `received_at` to now. When the event carries its own `causation_id`, it SHALL be preserved as the additional metadata key `:original_causation_id`. Commands MUST NOT appear as `causation_id` of any downstream message when they were themselves caused by an event.

#### Scenario: Command built from a RabbitMQ event
- **WHEN** a consumer pipes a command through `caused_by(command, event)` with a CloudEvents map
- **THEN** the command metadata carries the event's identity as causation and inherits its correlation and actor

#### Scenario: Original causation is preserved
- **WHEN** the CloudEvents map contains a `causation_id`
- **THEN** the command's metadata exposes it as the additional key `:original_causation_id`

#### Scenario: Event without correlation_id
- **WHEN** the CloudEvents map has no `correlation_id`
- **THEN** the command's `correlation_id` equals the event's `"type:id"`

#### Scenario: Malformed event time
- **WHEN** the CloudEvents map contains a `time` value that cannot be parsed as ISO 8601
- **THEN** `caused_by/2` raises a descriptive error instead of storing `nil`

### Requirement: Pipe-based metadata construction
The library SHALL provide pipe-friendly functions in `CommandKit.Command` — at minimum `caused_by/2`, `enacted_by/2`, `put_metadata/3`, a bulk `put_metadata/2` accepting a keyword list or map, and `with_metadata/2` replacing the command's metadata with an already-built `%CommandKit.Metadata{}` (for listener flows that derive metadata via `caused_by_event` first) — that take a command and return the command with updated metadata. These functions SHALL NOT be generated onto individual command modules.

#### Scenario: Command is enriched via pipes
- **WHEN** a caller writes `RecordPayout.new!(params) |> CommandKit.Command.enacted_by("user-123") |> CommandKit.Command.put_metadata(:tenant_id, "abc")`
- **THEN** the resulting command's metadata contains the actor and the additional pair

#### Scenario: Bulk metadata assignment
- **WHEN** a caller writes `CommandKit.Command.put_metadata(command, tenant_id: "abc", locale: "de")`
- **THEN** the resulting command's metadata contains both pairs without requiring a pipe chain

#### Scenario: Derived metadata is attached wholesale
- **WHEN** a listener writes `command |> CommandKit.Command.with_metadata(Metadata.caused_by_event(meta, "employee-absence-added", event_id, MyApp.Command))`
- **THEN** the command carries the derived metadata; values that are not a `%CommandKit.Metadata{}` are rejected

### Requirement: Event-listener correlation
`CommandKit.Metadata.caused_by_event/4` SHALL derive follow-up event metadata from an incoming persisted event's metadata: `causation_id` becomes `URN(source, event_name, event_id)` while `correlation_id` and `enacted_by` are inherited. `occurred_at` and `received_at` MUST both be set to the derivation time (UTC) — the follow-up event is a new fact; the triggering event's own time stays reachable through the causation chain. Event names containing underscores MUST be rejected with an `ArgumentError` suggesting the kebab-case form. The `source` argument SHALL accept either the URN prefix string or a command base module carrying the `source:` configuration; the function lives on `CommandKit.Metadata` (not on command modules) so the receiver announces the return type.

#### Scenario: Event listener correlates a follow-up event
- **WHEN** an event listener calls `caused_by_event(meta, "employee-absence-added", event_id, source)`
- **THEN** the result carries `causation_id = URN(source, "employee-absence-added", event_id)` with `correlation_id` and `enacted_by` copied from the incoming metadata

#### Scenario: Derived metadata carries fresh timestamps
- **WHEN** `caused_by_event` derives metadata from an event that occurred in the past
- **THEN** the derived metadata's `occurred_at` and `received_at` are both the derivation time, not the triggering event's time

#### Scenario: Underscored event name is rejected
- **WHEN** `caused_by_event` receives `"employee_absence_added"`
- **THEN** it raises an `ArgumentError` suggesting `"employee-absence-added"`

#### Scenario: Command base module supplies the source
- **WHEN** listener code calls `Metadata.caused_by_event(meta, "employee-absence-added", event_id, MyApp.Command)`
- **THEN** the URN uses the `source:` configured on `MyApp.Command`; a module without that configuration raises an `ArgumentError`

### Requirement: URN generation
The library SHALL expose a `CommandKit.URN` module that builds URNs of the form `"<source>:<name>:<id>"` from an explicit source, a kebab-case name, and an id.

#### Scenario: URN is generated for a command
- **WHEN** `CommandKit.URN.generate("de.123fahrschule:absence", "record-payout", uuid)` is called
- **THEN** it returns `"de.123fahrschule:absence:record-payout:" <> uuid`
