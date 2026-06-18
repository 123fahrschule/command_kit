# Pipelines And Middleware

Command buses execute commands through named pipelines.

```elixir
config :my_app, MyApp.CommandBus,
  default_pipeline: :default,
  pipelines: [
    default: [
      CommandKit.Middleware.Telemetry,
      CommandKit.Middleware.Logging,
      {CommandKit.Middleware.ErrorHandler, reporter: MyApp.ErrorReporter},
      CommandKit.Middleware.Authorization,
      CommandKit.Middleware.Idempotency
    ],
    system: [
      CommandKit.Middleware.Telemetry,
      CommandKit.Middleware.ErrorHandler
    ]
  ]
```

Select a pipeline at dispatch time:

```elixir
MyApp.CommandBus.dispatch(command, metadata, pipeline: :system)
```

## Middleware Contract

Middleware receives a pipeline, a continuation, and options:

```elixir
def call(pipeline, next, opts) do
  pipeline = next.(pipeline)
  pipeline
end
```

`opts` is the keyword list configured with that middleware in the bus pipeline.
Use a bare module when the middleware has no options:

```elixir
pipelines: [
  default: [
    MyApp.CommandMiddleware.Audit
  ]
]
```

In that case `opts` is `[]`.

Use `{Module, opts}` when a middleware needs configuration:

```elixir
pipelines: [
  default: [
    {MyApp.CommandMiddleware.Audit, audit_log: MyApp.AuditLog, include_metadata?: true}
  ]
]
```

Then `opts` receives exactly that keyword list:

```elixir
defmodule MyApp.CommandMiddleware.Audit do
  def call(pipeline, next, opts) do
    audit_log = Keyword.fetch!(opts, :audit_log)
    include_metadata? = Keyword.get(opts, :include_metadata?, false)

    next_pipeline = next.(pipeline)

    audit_log.record(%{
      command: pipeline.command.__struct__,
      pipeline: pipeline.pipeline,
      result: next_pipeline.result,
      metadata: if(include_metadata?, do: pipeline.metadata, else: %{})
    })

    next_pipeline
  end
end
```

## Pipeline State

Middleware receives a `%CommandKit.Pipeline{}`. The pipeline is the execution
envelope threaded through one dispatch. The command stays focused on business
input; the pipeline carries execution state around it.

Fields:

- `:command` - the current command struct. Initially this is the command passed
  to `dispatch/3`.
- `:metadata` - caller and audit metadata passed to `dispatch/3`. It may be a
  map or keyword list. Keep business parameters in the command, not metadata.
- `:context` - runtime-only `CommandKit.Context.t()` for dependencies and
  middleware state. Context is not serialized for async dispatch.
- `:result` - the current command result. It is `nil` until a middleware halts
  or the handler returns.
- `:halted?` - `true` when execution has a final result and the remaining
  middleware plus the handler should be skipped.
- `:bus` - the concrete application command bus module that received the
  dispatch call, for example `MyApp.CommandBus`. This is the module defined with
  `use CommandKit.Bus`, not a process or handler.
- `:pipeline` - the selected pipeline name, for example `:default` or `:system`.

Most middleware should treat `:command`, `:bus`, and `:pipeline` as read-only.
Changing `:metadata`, `:context`, `:result`, or `:halted?` is valid when that is
the middleware's explicit responsibility.

For example, when code calls:

```elixir
MyApp.CommandBus.dispatch(command, metadata, pipeline: :system)
```

middleware receives `pipeline.bus == MyApp.CommandBus` and
`pipeline.pipeline == :system`. This is useful for logging, telemetry,
auditing, and middleware that needs to behave differently for different command
buses.

### Pipeline Functions

`CommandKit.Pipeline.halt/2` sets the final result and marks the pipeline as
halted:

```elixir
CommandKit.Pipeline.halt(pipeline, {:error, :unauthorized})
```

Use it when command execution must stop before the handler.

`CommandKit.Pipeline.put_context/3` stores a runtime value in context:

```elixir
CommandKit.Pipeline.put_context(pipeline, {MyApp, :repo}, MyApp.Repo)
```

Use it for dependency injection or values that should be visible to later
middleware and handlers implementing `execute/3`.

`CommandKit.Pipeline.update_context/4` updates a runtime value or initializes it
when it is missing:

```elixir
CommandKit.Pipeline.update_context(
  pipeline,
  {MyApp, :multi},
  Ecto.Multi.new(),
  fn multi -> MyApp.Audit.add_to_multi(multi, pipeline.command) end
)
```

