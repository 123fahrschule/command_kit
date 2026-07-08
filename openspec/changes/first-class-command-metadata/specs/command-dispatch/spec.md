# command-dispatch Delta

## MODIFIED Requirements

### Requirement: Handler resolution
The command bus SHALL resolve a handler for each command before executing the command. The bus calls `execute/1` with the command when the handler exports it, otherwise `execute/2` with the command and the runtime context. Metadata is not a handler argument; handlers read it via `command.metadata`.

#### Scenario: Command has execute arity 1 handler
- **WHEN** the bus reaches the end of the selected pipeline for a command whose handler exports `execute/1`
- **THEN** it calls the handler with the command only

#### Scenario: Command has execute arity 2 handler
- **WHEN** the bus reaches the end of the selected pipeline for a command whose handler exports `execute/2` but not `execute/1`
- **THEN** it calls the handler with the command and the runtime context

#### Scenario: Command has no handler
- **WHEN** the bus reaches handler execution for a command without a registered handler
- **THEN** dispatch fails with an actionable missing-handler error

#### Scenario: Handler exports no supported execute function
- **WHEN** the resolved handler exports neither `execute/1` nor `execute/2`
- **THEN** dispatch fails with an actionable missing-handler-function error

### Requirement: Runtime execution context
The command bus SHALL create a runtime `CommandKit.Context` for each command execution and pass it through the selected pipeline.

#### Scenario: Middleware adds context value
- **WHEN** middleware stores a value in the execution context
- **THEN** later middleware and `execute/2` handlers can read that value through the context API

#### Scenario: Handler does not opt into context
- **WHEN** a handler only exports `execute/1`
- **THEN** dispatch succeeds without requiring the handler to know about the execution context

#### Scenario: Context is runtime-only
- **WHEN** command execution completes
- **THEN** the execution context is not included in the command struct or returned as serialized command data

#### Scenario: Context uses namespaced keys
- **WHEN** middleware stores a value with a namespaced tuple key such as `{MyApp, :repo}`
- **THEN** later middleware and `execute/2` handlers can retrieve that value with the same key

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
The dispatched command's metadata SHALL be the single source of truth throughout the pipeline. Dispatch functions MUST NOT accept a separate metadata argument; `dispatch/1` and `dispatch/2` (command, opts) are the only synchronous entry points. Middleware SHALL read metadata from the command in the pipeline and update it only through a pipeline API that updates the command itself, so handlers always observe middleware changes.

#### Scenario: Command metadata reaches middleware
- **WHEN** a caller dispatches a command whose metadata carries `enacted_by`
- **THEN** middleware observes that value on the pipeline's command

#### Scenario: Middleware-updated metadata reaches the handler
- **WHEN** middleware adds a metadata value through the pipeline metadata API
- **THEN** later middleware and the handler observe the updated value via `command.metadata`

#### Scenario: No divergent metadata state
- **WHEN** command execution is in progress
- **THEN** there is no pipeline metadata state that can differ from the command's metadata

#### Scenario: No metadata dispatch argument
- **WHEN** a caller invokes dispatch
- **THEN** the function accepts only the command and an options keyword list
