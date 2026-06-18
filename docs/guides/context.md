# Context

`CommandKit.Context` is runtime-only state for one command execution. It is
created by the bus, passed through middleware, and optionally received by
handlers that implement `execute/3`.

Context is not command data and is not serialized by async adapters.

## API

```elixir
context = CommandKit.Context.new()
context = CommandKit.Context.put(context, {MyApp, :repo}, MyApp.Repo)
repo = CommandKit.Context.fetch!(context, {MyApp, :repo})
clock = CommandKit.Context.get(context, {MyApp, :clock}, MyApp.Clock)
```

Use namespaced tuple keys for values that may cross module boundaries:

```elixir
{MyApp, :repo}
{MyApp, :clock}
{MyApp.Billing, :payment_client}
```

Plain atom keys are acceptable for local, single-owner middleware state, but
namespaced keys avoid collisions.

## Execution-time Dependency Injection

Elixir handlers are modules with functions rather than constructed object
instances. Context provides execution-time dependency injection without putting
services into commands or relying on global process state.

Good dependency injection use cases:

- repositories
- mailers
- HTTP clients
- clocks
- UUID generators
- storage adapters
- payment or provider clients
- test doubles

Example middleware:

```elixir
defmodule MyApp.CommandMiddleware.InjectDependencies do
  def call(pipeline, next, _opts) do
    pipeline
    |> CommandKit.Pipeline.put_context({MyApp, :repo}, MyApp.Repo)
    |> CommandKit.Pipeline.put_context({MyApp, :clock}, MyApp.Clock)
    |> next.()
  end
end
```

Example handler:

```elixir
def execute(command, metadata, context) do
  repo = CommandKit.Context.fetch!(context, {MyApp, :repo})
  clock = CommandKit.Context.fetch!(context, {MyApp, :clock})

  repo.transaction(fn ->
    {:ok, clock.utc_now()}
  end)
end
```

## Other Context Use Cases

- resolved actors
- tenant or account context
- feature flag snapshots
- locks
- transaction handles
- Ecto repositories
- optional `Ecto.Multi` accumulation
- telemetry correlation state
- authorization state

Keep command data in commands, caller/audit data in metadata, and execution
services in context.
