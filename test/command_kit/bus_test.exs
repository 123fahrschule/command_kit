defmodule CommandKit.BusTest do
  use ExUnit.Case, async: false

  defmodule CommandBase do
    use CommandKit.Core.Command
  end

  defmodule Ping do
    use CommandBase

    params do
      field :id, :integer
    end

    handler(CommandKit.BusTest.PingHandler)
  end

  defmodule PingHandler do
    def execute(command, metadata, context) do
      send(
        metadata.test_pid,
        {:handler3, command.id, CommandKit.Context.fetch!(context, {__MODULE__, :value})}
      )

      {:ok, :handler3}
    end
  end

  defmodule Execute2Command do
    use CommandBase

    params do
      field :id, :integer
    end

    handler(CommandKit.BusTest.Execute2Handler)
  end

  defmodule Execute2Handler do
    def execute(command, metadata) do
      send(metadata.test_pid, {:handler2, command.id})
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
    def execute(command, metadata) do
      send(metadata.test_pid, {:alpha, command.route})
      {:ok, :alpha}
    end
  end

  defmodule BetaHandler do
    def execute(command, metadata) do
      send(metadata.test_pid, {:beta, command.route})
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

  test "dispatch uses default pipeline and execute/3 when available" do
    Application.put_env(:command_kit, TestBus,
      default_pipeline: :default,
      pipelines: [default: [ContextMiddleware]]
    )

    command = Ping.new!(id: 1)
    assert {:ok, :handler3} = TestBus.dispatch(command, %{test_pid: self()})
    assert_received {:handler3, 1, :from_context}
  end

  test "dispatch selects named pipeline and can halt" do
    Application.put_env(:command_kit, TestBus,
      default_pipeline: :default,
      pipelines: [default: [ContextMiddleware], system: [HaltMiddleware]]
    )

    assert {:error, :halted} =
             TestBus.dispatch(Ping.new!(id: 1), %{test_pid: self()}, pipeline: :system)

    refute_received {:handler3, _, _}
  end

  test "dispatch falls back to execute/2" do
    Application.put_env(:command_kit, TestBus, pipelines: [default: []])

    assert {:ok, :handler2} = TestBus.dispatch(Execute2Command.new!(id: 2), %{test_pid: self()})
    assert_received {:handler2, 2}
  end

  test "dispatch can resolve handlers through protocol pattern matching" do
    Application.put_env(:command_kit, TestBus, pipelines: [default: []])

    assert {:ok, :alpha} =
             TestBus.dispatch(RoutedCommand.new!(route: "alpha"), %{test_pid: self()})

    assert_received {:alpha, "alpha"}

    assert {:ok, :beta} =
             TestBus.dispatch(RoutedCommand.new!(route: "beta"), %{test_pid: self()})

    assert_received {:beta, "beta"}
  end

  test "unknown pipeline raises configuration error" do
    Application.put_env(:command_kit, TestBus, pipelines: [default: []])

    assert_raise CommandKit.ConfigurationError, ~r/unknown CommandKit pipeline/, fn ->
      TestBus.dispatch(Ping.new!(id: 1), %{}, pipeline: :missing)
    end
  end

  test "handler without supported execute function raises" do
    Application.put_env(:command_kit, TestBus, pipelines: [default: []])

    assert_raise CommandKit.MissingHandlerFunctionError, fn ->
      TestBus.dispatch(NoFunctionCommand.new!(id: 1), %{})
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
