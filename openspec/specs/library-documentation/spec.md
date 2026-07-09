# library-documentation Specification

## Purpose
TBD - created by archiving change extract-command-kit-library. Update Purpose after archive.
## Requirements
### Requirement: README quickstart
The library SHALL include a README that explains installation, minimal command definition, bus setup, pipeline configuration, and synchronous dispatch.

#### Scenario: New consumer reads quickstart
- **WHEN** a developer follows the README quickstart
- **THEN** they can define a command, configure a bus, register a handler, and dispatch the command

### Requirement: Command authoring guide
The library SHALL document command authoring for core commands and Ecto-backed commands.

#### Scenario: Developer chooses command implementation
- **WHEN** a developer reads the command authoring guide
- **THEN** they can choose between `CommandKit.Core.Command` and `CommandKit.Ecto.Command` and understand the trade-off

#### Scenario: Developer defines typed params
- **WHEN** a developer reads the params documentation
- **THEN** they understand supported field types, required-by-default behavior, constructor results, and introspection

#### Scenario: Developer handles construction errors
- **WHEN** a developer reads the command authoring guide
- **THEN** they understand `CommandKit.CommandError`, `CommandKit.ParamError`, and how to map construction errors to UI or API errors

#### Scenario: Developer declares command handler
- **WHEN** a developer reads the command authoring guide
- **THEN** they understand how to declare a command handler with the command DSL

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
- **THEN** they understand how to inject runtime services such as repositories, mailers, HTTP clients, clocks, UUID generators, storage adapters, provider clients, and test doubles into `execute/3` handlers

#### Scenario: Developer uses namespaced context keys
- **WHEN** a developer reads the runtime context documentation
- **THEN** they understand why namespaced tuple keys such as `{MyApp, :repo}` are recommended for context values

#### Scenario: Developer avoids serializing context
- **WHEN** a developer reads the runtime context documentation
- **THEN** they understand that context is runtime-only and is not serialized by async adapters

### Requirement: Async guide
The library SHALL document async dispatch through TaskSupervisor and Oban adapters.

#### Scenario: Developer configures TaskSupervisor async
- **WHEN** a developer follows the TaskSupervisor async guide
- **THEN** they can configure non-durable async dispatch

#### Scenario: Developer configures Oban async
- **WHEN** a developer follows the Oban async guide
- **THEN** they can configure durable async dispatch and understand command serialization requirements

### Requirement: Public API moduledocs
Public modules SHALL include moduledocs that describe purpose, key functions, options, and examples.

#### Scenario: Developer opens generated docs
- **WHEN** a developer views generated documentation for public modules
- **THEN** each public module explains its role and links to related command, bus, middleware, or async APIs

### Requirement: Testing documentation
The library SHALL document recommended testing patterns for commands, handlers, middleware, pipelines, and async adapters.

#### Scenario: Developer tests middleware
- **WHEN** a developer reads testing documentation
- **THEN** they can test middleware behavior without running an entire application

#### Scenario: Developer tests async dispatch
- **WHEN** a developer reads async testing documentation
- **THEN** they can test TaskSupervisor and Oban-backed dispatch behavior deterministically