Use it for accumulated execution state such as transaction builders, locks, or
correlation data.

Middleware can continue, transform, or halt.

### Continue

Continue means the middleware calls `next.(pipeline)` and returns the resulting
pipeline. Use this when the middleware only wraps execution, for example for
logging, telemetry, auditing, timing, or cleanup.

```elixir
def call(pipeline, next, _opts) do
  started_at = System.monotonic_time()
  next_pipeline = next.(pipeline)
  duration = System.monotonic_time() - started_at

  MyApp.Metrics.record_duration(pipeline.command.__struct__, duration)

  next_pipeline
end
```

The value returned from `next.(pipeline)` may already be halted by downstream
middleware. Wrapper middleware should usually return `next_pipeline` unchanged
after observing it. Check `next_pipeline.halted?` only when halted executions
need different side effects.

### Transform

Transform means the middleware changes the pipeline before or after calling
`next`. Use this to add execution context, normalize metadata, replace command
data with an equivalent typed command, or enrich the final result.

```elixir
def call(pipeline, next, _opts) do
  pipeline
  |> CommandKit.Pipeline.put_context({MyApp, :repo}, MyApp.Repo)
  |> next.()
end
```

When transforming after `next`, preserve `result` and `halted?` unless changing
them is the purpose of the middleware. Accidental result rewrites make
downstream failures hard to understand.

```elixir
def call(pipeline, next, _opts) do
  next_pipeline = next.(pipeline)
  metadata = put_metadata(next_pipeline.metadata, :audited?, true)

  %{next_pipeline | metadata: metadata}
end

defp put_metadata(metadata, key, value) when is_map(metadata), do: Map.put(metadata, key, value)
defp put_metadata(metadata, key, value) when is_list(metadata), do: Keyword.put(metadata, key, value)
```

### Halt

Halt means the middleware does not call `next`. It returns a pipeline with a
final result and `halted?: true`, which skips the remaining middleware and the
handler. Use this for authorization failures, validation failures, idempotency
cache hits, circuit breakers, or other cases where command execution should not
continue.

```elixir
def call(pipeline, _next, _opts) do
  CommandKit.Pipeline.halt(pipeline, {:error, :unauthorized})
end
```

The bus returns the halt result to the caller. Middleware that already wrapped
the halted middleware still receives the halted pipeline from `next.(pipeline)`,
so telemetry, logging, or auditing middleware can still record the outcome.

The first configured middleware is the outermost wrapper.

## Built-in Middleware

- `CommandKit.Middleware.Telemetry`
- `CommandKit.Middleware.Logging`
- `CommandKit.Middleware.ErrorHandler`
- `CommandKit.Middleware.Authorization`
- `CommandKit.Middleware.Idempotency`
- `CommandKit.Middleware.Validation`

Recommended ordering:

```elixir
[
  CommandKit.Middleware.Telemetry,
  CommandKit.Middleware.Logging,
  CommandKit.Middleware.ErrorHandler,
  CommandKit.Middleware.Authorization,
  CommandKit.Middleware.Idempotency
]
```

If you use validation, place it after authorization and before idempotency
unless you intentionally want an idempotency hit to skip validation:

```elixir
[
  CommandKit.Middleware.Telemetry,
  CommandKit.Middleware.Logging,
  CommandKit.Middleware.ErrorHandler,
  CommandKit.Middleware.Authorization,
  CommandKit.Middleware.Validation,
  CommandKit.Middleware.Idempotency
]
```

## Result Conventions

CommandKit accepts any handler return value, but the recommended shapes are:

- `:ok`
- `{:ok, value}`
- `{:error, reason}`

Built-in logging, telemetry, and idempotency understand these shapes and fall
back to generic tagging for other values.

## Telemetry

`CommandKit.Middleware.Telemetry` emits telemetry events around command
dispatch. It has no options.

```elixir
CommandKit.Middleware.Telemetry
```

Events:

- `[:command_kit, :dispatch, :start]`
- `[:command_kit, :dispatch, :stop]`
- `[:command_kit, :dispatch, :exception]`

Start events include `%{system_time: System.system_time()}` as measurements.
Stop events include `%{duration: native_time}` as measurements and add
`halted?` and `result_tag` to metadata. Exception events include duration and
add `kind`, `reason`, and `stacktrace`.

All telemetry events include these metadata fields:

- `:bus`
- `:pipeline`
- `:command`

With the recommended ordering, `ErrorHandler` catches downstream exceptions, so
telemetry usually emits a `:stop` event with an error result tag. The
`:exception` event is emitted when an exception escapes the middleware stack
below telemetry.

