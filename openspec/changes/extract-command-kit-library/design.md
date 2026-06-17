## Context

`command_kit` is currently an empty library repository with OpenSpec scaffolding and a license. The intended consumers are internal Phoenix applications that already rely on common Elixir infrastructure but need a reusable command layer instead of each application re-creating command structs, command buses, middleware stacks, telemetry, and async execution.

The library must support applications that want a small core command implementation and applications that want Ecto-backed parameter casting. Even when Ecto is used internally, command modules must read as command definitions, not as Ecto schemas or changesets.

## Goals / Non-Goals

**Goals:**

- Provide a reusable command definition DSL with explicit parameter types and required-by-default fields.
- Let applications define their own base command modules, for example `use CommandKit.Core.Command` or `use CommandKit.Ecto.Command`.
- Provide a command bus with multiple named pipelines.
- Provide a runtime command context that middleware can enrich and handlers can opt into via `execute/3`.
- Provide a middleware contract and built-in middleware for telemetry, logging, error handling, authorization, idempotency, and validation.
- Provide async dispatch through pluggable adapters, starting with `Task.Supervisor` and Oban.
- Make documentation part of the implementation scope.

**Non-Goals:**

- Do not migrate any consuming application in this change.
- Do not couple the library to a specific event store, audit model, web framework, or domain authorization model.
- Do not expose `Ecto.Schema` or `def changeset` as part of the command authoring API.
- Do not replace Oban; only provide an adapter for applications that already use it.

## Decisions

### Split Core, Ecto, And Async Adapters

`CommandKit.Core` will contain bus, pipeline, middleware, handler resolution, metadata, and a dependency-light command DSL. `CommandKit.Ecto.Command` will provide the same command authoring shape while using Ecto internally for typed parameter casting. `CommandKit.Async.TaskSupervisor` and `CommandKit.Async.Oban` will live behind adapter behaviours.

Alternative considered: make Ecto mandatory in the core. That is acceptable for current internal consumers, but separating the modules keeps the core easier to reason about and allows tests to prove which behavior is generic and which behavior depends on Ecto.

### Use Application-Specific Base Modules

Applications will define a local command base module:

```elixir
defmodule Absence.Command do
  use CommandKit.Ecto.Command
end
```

Individual commands then use the application module:

```elixir
defmodule Absence.Commands.RequestAbsence do
  use Absence.Command

  params do
    field :employee_id, :integer
    field :starts_on, :date
    field :ends_on, :date
    field :reason, :string, optional: true
  end
end
```

Alternative considered: have every command use `CommandKit.Ecto.Command` directly. The base module is better because applications can centralize defaults, error formatting, serialization settings, and future command-class choices.

### Keep Command Construction Explicit

Command modules will expose constructors such as `new/1` and `new!/1`. The command bus will accept command structs and will not silently cast arbitrary request parameters.

This keeps the boundary clear:

```text
raw params -> command constructor -> command struct -> bus pipeline -> handler
```

Alternative considered: let `dispatch/2` accept raw params and a command module. That would blur adapter, form, and execution responsibilities.

### Make Params Required By Default And Optional Explicitly

Every field declared inside `params do` is required by default. A command can mark a field as optional with `optional: true` when the field does not change the command intent, for example a note, external reference, or optional reason.

```elixir
params do
  field :funding_request_id, :integer
  field :paid_on, :date
  field :paid_amount, :decimal
  field :paid_reference, :string, optional: true
end
```

Required fields must be present and castable. Optional fields may be absent or nil; when present, they still must be castable to their declared type.

Alternative considered: make all params mandatory and require a new command for every missing field. That is clean for business-critical parameters, but too strict for common optional data such as comments, references, and external IDs.

### Return Structured Command Construction Errors

Command constructors will return command-level error structs instead of raw maps or Ecto changesets.

`new/1` will return:

```elixir
{:error,
 %CommandKit.CommandError{
   command: MyApp.Commands.RecordPayout,
   errors: [
     %CommandKit.ParamError{
       path: [:paid_on],
       code: :required,
       expected: :date,
       message: nil
     },
     %CommandKit.ParamError{
       path: [:paid_amount],
       code: :invalid_type,
       expected: :decimal,
       message: nil
     }
   ]
 }}
```

`new!/1` will raise a `CommandKit.CommandError` with the same structured data. `CommandKit.ParamError` will include `path`, `code`, `expected`, and `message`. Rejected values will not be stored by default because commands may contain personal data, secrets, or regulated values.

Alternative considered: return raw `%Ecto.Changeset{}` values. That is convenient for Ecto-backed commands but leaks implementation details and makes core commands inconsistent. Alternative considered: return a plain field-to-errors map. That is simple but too weak for nested paths, expected types, UI mapping, API serialization, and tests.

### Use Adapter-safe Parameter Types

Command parameters will use adapter-safe scalar and value types only. The first supported type set is strings, integers, booleans, decimals, dates, datetimes, and maps/lists composed from those supported scalar/value types.

Custom parameter types are not part of the first version. Application services and command handlers must remain callable from all adapters in layered applications, so command input should stay transportable through controllers, LiveViews, jobs, CLIs, tests, and durable async serialization.

### Use Named Pipelines

