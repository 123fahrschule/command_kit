## Why

Several internal Phoenix applications need the same command execution shape: typed commands, handler dispatch, middleware pipelines, telemetry, and optional asynchronous execution. Extracting this into `command_kit` avoids rebuilding that infrastructure per application while keeping each application free to define its own command base module and execution adapters.

## What Changes

- Create `command_kit` as a reusable Elixir library for command definition and dispatch.
- Add a command DSL that supports `params do` fields with explicit types, required-by-default parameters, explicit `optional: true` fields, and generated constructors without exposing Ecto concepts in command modules.
- Support both a core command implementation and an Ecto-backed command implementation so applications can choose the command class they want.
- Add a command bus with multiple named pipelines, middleware composition, handler resolution, metadata propagation, and runtime execution context.
- Provide common middleware for telemetry, logging, error handling, authorization, idempotency, and command parameter validation.
- Add asynchronous dispatch adapters for non-durable `Task.Supervisor` execution and durable Oban-backed execution.
- Treat documentation as a first-class deliverable, including installation, command authoring, pipeline configuration, middleware authoring, async dispatch, and adapter guidance.

## Capabilities

### New Capabilities

- `command-definition`: Define typed commands through application-specific base modules, core commands, and Ecto-backed commands.
- `command-dispatch`: Dispatch commands through named pipelines, resolve handlers, propagate metadata and runtime context, and execute middleware.
- `command-middleware`: Provide middleware contracts and built-in middleware for cross-cutting command behavior.
- `async-dispatch`: Dispatch commands asynchronously through pluggable task and Oban adapters.
- `library-documentation`: Document the library API, extension points, configuration, and recommended application integration patterns.

### Modified Capabilities

- None.

## Impact

- Adds a new Elixir library surface under `command_kit`.
- Introduces optional Ecto and Oban integration modules while keeping the core dispatch abstractions independent of those choices.
- Defines public APIs for command modules, buses, handlers, middleware, metadata, async adapters, and documentation.
- Does not migrate any consuming application as part of this change.
