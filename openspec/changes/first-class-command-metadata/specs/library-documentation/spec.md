# library-documentation Delta

## MODIFIED Requirements

### Requirement: README quickstart
The library SHALL include a README that explains installation, minimal command definition (including the `source:` option), bus setup, pipeline configuration, metadata construction via pipes, and synchronous dispatch of a single command argument.

#### Scenario: New consumer reads quickstart
- **WHEN** a developer follows the README quickstart
- **THEN** they can define a command base with `source:`, define a command, configure a bus, register an `execute/1` handler, enrich a command with `enacted_by`, and dispatch it with `dispatch(command)`

### Requirement: Pipeline and middleware guide
The library SHALL document named pipelines, middleware ordering, built-in middleware, runtime context use cases, and custom middleware authoring.

#### Scenario: Developer configures multiple pipelines
- **WHEN** a developer follows the pipeline guide
- **THEN** they can configure at least two named pipelines and select one during dispatch

#### Scenario: Developer writes custom middleware
- **WHEN** a developer follows the middleware guide
- **THEN** they can implement middleware that continues, transforms, or halts the pipeline

#### Scenario: Developer follows result conventions
- **WHEN** a developer reads the pipeline and middleware guide
- **THEN** they understand the recommended result shapes `:ok`, `{:ok, value}`, and `{:error, reason}` and how built-in middleware tags other return values generically

#### Scenario: Developer evaluates context use cases
- **WHEN** a developer reads the runtime context documentation
- **THEN** they understand appropriate use cases such as execution-time dependency injection, resolved actors, tenant context, feature flags, locks, transaction handles, Ecto repositories, optional Ecto.Multi accumulation, telemetry correlation state, and authorization state

#### Scenario: Developer uses context for dependency injection
- **WHEN** a developer reads the runtime context documentation
- **THEN** they understand how to inject runtime services such as repositories, mailers, HTTP clients, clocks, UUID generators, storage adapters, provider clients, and test doubles into `execute/2` handlers

#### Scenario: Developer uses namespaced context keys
- **WHEN** a developer reads the runtime context documentation
- **THEN** they understand why namespaced tuple keys such as `{MyApp, :repo}` are recommended for context values

#### Scenario: Developer avoids serializing context
- **WHEN** a developer reads the runtime context documentation
- **THEN** they understand that context is runtime-only and is not serialized by async adapters

#### Scenario: Developer learns metadata middleware access
- **WHEN** a developer reads the middleware guide
- **THEN** they understand that pipeline metadata comes from the command and that additional keys are read via the metadata accessor API

## ADDED Requirements

### Requirement: Metadata guide
The library SHALL document the metadata concept in a dedicated guide: the five fixed fields and their semantics, chain-start defaults, the rule that commands never appear mid-chain as causation, `caused_by/2` with CloudEvents input, `caused_by_event` for event listeners, pipe-based construction, additional metadata via `get`/`put`/Access, and `to_map/1` for event-store persistence. The guide MUST NOT document the internal extras container.

#### Scenario: Developer correlates a command from an event
- **WHEN** a developer follows the metadata guide's consumer example
- **THEN** they can build a command from a CloudEvents map so its metadata carries the event's causation and correlation

#### Scenario: Developer attaches arbitrary metadata
- **WHEN** a developer follows the metadata guide
- **THEN** they can attach and read additional keys without encountering any container concept

#### Scenario: Developer persists metadata with events
- **WHEN** a developer follows the metadata guide's application-service example
- **THEN** they append events with `Metadata.to_map(command.metadata)` and understand that events inherit command metadata verbatim
