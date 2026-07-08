defmodule CommandKit.BusTest do
  use ExUnit.Case, async: false

  defmodule CommandBase do
    use CommandKit.Core.Command, source: "de.123fahrschule:testapp"
  end

  defmodule Ping do
    use CommandBase

    params do
      field :id, :integer
    end

    handler(CommandKit.BusTest.PingHandler)
  end

  defmodule PingHandler do
    def execute(command, context) do
      send(
        command.metadata[:test_pid],
        {:handler2, command.id, CommandKit.Context.fetch!(context, {__MODULE__, :value})}
      )

      {:ok, :handler2}
    end
  end

  defmodule Execute1Command do
    use CommandBase

    params do
      field :id, :integer
    end

    handler(CommandKit.BusTest.Execute1Handler)
  end

  defmodule Execute1Handler do
    def execute(command) do
      send(command.metadata[:test_pid], {:handler1, command.id})
      {:ok, :handler1}
    end

    # execute/1 must win over execute/2 when both are exported
    def execute(command, _context) do
      send(command.metadata[:test_pid], {:handler2, command.id})
      {:ok, :handler2}
    end
  end

  defmodule RoutedCommand do
    use CommandBase

    params do
      field :route, :string
    end
  end

  defmodule AlphaHandler do
    def execute(command) do
      send(command.metadata[:test_pid], {:alpha, command.route})
      {:ok, :alpha}
    end
  end

  defmodule BetaHandler do
    def execute(command) do
      send(command.metadata[:test_pid], {:beta, command.route})
      {:ok, :beta}
    end
  end

  defimpl CommandKit.Handler, for: CommandKit.BusTest.RoutedCommand do
    def handler(%{route: "alpha"}), do: CommandKit.BusTest.AlphaHandler
    def handler(%{route: "beta"}), do: CommandKit.BusTest.BetaHandler
  end

  defmodule NoFunctionCommand do
    use CommandBase

    params do
      field :id, :integer
    end

    handler(CommandKit.BusTest.NoFunctionHandler)
  end

  defmodule NoFunctionHandler do
  end

  defmodule ContextMiddleware do
    def call(pipeline, next, _opts) do
      pipeline
      |> CommandKit.Pipeline.put_context({PingHandler, :value}, :from_context)
      |> next.()
    end
  end

  defmodule MetadataMiddleware do
    def call(pipeline, next, _opts) do
      pipeline
      |> CommandKit.Pipeline.put_metadata(:enriched, :by_middleware)
      |> next.()
    end
  end

  defmodule MetadataReadingHandler do
    def execute(command) do
      send(command.metadata[:test_pid], {:metadata_seen, command.metadata[:enriched]})
      :ok
    end
  end

  defmodule MetadataCommand do
    use CommandBase

    params do
      field :id, :integer
    end

    handler(CommandKit.BusTest.MetadataReadingHandler)
  end

  defmodule HaltMiddleware do
    def call(pipeline, _next, _opts), do: CommandKit.Pipeline.halt(pipeline, {:error, :halted})
  end

  defmodule TestBus do
    use CommandKit.Bus, otp_app: :command_kit
  end

  setup do
    previous = Application.get_env(:command_kit, TestBus)

    on_exit(fn ->
      if previous do
        Application.put_env(:command_kit, TestBus, previous)
      else
        Application.delete_env(:command_kit, TestBus)
      end
    end)

    :ok
  end

  defp with_test_pid(command),
    do: CommandKit.Command.put_metadata(command, :test_pid, self())

  test "dispatch uses default pipeline and execute/2 receives the context" do
    Application.put_env(:command_kit, TestBus,
      default_pipeline: :default,
      pipelines: [default: [ContextMiddleware]]
    )

    command = Ping.new!(id: 1) |> with_test_pid()
    assert {:ok, :handler2} = TestBus.dispatch(command)
    assert_received {:handler2, 1, :from_context}
  end

  test "dispatch prefers execute/1 over execute/2" do
    Application.put_env(:command_kit, TestBus, pipelines: [default: []])

    command = Execute1Command.new!(id: 2) |> with_test_pid()
    assert {:ok, :handler1} = TestBus.dispatch(command)
    assert_received {:handler1, 2}
    refute_received {:handler2, _}
  end

  test "dispatch selects named pipeline and can halt" do
    Application.put_env(:command_kit, TestBus,
      default_pipeline: :default,
      pipelines: [default: [ContextMiddleware], system: [HaltMiddleware]]
    )

    command = Ping.new!(id: 1) |> with_test_pid()
    assert {:error, :halted} = TestBus.dispatch(command, pipeline: :system)
    refute_received {:handler2, _, _}
  end

  test "middleware metadata changes are visible to the handler" do
    Application.put_env(:command_kit, TestBus, pipelines: [default: [MetadataMiddleware]])

    command = MetadataCommand.new!(id: 1) |> with_test_pid()
    assert :ok = TestBus.dispatch(command)
    assert_received {:metadata_seen, :by_middleware}
  end

  test "dispatch can resolve handlers through protocol pattern matching" do
    Application.put_env(:command_kit, TestBus, pipelines: [default: []])

    assert {:ok, :alpha} =
             TestBus.dispatch(RoutedCommand.new!(route: "alpha") |> with_test_pid())

    assert_received {:alpha, "alpha"}

    assert {:ok, :beta} =
             TestBus.dispatch(RoutedCommand.new!(route: "beta") |> with_test_pid())

    assert_received {:beta, "beta"}
  end

  test "unknown pipeline raises configuration error" do
    Application.put_env(:command_kit, TestBus, pipelines: [default: []])

    assert_raise CommandKit.ConfigurationError, ~r/unknown CommandKit pipeline/, fn ->
      TestBus.dispatch(Ping.new!(id: 1), pipeline: :missing)
    end
  end

  test "handler without supported execute function raises" do
    Application.put_env(:command_kit, TestBus, pipelines: [default: []])

    assert_raise CommandKit.MissingHandlerFunctionError, ~r/execute\/1 or execute\/2/, fn ->
      TestBus.dispatch(NoFunctionCommand.new!(id: 1))
    end
  end

  test "context supports namespaced keys and defaults" do
    context =
      CommandKit.Context.new()
      |> CommandKit.Context.put({__MODULE__, :repo}, :repo)

    assert CommandKit.Context.fetch!(context, {__MODULE__, :repo}) == :repo
    assert CommandKit.Context.get(context, {__MODULE__, :missing}, :default) == :default

    assert_raise CommandKit.MissingContextValueError, fn ->
      CommandKit.Context.fetch!(context, {__MODULE__, :missing})
    end
  end
end
