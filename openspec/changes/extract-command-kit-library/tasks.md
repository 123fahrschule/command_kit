## 1. Project Setup

- [ ] 1.1 Create the Mix library project files for `command_kit` without disturbing existing OpenSpec files
- [ ] 1.2 Add core dependencies for telemetry and optional dependencies for Ecto and Oban integration
- [ ] 1.3 Configure formatter, test paths, aliases, and documentation generation
- [ ] 1.4 Add baseline CI-friendly checks for compile, format, and tests

## 2. Core Command Definition

- [ ] 2.1 Implement `CommandKit.Core.Command` with application-specific base module support
- [ ] 2.2 Implement the `params do` and `field` DSL for typed parameter declarations
- [ ] 2.3 Generate required-by-default struct fields and parameter introspection metadata, including optional field metadata
- [ ] 2.4 Implement `new/1` and `new!/1` constructors for core commands
- [ ] 2.5 Add `CommandKit.CommandError` and `CommandKit.ParamError` with path, code, expected type, and message fields
- [ ] 2.6 Implement `optional: true` handling for absent, nil, valid, and invalid optional fields
- [ ] 2.7 Implement the command `handler` DSL and handler introspection metadata
- [ ] 2.8 Enforce the supported adapter-safe type set and reject unsupported custom parameter types
- [ ] 2.9 Test core command base modules, typed params, required fields, optional fields, structured errors, handler DSL, supported type enforcement, constructors, and introspection

## 3. Ecto-backed Command Definition

- [ ] 3.1 Implement `CommandKit.Ecto.Command` using Ecto internally while preserving the same public command DSL
- [ ] 3.2 Support casting for the first built-in field types including string, integer, boolean, decimal, date, datetime, and maps/lists of supported values
- [ ] 3.3 Wrap Ecto casting and validation failures in command-level errors without exposing raw changesets as the public API
- [ ] 3.4 Ensure command modules do not need visible `Ecto.Schema`, `embedded_schema`, or `changeset` code
- [ ] 3.5 Implement Ecto-backed `optional: true` behavior without exposing raw changesets
- [ ] 3.6 Test successful and failing Ecto-backed command construction across supported field types and optional fields

## 4. Command Bus And Pipelines

- [ ] 4.1 Implement `CommandKit.Bus` for application command bus modules with `otp_app` configuration
- [ ] 4.2 Implement `CommandKit.Context` with public APIs for runtime-only execution state and namespaced tuple key support
- [ ] 4.3 Implement `CommandKit.Pipeline` with command, metadata, context, result, halted state, bus module, and pipeline name
- [ ] 4.4 Implement multiple named pipeline configuration with default pipeline selection
- [ ] 4.5 Implement synchronous `dispatch` functions with explicit pipeline selection
- [ ] 4.6 Implement handler resolution for `execute/3` with fallback to `execute/2`
- [ ] 4.7 Implement missing-handler and missing-handler-function errors
- [ ] 4.8 Test default pipeline dispatch, named pipeline dispatch, unknown pipeline errors, metadata propagation, context propagation, namespaced context keys, execute arity selection, handler execution, and result return

## 5. Middleware System

- [ ] 5.1 Implement the middleware behaviour and continuation-based pipeline execution
- [ ] 5.2 Implement pipeline halt helpers and verify halted pipelines skip later middleware and handlers
- [ ] 5.3 Implement middleware access to `CommandKit.Context` through public APIs
- [ ] 5.4 Implement telemetry middleware with start, stop, and exception events
- [ ] 5.5 Implement logging middleware with generic command, pipeline, result tag, and duration logging
- [ ] 5.6 Implement error handling middleware with configurable reporter and public error result
- [ ] 5.7 Implement authorization middleware with application-provided authorization logic
- [ ] 5.8 Implement idempotency middleware and an ETS-backed idempotency store with TTL
- [ ] 5.9 Implement validation middleware for supported command validation state
- [ ] 5.10 Test middleware ordering, transformation, halting, context updates, telemetry payloads, error handling, authorization, idempotency hits and misses, and validation behavior

## 6. Async Dispatch

- [ ] 6.1 Define the async adapter behaviour and bus-level async dispatch API
- [ ] 6.2 Implement missing-adapter configuration errors
- [ ] 6.3 Implement the TaskSupervisor async adapter and supervised task execution through the selected pipeline
- [ ] 6.4 Implement command serialization and reconstruction helpers for the supported adapter-safe type set while excluding runtime context
- [ ] 6.5 Implement fresh context creation during async execution
- [ ] 6.6 Implement the Oban async adapter and worker using command module, serialized params, metadata, and pipeline name
- [ ] 6.7 Test TaskSupervisor scheduling, Oban enqueueing, Oban worker reconstruction, supported value serialization, unsupported value failures, context exclusion from serialization, selected pipeline fidelity, and reconstruction failures

## 7. Documentation

- [ ] 7.1 Write the README quickstart covering installation, command definition, bus setup, pipeline configuration, handler registration, and dispatch
- [ ] 7.2 Write the command authoring guide for core and Ecto-backed commands, including structured construction errors, adapter-safe parameter types, and handler DSL usage
- [ ] 7.3 Write the context guide with namespaced key conventions and use cases such as execution-time dependency injection, resolved actors, tenant context, feature flags, locks, transaction handles, Ecto repositories, optional Ecto.Multi accumulation, telemetry correlation state, and authorization state
- [ ] 7.4 Write the pipeline and middleware guide with built-in middleware ordering, context usage, result conventions, and custom middleware examples
- [ ] 7.5 Write the async guide for TaskSupervisor and Oban adapters, including runtime context exclusion from serialization
- [ ] 7.6 Add moduledocs and examples for all public modules
- [ ] 7.7 Add testing documentation for commands, middleware, context, pipelines, and async adapters

## 8. Final Verification

- [ ] 8.1 Run formatting and fix any formatting issues
- [ ] 8.2 Run the full test suite
- [ ] 8.3 Generate documentation locally and fix broken links or missing moduledocs
- [ ] 8.4 Confirm every requirement in the specs is covered by implementation, tests, or documentation
