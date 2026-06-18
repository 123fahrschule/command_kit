# Testing

CommandKit is designed so each layer can be tested directly.

## Commands

Test constructors and structured errors:

```elixir
assert {:ok, command} = MyCommand.new(%{"id" => "42"})
assert {:error, %CommandKit.CommandError{errors: errors}} = MyCommand.new(%{})
```

## Middleware

Middleware can be tested with a small pipeline and continuation:

```elixir
pipeline = %CommandKit.Pipeline{command: command, bus: MyBus, pipeline: :default}

result =
  MyMiddleware.call(pipeline, fn pipeline ->
    %{pipeline | result: :ok}
  end, [])
```

## Buses

Use the test application environment to configure a bus:

```elixir
Application.put_env(:my_app, MyApp.CommandBus,
  pipelines: [default: [MyMiddleware]]
)
```

Restore previous config in `on_exit/1`.

## Async

For TaskSupervisor, start a test supervisor with `start_supervised/1`.

For Oban, test command serialization and worker reconstruction separately from
database-backed Oban execution when possible. Runtime context is not serialized,
so async tests should inject execution services through the pipeline that runs
at perform time.
