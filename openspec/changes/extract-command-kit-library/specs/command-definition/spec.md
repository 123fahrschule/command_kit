## ADDED Requirements

### Requirement: Application-specific command base modules
The library SHALL allow an application to define a local command base module by using either the core command implementation or the Ecto-backed command implementation.

#### Scenario: Application defines an Ecto-backed command base
- **WHEN** an application defines `defmodule Absence.Command` with `use CommandKit.Ecto.Command`
- **THEN** command modules using `use Absence.Command` receive the command DSL and constructor API

#### Scenario: Application defines a core command base
- **WHEN** an application defines `defmodule Absence.Command` with `use CommandKit.Core.Command`
- **THEN** command modules using `use Absence.Command` receive the core command DSL without requiring Ecto-backed casting

### Requirement: Typed params DSL
Command modules SHALL declare their parameters through a `params do` block with `field` entries that include a name and type.

#### Scenario: Command declares date parameters
- **WHEN** a command declares `field :starts_on, :date` inside `params do`
- **THEN** the command exposes `starts_on` as a typed command parameter

#### Scenario: Command declares multiple parameter types
- **WHEN** a command declares integer, string, boolean, decimal, date, and datetime fields
- **THEN** the command definition records each field name and declared type for construction and introspection

#### Scenario: Command declares map and list parameters
- **WHEN** a command declares map or list fields composed from supported scalar and value types
- **THEN** the command definition records those fields for construction, introspection, and async serialization

#### Scenario: Command declares unsupported custom type
- **WHEN** a command declares a custom parameter type that is not part of the supported type set
- **THEN** command definition fails with an actionable unsupported-type error

### Requirement: Parameters are required by default
Every field declared in a command `params do` block MUST be required for command construction unless the field is explicitly marked with `optional: true`.

#### Scenario: Missing declared field
- **WHEN** command construction receives attributes missing a declared field
- **THEN** construction fails with a command construction error that identifies the missing field

#### Scenario: All declared fields are present
- **WHEN** command construction receives valid values for every declared field
- **THEN** construction succeeds and returns a command struct

### Requirement: Explicit optional parameters
Command modules SHALL allow fields to be marked optional by passing `optional: true` to `field`.

#### Scenario: Optional field is absent
- **WHEN** command construction receives attributes missing a field declared with `optional: true`
- **THEN** construction succeeds without requiring that field

#### Scenario: Optional field is present and valid
- **WHEN** command construction receives a value for a field declared with `optional: true`
- **THEN** construction casts and stores that value according to the declared type

#### Scenario: Optional field is present and invalid
- **WHEN** command construction receives an invalid value for a field declared with `optional: true`
- **THEN** construction fails with a command construction error that identifies the invalid field

#### Scenario: Optional field introspection
- **WHEN** application code inspects command parameters
- **THEN** each parameter includes whether it is required or optional

### Requirement: Ecto-backed commands hide Ecto authoring details
The Ecto-backed command implementation SHALL use Ecto internally without requiring command modules to call `use Ecto.Schema`, write `embedded_schema`, or define `changeset` functions.

#### Scenario: Command author writes only command DSL
- **WHEN** a command module uses an application command base backed by Ecto
- **THEN** the command module can define its parameters using `params do` without visible Ecto schema or changeset code

#### Scenario: Invalid Ecto-backed cast
- **WHEN** Ecto-backed command construction receives a value that cannot be cast to the declared type
- **THEN** construction fails with a command-level error rather than exposing a raw changeset as the public API

### Requirement: Structured command construction errors
Command construction failures SHALL be represented as `CommandKit.CommandError` values containing one or more `CommandKit.ParamError` entries.

#### Scenario: Required field is missing
- **WHEN** command construction receives attributes missing a required field
- **THEN** `new/1` returns `{:error, %CommandKit.CommandError{}}` with a `ParamError` whose path identifies the field, code is `:required`, and expected type is the declared field type

#### Scenario: Field has invalid type
- **WHEN** command construction receives a value that cannot be cast to the declared field type
- **THEN** `new/1` returns `{:error, %CommandKit.CommandError{}}` with a `ParamError` whose path identifies the field, code is `:invalid_type`, and expected type is the declared field type

#### Scenario: Raising constructor fails
- **WHEN** `new!/1` receives invalid command attributes
- **THEN** it raises `CommandKit.CommandError` with the same structured error details returned by `new/1`

#### Scenario: Rejected values are omitted
- **WHEN** command construction fails for a field containing a rejected value
- **THEN** the command construction error does not include the rejected value by default

### Requirement: Command constructors
Command modules SHALL expose `new/1` and `new!/1` constructors that build typed command structs from attributes.

#### Scenario: Safe constructor succeeds
- **WHEN** `new/1` receives valid attributes for every declared field
- **THEN** it returns `{:ok, command}`

#### Scenario: Safe constructor fails
- **WHEN** `new/1` receives missing or invalid attributes
- **THEN** it returns `{:error, error}` without raising

### Requirement: Handler declaration DSL
Command modules SHALL be able to declare their handler through the command DSL.

#### Scenario: Command declares handler
- **WHEN** a command module calls `handler MyApp.Services.RecordPayout`
- **THEN** the command definition records that handler for command bus resolution

#### Scenario: Command handler is inspected
- **WHEN** application code inspects the command definition
- **THEN** it can discover the declared handler module

### Requirement: Command parameter introspection
Command modules SHALL expose introspection for declared parameters, their types, and serialization names.

#### Scenario: Command parameters are inspected
- **WHEN** application code calls the command parameter introspection API
- **THEN** it receives the list of declared fields with their names and types

#### Scenario: Async adapter inspects command params
- **WHEN** an async adapter needs to serialize a command
- **THEN** it can use command parameter introspection to serialize only declared command parameters
