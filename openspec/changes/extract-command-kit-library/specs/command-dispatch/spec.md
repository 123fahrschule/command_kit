## ADDED Requirements

### Requirement: Command bus modules
The library SHALL allow applications to define command bus modules that dispatch command structs through configured pipelines.

#### Scenario: Application defines a command bus
- **WHEN** an application defines a module using the command bus API with an `otp_app`
- **THEN** the module exposes dispatch functions backed by that application's configuration

### Requirement: Multiple named pipelines
The command bus MUST support multiple named pipelines and a configured default pipeline.

#### Scenario: Dispatch uses default pipeline
- **WHEN** a caller dispatches a command without specifying a pipeline
- **THEN** the bus executes the command through the configured default pipeline

#### Scenario: Dispatch selects named pipeline
- **WHEN** a caller dispatches a command with `pipeline: :system`
- **THEN** the bus executes the command through the `:system` pipeline

#### Scenario: Unknown pipeline
- **WHEN** a caller selects a pipeline that is not configured
- **THEN** dispatch fails with a configuration error that identifies the unknown pipeline

### Requirement: Handler resolution
The command bus SHALL resolve a handler for each command before executing the command.

#### Scenario: Command has execute arity 3 handler
- **WHEN** the bus reaches the end of the selected pipeline for a command whose handler exports `execute/3`
- **THEN** it calls the handler with command, metadata, and context

#### Scenario: Command has execute arity 2 handler
- **WHEN** the bus reaches the end of the selected pipeline for a command whose handler exports `execute/2` but not `execute/3`
- **THEN** it calls the handler with command and metadata

#### Scenario: Command has no handler
- **WHEN** the bus reaches handler execution for a command without a registered handler
- **THEN** dispatch fails with an actionable missing-handler error

#### Scenario: Handler exports no supported execute function
- **WHEN** the resolved handler exports neither `execute/2` nor `execute/3`
- **THEN** dispatch fails with an actionable missing-handler-function error

### Requirement: Runtime execution context
The command bus SHALL create a runtime `CommandKit.Context` for each command execution and pass it through the selected pipeline.

#### Scenario: Middleware adds context value
- **WHEN** middleware stores a value in the execution context
- **THEN** later middleware and `execute/3` handlers can read that value through the context API

#### Scenario: Handler does not opt into context
- **WHEN** a handler only exports `execute/2`
- **THEN** dispatch succeeds without requiring the handler to know about the execution context

#### Scenario: Context is runtime-only
- **WHEN** command execution completes
- **THEN** the execution context is not included in the command struct or returned as serialized command data

#### Scenario: Context uses namespaced keys
- **WHEN** middleware stores a value with a namespaced tuple key such as `{MyApp, :repo}`
- **THEN** later middleware and `execute/3` handlers can retrieve that value with the same key

#### Scenario: Context returns default value
- **WHEN** code reads a missing context key with a provided default
- **THEN** the context API returns the default value

#### Scenario: Context fetch raises for missing value
- **WHEN** code calls the raising fetch API for a missing context key
- **THEN** the context API raises an actionable missing-context-value error

#### Scenario: Bus does not inject dependencies automatically
- **WHEN** a command execution starts without dependency-injection middleware
- **THEN** the runtime context does not contain application dependencies by default

### Requirement: Metadata propagation
The command bus SHALL propagate caller-provided metadata through middleware and into the handler without merging domain-specific fields by default.

#### Scenario: Metadata reaches handler
- **WHEN** a caller dispatches a command with metadata
- **THEN** middleware and the handler receive that metadata

#### Scenario: Metadata is updated by middleware
- **WHEN** middleware adds a metadata value to the pipeline
- **THEN** later middleware and the handler receive the updated metadata

### Requirement: Dispatch result
Synchronous dispatch SHALL return the final pipeline result to the caller.

#### Scenario: Handler returns success
- **WHEN** a handler returns `{:ok, value}`
- **THEN** dispatch returns `{:ok, value}`

#### Scenario: Middleware halts with result
- **WHEN** middleware halts the pipeline with `{:error, :unauthorized}`
- **THEN** dispatch returns `{:error, :unauthorized}` and does not call the handler

### Requirement: Pipeline execution order
The command bus MUST execute middleware in configured order before the handler and unwind post-processing in reverse order.

#### Scenario: Middleware wraps handler
- **WHEN** a pipeline is configured as `[Outer, Inner]`
- **THEN** `Outer` runs before `Inner`, `Inner` runs before the handler, and `Outer` observes the final result after `Inner`
