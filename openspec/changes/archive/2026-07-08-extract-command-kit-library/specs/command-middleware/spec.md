## ADDED Requirements

### Requirement: Middleware behaviour
The library SHALL define a middleware behaviour that receives a pipeline struct and a continuation function.

#### Scenario: Middleware continues pipeline
- **WHEN** middleware calls the continuation with the pipeline
- **THEN** execution continues to the next middleware or handler

#### Scenario: Middleware transforms pipeline
- **WHEN** middleware returns an updated pipeline
- **THEN** the bus uses that updated pipeline for subsequent execution

### Requirement: Middleware context access
Middleware SHALL be able to read and update the runtime command context through public context APIs.

#### Scenario: Middleware stores resolved actor
- **WHEN** middleware resolves an actor from metadata
- **THEN** it can store that actor in the runtime context for later middleware and `execute/3` handlers

#### Scenario: Middleware stores transaction state
- **WHEN** middleware opens a transaction or prepares transaction-related state
- **THEN** it can store runtime-only transaction state in the context without modifying the command

### Requirement: Pipeline halting
Middleware MUST be able to halt the pipeline with a result.

#### Scenario: Authorization middleware rejects command
- **WHEN** middleware halts the pipeline with `{:error, :unauthorized}`
- **THEN** later middleware and the handler are not executed

### Requirement: Telemetry middleware
The library SHALL provide telemetry middleware that emits dispatch start, stop, and exception events.

#### Scenario: Successful command dispatch emits telemetry
- **WHEN** a command dispatch completes successfully
- **THEN** telemetry events include command module, bus module, pipeline name, result tag, and duration

#### Scenario: Failed command dispatch emits telemetry
- **WHEN** command dispatch raises or is converted to an error by middleware
- **THEN** telemetry includes command module, bus module, pipeline name, and failure information

### Requirement: Logging middleware
The library SHALL provide logging middleware that logs command start and completion using generic command and pipeline metadata.

#### Scenario: Command completes
- **WHEN** logging middleware wraps a successful command dispatch
- **THEN** it logs the command module, pipeline name, result tag, and duration

### Requirement: Error handling middleware
The library SHALL provide error handling middleware with a configurable reporter and configurable public error result.

#### Scenario: Handler raises
- **WHEN** a handler raises during dispatch
- **THEN** error handling middleware reports the exception and halts with the configured error result

#### Scenario: Reporter is configured
- **WHEN** an application configures a reporter module for error handling
- **THEN** the middleware calls that reporter with the exception, stacktrace, command, metadata, and pipeline information

### Requirement: Authorization middleware
The library SHALL provide authorization middleware that delegates authorization decisions to application-provided command authorization logic.

#### Scenario: Authorization succeeds
- **WHEN** authorization returns `:ok`
- **THEN** the pipeline continues

#### Scenario: Authorization fails
- **WHEN** authorization returns `{:error, reason}`
- **THEN** the pipeline halts with `{:error, reason}`

### Requirement: Idempotency middleware
The library SHALL provide idempotency middleware that reuses successful results for repeated commands with the same idempotency key.

#### Scenario: First dispatch stores result
- **WHEN** a command with an idempotency key completes with a cacheable success result
- **THEN** the idempotency middleware stores that result using the command fingerprint and idempotency key

#### Scenario: Repeated dispatch returns cached result
- **WHEN** the same command fingerprint and idempotency key are dispatched again
- **THEN** the idempotency middleware returns the cached result without executing the handler

#### Scenario: Error result is not cached
- **WHEN** a command with an idempotency key returns an error
- **THEN** the idempotency middleware does not cache that result

### Requirement: Validation middleware
The library SHALL provide validation middleware that can verify command construction or command validation state before handler execution.

#### Scenario: Invalid command reaches validation middleware
- **WHEN** validation middleware receives a command marked invalid by a supported command implementation
- **THEN** the middleware halts with a command validation error

#### Scenario: Valid command reaches validation middleware
- **WHEN** validation middleware receives a valid command struct
- **THEN** the pipeline continues
