## ADDED Requirements

### Requirement: Async adapter behaviour
The library SHALL define an async adapter behaviour for scheduling command execution.

#### Scenario: Bus dispatches asynchronously
- **WHEN** a caller invokes async dispatch for a command
- **THEN** the bus delegates scheduling to the configured async adapter with command, metadata, and pipeline name

#### Scenario: Missing async adapter
- **WHEN** async dispatch is called without a configured async adapter
- **THEN** the bus returns an actionable configuration error

### Requirement: TaskSupervisor async adapter
The library SHALL provide a non-durable async adapter backed by `Task.Supervisor`.

#### Scenario: Task adapter schedules command
- **WHEN** async dispatch uses the TaskSupervisor adapter
- **THEN** the adapter starts a supervised task that executes the command through the selected bus pipeline

#### Scenario: Task adapter returns schedule result
- **WHEN** the TaskSupervisor adapter successfully starts a task
- **THEN** async dispatch returns a scheduling result that identifies the task

### Requirement: Oban async adapter
The library SHALL provide a durable async adapter for applications that use Oban.

#### Scenario: Oban adapter enqueues command
- **WHEN** async dispatch uses the Oban adapter
- **THEN** the adapter inserts an Oban job containing bus module, command module, serialized command params, metadata, and pipeline name

#### Scenario: Oban worker executes command
- **WHEN** the Oban worker performs the job
- **THEN** it reconstructs the command and executes it through the selected bus pipeline

### Requirement: Async pipeline fidelity
Async command execution MUST apply the same pipeline semantics as synchronous dispatch.

#### Scenario: Async command uses selected pipeline
- **WHEN** a command is scheduled asynchronously with `pipeline: :background`
- **THEN** later execution uses the `:background` pipeline

#### Scenario: Async command runs middleware
- **WHEN** an async command executes
- **THEN** configured middleware for the selected pipeline runs before handler execution

#### Scenario: Async command creates runtime context during execution
- **WHEN** an async command is executed by an adapter
- **THEN** the bus creates a fresh runtime context for that execution

### Requirement: Async serialization
Durable async adapters MUST serialize commands using declared command parameters and metadata. Serializable command parameter values MUST be limited to supported scalar/value types and maps/lists composed from those supported types.

#### Scenario: Command has typed params
- **WHEN** an Oban job is created for a typed command
- **THEN** only bus module, command module, declared command params, metadata, and pipeline name are persisted in the job args

#### Scenario: Command params include supported value types
- **WHEN** an Oban job is created for a command containing strings, integers, booleans, decimals, dates, datetimes, and maps/lists composed from supported values
- **THEN** the adapter serializes those values into durable job args and reconstructs them during execution

#### Scenario: Command params include unsupported custom value
- **WHEN** durable async serialization receives a command parameter value outside the supported type set
- **THEN** serialization fails with an actionable unsupported-serialization-type error

#### Scenario: Context is not serialized
- **WHEN** an Oban job is created for a command
- **THEN** runtime context values are not persisted in the job args

#### Scenario: Command reconstruction fails
- **WHEN** an Oban worker cannot reconstruct a command from stored params
- **THEN** the worker fails with an actionable command reconstruction error