## Logging

`CommandKit.Middleware.Logging` writes a start and stop log entry through
`Logger.info/1`. It has no options.

```elixir
CommandKit.Middleware.Logging
```

The start log includes command module, bus, and pipeline. The stop log includes
command module, pipeline, result tag, and duration in milliseconds.

## Error Handler

`CommandKit.Middleware.ErrorHandler` catches exceptions raised by downstream
middleware or the handler, reports them, and halts the pipeline with a public
error result.

```elixir
{CommandKit.Middleware.ErrorHandler,
 reporter: MyApp.ErrorReporter,
 result: {:error, :command_failed}}
```

Options:

- `:reporter` - optional module used to report exceptions.
- `:result` - public result returned to the caller, defaults to
  `{:error, :command_failed}`.

Without `:reporter`, exceptions are logged with `Logger.error/1`. A reporter
module must export either `report_exception/3` or `report_error/3`.

```elixir
defmodule MyApp.ErrorReporter do
  def report_exception(error, stacktrace, info) do
    MyApp.ErrorTracker.report(error, stacktrace, info)
  end
end
```

The `info` map contains:

- `:command`
- `:bus`
- `:pipeline`
- `:metadata`

## Authorization

`CommandKit.Middleware.Authorization` authorizes the command before the handler
runs. It continues on `:ok` and halts with `{:error, reason}` otherwise.

```elixir
{CommandKit.Middleware.Authorization, authorizer: MyApp.Authorizer}
```

Options:

- `:authorizer` - optional module exporting `authorize/3` or `authorize/2`.

`authorize/3` receives command, metadata, and context:

```elixir
defmodule MyApp.Authorizer do
  def authorize(command, metadata, context) do
    actor = metadata[:actor]

    if MyApp.Permissions.allowed?(actor, command, context) do
      :ok
    else
      {:error, :unauthorized}
    end
  end
end
```

`authorize/2` receives only command and metadata:

```elixir
defmodule MyApp.Authorizer do
  def authorize(command, metadata) do
    if metadata[:role] == :admin do
      :ok
    else
      {:error, :unauthorized}
    end
  end
end
```

Without an `:authorizer`, the middleware calls the `CommandKit.Authorization`
protocol. The default implementation for `Any` allows the command.

```elixir
defimpl CommandKit.Authorization, for: MyApp.Commands.RecordPayout do
  def authorize(command, metadata, context) do
    MyApp.FundingRequests.Policy.authorize(command, metadata, context)
  end
end
```

## Validation

`CommandKit.Middleware.Validation` runs optional command validation before the
handler executes. It has no options.

```elixir
CommandKit.Middleware.Validation
```

The middleware calls the `CommandKit.Validation` protocol. Return `:ok` to
continue or `{:error, reason}` to halt with `{:error, reason}`. The default
implementation for `Any` returns `:ok`.

```elixir
defimpl CommandKit.Validation, for: MyApp.Commands.RecordPayout do
  def validate(command) do
    if Date.compare(command.paid_on, Date.utc_today()) == :gt do
      {:error, :paid_on_in_future}
    else
      :ok
    end
  end
end
```

Command construction already checks required fields and supported parameter
types. Use validation middleware for additional command-level rules that need
application code.

## Idempotency

`CommandKit.Middleware.Idempotency` reads `metadata[:idempotency_key]` by
default. It caches only successful result shapes: `:ok`, `:unchanged`, and
`{:ok, value}`.

```elixir
{CommandKit.Middleware.Idempotency,
 metadata_key: :idempotency_key,
 store: MyApp.IdempotencyStore,
 ttl_ms: :timer.hours(24)}
```

Options:

- `:metadata_key` - metadata key to read, defaults to `:idempotency_key`.
- `:store` - store module, defaults to `CommandKit.IdempotencyStore`.
- `:ttl_ms` - cache lifetime in milliseconds, defaults to 24 hours.

If the metadata key is missing, `nil`, or an empty string, the middleware does
not perform idempotency lookup and simply continues.

The cache key combines a fingerprint of the command data with the idempotency
token, so the same token used with different command data does not collide.

Custom stores must export:

```elixir
@callback fetch(term()) :: {:ok, term()} | :miss
@callback put(term(), term(), non_neg_integer()) :: :ok
```

`CommandKit.IdempotencyStore` is an ETS-backed default store. It creates its
table lazily, but applications may also start it explicitly in their supervision
tree with `CommandKit.IdempotencyStore.start_link/1`.
