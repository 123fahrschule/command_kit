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
MyApp.CommandBus.dispatch_async(command, pipeline: :background)
```

## Oban Adapter

Oban dispatch is durable. Job args include bus module, command module,
serialized command params, command identity, command metadata, and pipeline
name. Runtime context is not serialized and is rebuilt at execution time.

```elixir
config :my_app, MyApp.CommandBus,
  async_adapter: {CommandKit.Async.Oban, queue: :commands}
```

```elixir
MyApp.CommandBus.dispatch_async(command, pipeline: :background)
```

## Serialization

The command's identity and metadata survive the queue verbatim: `command_id`,
causation and correlation ids, `enacted_by`, both timestamps, and all
additional metadata pairs are restored exactly as dispatched — construction
defaults do not regenerate on load.

Durable serialization supports these param and metadata values:

- strings
- integers
- booleans
- decimals
- dates
- datetimes
- maps/lists composed from supported values

Unsupported values fail with `CommandKit.SerializationError`.
