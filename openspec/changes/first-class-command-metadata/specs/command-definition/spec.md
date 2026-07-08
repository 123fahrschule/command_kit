# command-definition Delta

## MODIFIED Requirements

### Requirement: Application-specific command base modules
The library SHALL allow an application to define a local command base module by using either the core command implementation or the Ecto-backed command implementation. The base module `use` MUST require a `source:` option that supplies the URN prefix for command identity and correlation helpers. The source is application-wide: individual command modules MUST NOT be able to override it.

#### Scenario: Application defines an Ecto-backed command base
- **WHEN** an application defines `defmodule Absence.Command` with `use CommandKit.Ecto.Command, source: "de.123fahrschule:absence"`
- **THEN** command modules using `use Absence.Command` receive the command DSL and constructor API

#### Scenario: Application defines a core command base
- **WHEN** an application defines `defmodule Absence.Command` with `use CommandKit.Core.Command, source: "de.123fahrschule:absence"`
- **THEN** command modules using `use Absence.Command` receive the core command DSL without requiring Ecto-backed casting

#### Scenario: Base module without source
- **WHEN** an application uses a command base implementation without a `source:` option
- **THEN** compilation fails with an `ArgumentError` that shows an example `source:` value

#### Scenario: Per-command source override is rejected
- **WHEN** a command module writes `use MyApp.Command, source: "other"`
- **THEN** compilation fails with an `ArgumentError` explaining that `source:` is configured once on the base module

## ADDED Requirements

### Requirement: Command identity
Every command struct SHALL carry a `command_id` (a UUID string generated inside `new/1`, because commands are not persisted) and expose a `command_name/0` function derived from the module's last segment in kebab-case. `command_name/0` MUST be overridable via `defoverridable`. Names containing underscores MUST be rejected at construction time with an `ArgumentError` suggesting the kebab-case form, including overridden names.

#### Scenario: Command id is generated at construction
- **WHEN** `RecordPayout.new!(params)` is called twice
- **THEN** each command struct carries a distinct UUID `command_id`

#### Scenario: Command name is derived from the module
- **WHEN** a command module is named `MyApp.Commands.RecordPayout`
- **THEN** `command_name/0` returns `"record-payout"`

#### Scenario: Command name is overridden
- **WHEN** a command module redefines `command_name/0` to return `"record-manual-payout"`
- **THEN** construction and correlation use the overridden name

#### Scenario: Overridden name with underscores is rejected
- **WHEN** a command module overrides `command_name/0` to return `"record_payout"`
- **THEN** construction raises an `ArgumentError` suggesting `"record-payout"`

### Requirement: Reserved parameter names
The params DSL MUST reject field declarations named `:metadata` or `:command_id` at compile time, because these names are struct fields owned by the library.

#### Scenario: Command declares a metadata param
- **WHEN** a command declares `field :metadata, :map` inside `params do`
- **THEN** compilation fails with an error naming the reserved field
