# Async Dispatch

CommandKit supports async dispatch through adapters. Async execution still
dispatches through the selected bus pipeline; it does not call handlers
directly.

## TaskSupervisor Adapter

TaskSupervisor dispatch is non-durable.

```elixir
children = [
  {Task.Supervisor, name: MyApp.CommandTaskSupervisor}
]

config :my_app, MyApp.CommandBus,
  async_adapter:
    {CommandKit.Async.TaskSupervisor, supervisor: MyApp.CommandTaskSupervisor}
```

```elixir
MyApp.CommandBus.dispatch_async(command, metadata, pipeline: :background)
```

## Oban Adapter

Oban dispatch is durable. Job args include bus module, command module,
serialized command params, metadata, and pipeline name. Runtime context is not
serialized and is rebuilt at execution time.

```elixir
config :my_app, MyApp.CommandBus,
  async_adapter: {CommandKit.Async.Oban, queue: :commands}
```

```elixir
MyApp.CommandBus.dispatch_async(command, metadata, pipeline: :background)
```

## Serialization

Durable serialization supports:

- strings
- integers
- booleans
- decimals
- dates
- datetimes
- maps/lists composed from supported values

Unsupported values fail with `CommandKit.SerializationError`.