The bus will support multiple named pipelines, for example `:default`, `:public`, `:system`, and `:background`. `dispatch/3` and async dispatch functions can select a pipeline explicitly, otherwise the configured default pipeline is used.

Alternative considered: one global pipeline. That is simpler, but it does not cover applications that need different authorization, idempotency, or error-handling behavior per command source.

### Middleware Owns Cross-Cutting Behavior

Middleware will use a continuation-based contract similar to Plug:

```elixir
call(pipeline, next) :: pipeline
```

Middlewares can inspect and update command, metadata, context, result, and halted state. Built-in middleware will remain configurable so applications can replace logging, error reporting, authorization, and idempotency storage without forking the bus.

### Add Runtime Context For Opt-In Handler State

The bus will create a `CommandKit.Context` for each execution. Middleware can add runtime-only state to the context, and handlers can opt into that state by implementing `execute/3` instead of only `execute/2`.

Handler resolution will prefer `execute(command, metadata, context)` when the handler exports it. If the handler only exports `execute(command, metadata)`, the bus will call `execute/2`.

```elixir
def execute(command, metadata) do
  # normal handler path
end

def execute(command, metadata, context) do
  # opt-in path for handlers that need runtime context
end
```

The context is not command data. It must not be serialized by async adapters and must not be persisted as part of the command. It is rebuilt at execution time by the selected pipeline.

Expected context use cases include execution-time dependency injection, resolved actors, tenant or account context, feature flag snapshots, locks, transaction handles, Ecto repositories, optional Ecto.Multi accumulation, telemetry correlation state, and middleware-derived authorization state. Dependency injection through context is especially useful in Elixir because command handlers are usually modules with functions rather than constructed object instances. Applications can inject runtime services such as repositories, mailers, HTTP clients, clocks, UUID generators, storage adapters, provider clients, and test doubles without putting those services into command data or global process state.

Context values will be stored and read through public APIs such as `put/3`, `get/3`, `fetch/2`, `fetch!/2`, and `update/4`. The recommended key style is namespaced tuple keys such as `{MyApp, :repo}`, `{MyApp, :clock}`, or `{MyApp.Billing, :payment_client}`. Plain atom keys remain possible for local or single-owner values, but public documentation will recommend namespaced keys to avoid collisions between middleware, adapters, and application code.

The bus will not inject default dependencies into context automatically. Applications can add dependency-injection middleware when they need repositories, clocks, clients, or test doubles in handlers.

Alternative considered: expose `pipeline.private` publicly. An explicit `CommandKit.Context` is clearer because it names the runtime concept directly and avoids putting non-domain state into command structs.

### Support Handler Declaration In The Command DSL

Command modules can declare their handler in the command DSL:

```elixir
defmodule MyApp.Commands.RecordPayout do
  use MyApp.Command

  params do
    field :funding_request_id, :integer
    field :paid_on, :date
    field :paid_amount, :decimal
  end

  handler MyApp.FundingRequests.RecordPayout
end
```

The implementation may still expose lower-level handler registration for applications that prefer protocols or behaviours, but the command DSL is the recommended API because it keeps the command-to-handler relationship discoverable next to the command definition.

### Keep Result Conventions Recommended But Flexible

`CommandKit` will remain tolerant of arbitrary handler return values, but documentation and built-in middleware will treat `:ok`, `{:ok, value}`, and `{:error, reason}` as the recommended result convention. Logging, telemetry, and idempotency will provide sensible result tagging for those shapes and fall back to generic tagging for other return values.

### Async Dispatch Replays The Selected Pipeline

Async adapters will serialize enough information to execute the same command through the selected pipeline later. The durable Oban adapter will store command module, command params, metadata, and pipeline name. Runtime context is never serialized. The Task adapter can keep the command struct in memory because it is non-durable, but it still creates a fresh execution context when the command runs.

Alternative considered: async adapters call handlers directly. That would skip middleware behavior and make async commands observably different from sync commands.

### Documentation Is A Release Gate

The first implementation is not complete until README content, moduledocs, and focused guides cover command authoring, pipeline configuration, middleware, telemetry, async adapters, and testing.

## Risks / Trade-offs

- Ecto-backed commands could leak Ecto concepts through errors or documentation -> Wrap constructor results and document command terminology consistently.
- Oban serialization can fail for unsupported field types -> Require command param introspection and provide adapter tests for all supported built-in types.
- Multiple pipelines can create configuration mistakes -> Validate pipeline configuration at compile time or startup and provide clear error messages.
- Middleware ordering affects behavior -> Document recommended ordering and cover ordering with tests.
- Optional parameters can weaken command intent if overused -> Keep fields required by default and document optional parameters for non-essential data only.
- Runtime context can become an unstructured service locator -> Provide a small public API, recommend namespaced keys, document intended use cases including dependency injection, and keep command data in commands, caller data in metadata, and execution services in context.

## Migration Plan

This change introduces a new library surface and does not migrate a consuming application. Implementation can proceed by building the library, tests, and documentation in place. Future application migrations will be specified separately when the target application is chosen.

Rollback is limited to removing the unfinished library dependency from any experimental consumer branch. No production data or consuming application behavior changes in this change.

## Open Questions

- Should rejected command construction values ever be included behind an opt-in debug configuration, or should they always be omitted for safety?
