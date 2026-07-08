# async-dispatch Delta

## MODIFIED Requirements

### Requirement: Async adapter behaviour
The library SHALL define an async adapter behaviour for scheduling command execution. Metadata travels inside the command; adapters receive no separate metadata argument.

#### Scenario: Bus dispatches asynchronously
- **WHEN** a caller invokes async dispatch for a command
- **THEN** the bus delegates scheduling to the configured async adapter with the command and pipeline name

#### Scenario: Missing async adapter
- **WHEN** async dispatch is called without a configured async adapter
- **THEN** the bus returns an actionable configuration error

### Requirement: Oban async adapter
The library SHALL provide a durable async adapter for applications that use Oban.

#### Scenario: Oban adapter enqueues command
- **WHEN** async dispatch uses the Oban adapter
- **THEN** the adapter inserts an Oban job containing bus module, command module, serialized command params, command identity, command metadata, and pipeline name

#### Scenario: Oban worker executes command
- **WHEN** the Oban worker performs the job
- **THEN** it reconstructs the command including its identity and metadata and executes it through the selected bus pipeline

#### Scenario: Oban worker propagates dispatch errors
- **WHEN** the dispatched command's result is `{:error, reason}`
- **THEN** `perform/1` returns that error so Oban marks the job failed and can retry it

### Requirement: Async serialization
Durable async adapters MUST serialize commands using declared command parameters, the command identity (`command_id`), and the command metadata (five fixed fields plus all additional pairs). Reconstruction MUST restore identity and metadata verbatim — construction defaults MUST NOT regenerate on load. Serializable command parameter and additional-metadata values MUST be limited to supported scalar/value types and maps/lists composed from those supported types.

#### Scenario: Command has typed params
- **WHEN** an Oban job is created for a typed command
- **THEN** only bus module, command module, declared command params, command identity, command metadata, and pipeline name are persisted in the job args

#### Scenario: Command params include supported value types
- **WHEN** an Oban job is created for a command containing strings, integers, booleans, decimals, dates, datetimes, and maps/lists composed from supported values
- **THEN** the adapter serializes those values into durable job args and reconstructs them during execution

#### Scenario: Integer map keys survive the JSON round trip
- **WHEN** a command param contains a map with integer keys such as `%{1 => "x"}`
- **THEN** the reconstructed command carries `%{1 => "x"}`, not `%{"1" => "x"}` — integer keys are not silently stringified by job encoding

#### Scenario: Command params include unsupported custom value
- **WHEN** durable async serialization receives a command parameter value outside the supported type set
- **THEN** serialization fails with an actionable unsupported-serialization-type error

#### Scenario: Metadata round-trips the async hop
- **WHEN** a command with chain-start metadata and additional pairs is scheduled through the Oban adapter and later executed
- **THEN** the reconstructed command carries the identical `command_id`, causation and correlation ids, timestamps, `enacted_by`, and additional pairs

#### Scenario: Additional metadata value is unsupported
- **WHEN** durable async serialization encounters an additional metadata value outside the supported type set
- **THEN** serialization fails with an actionable unsupported-serialization-type error

#### Scenario: Context is not serialized
- **WHEN** an Oban job is created for a command
- **THEN** runtime context values are not persisted in the job args

#### Scenario: Command reconstruction fails
- **WHEN** an Oban worker cannot reconstruct a command from stored params
- **THEN** the worker fails with an actionable command reconstruction error
