defmodule CommandKit.MiddlewareTest do
  use ExUnit.Case, async: false

  defmodule CommandBase do
    use CommandKit.Core.Command, source: "de.123fahrschule:testapp"
  end

  defmodule Ping do
    use CommandBase

    params do
      field :id, :integer
    end

    handler(CommandKit.MiddlewareTest.PingHandler)
  end

  defmodule PingHandler do
    def execute(command) do
      send(command.metadata[:test_pid], {:ran, command.id})
      {:ok, command.id}
    end
  end

  defimpl CommandKit.Validation, for: Ping do
    def validate(%{id: -1}), do: {:error, :negative}
    def validate(_command), do: :ok
  end

  defmodule MapPing do
    use CommandBase

    params do
      field :id, :integer
      field :payload, :map
    end

    handler(CommandKit.MiddlewareTest.PingHandler)
  end

  defmodule RaisingHandler do
    def execute(_command), do: raise("boom")
  end

  defmodule Boom do
    use CommandBase

    params do
      field :id, :integer
    end

    handler(CommandKit.MiddlewareTest.RaisingHandler)
  end

  defmodule Recorder do
    def call(pipeline, next, opts) do
      test_pid = CommandKit.Pipeline.metadata(pipeline)[:test_pid]
      send(test_pid, {:before, opts[:name]})
      pipeline = next.(pipeline)
      send(test_pid, {:after, opts[:name]})
      pipeline
    end
  end

  defmodule RejectAuthorizer do
    def authorize(_command, _context), do: {:error, :unauthorized}
  end

  defmodule Reporter do
    def report_exception(error, _stacktrace, info) do
      send(info.metadata[:test_pid], {:reported, Exception.message(error), info.pipeline})
      :ok
    end
  end

  defmodule TestBus do
    use CommandKit.Bus, otp_app: :command_kit
  end

  def handle_telemetry_event(_event, measurements, metadata, test_pid) do
    send(test_pid, {:telemetry_stop, measurements, metadata})
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

  test "middleware ordering wraps handler execution" do
    Application.put_env(:command_kit, TestBus,
      pipelines: [
        default: [
          {Recorder, name: :outer},
          {Recorder, name: :inner}
        ]
      ]
    )

    assert {:ok, 1} = TestBus.dispatch(Ping.new!(id: 1) |> with_test_pid())

    assert_received {:before, :outer}
    assert_received {:before, :inner}
    assert_received {:ran, 1}
    assert_received {:after, :inner}
    assert_received {:after, :outer}
  end

  test "authorization middleware can halt" do
    Application.put_env(:command_kit, TestBus,
      pipelines: [default: [{CommandKit.Middleware.Authorization, authorizer: RejectAuthorizer}]]
    )

    assert {:error, :unauthorized} = TestBus.dispatch(Ping.new!(id: 1) |> with_test_pid())
    refute_received {:ran, _}
  end

  test "error handler reports and normalizes exceptions" do
    Application.put_env(:command_kit, TestBus,
      pipelines: [default: [{CommandKit.Middleware.ErrorHandler, reporter: Reporter}]]
    )

    assert {:error, :command_failed} = TestBus.dispatch(Boom.new!(id: 1) |> with_test_pid())
    assert_received {:reported, "boom", :default}
  end

  test "idempotency middleware caches results across freshly built commands" do
    Application.put_env(:command_kit, TestBus,
      pipelines: [default: [CommandKit.Middleware.Idempotency]]
    )

    id = System.unique_integer([:positive])
    key = "key-#{System.unique_integer([:positive])}"

    build = fn ->
      Ping.new!(id: id)
      |> with_test_pid()
      |> CommandKit.Command.put_metadata(:idempotency_key, key)
    end

    first = build.()
    second = build.()

    # different identity and timestamps, same params and key
    refute first.command_id == second.command_id

    assert {:ok, ^id} = TestBus.dispatch(first)
    assert_received {:ran, _}

    assert {:ok, ^id} = TestBus.dispatch(second)
    refute_received {:ran, _}
  end

  test "fingerprint is insensitive to map construction history" do
    Application.put_env(:command_kit, TestBus,
      pipelines: [default: [CommandKit.Middleware.Idempotency]]
    )

    id = System.unique_integer([:positive])
    key = "key-#{System.unique_integer([:positive])}"

    # three equal payloads with different construction histories: built
    # directly, shrunk from a larger map, and inserted in shuffled order
    direct = Map.new(1..60, fn i -> {"k#{i}", i} end)

    shrunk =
      Map.new(1..100, fn i -> {"k#{i}", i} end)
      |> then(fn map -> Enum.reduce(61..100, map, &Map.delete(&2, "k#{&1}")) end)

    shuffled = Enum.reduce(Enum.shuffle(1..60), %{}, fn i, acc -> Map.put(acc, "k#{i}", i) end)

    build = fn payload ->
      MapPing.new!(id: id, payload: payload)
      |> with_test_pid()
      |> CommandKit.Command.put_metadata(:idempotency_key, key)
    end

    assert {:ok, ^id} = TestBus.dispatch(build.(direct))
    assert_received {:ran, _}

    assert {:ok, ^id} = TestBus.dispatch(build.(shrunk))
    assert {:ok, ^id} = TestBus.dispatch(build.(shuffled))
    refute_received {:ran, _}
  end

  test "telemetry middleware emits stop events" do
    test_pid = self()
    handler_id = "command-kit-test-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler_id,
      [:command_kit, :dispatch, :stop],
      &__MODULE__.handle_telemetry_event/4,
      test_pid
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    Application.put_env(:command_kit, TestBus,
      pipelines: [default: [CommandKit.Middleware.Telemetry]]
    )

    assert {:ok, 1} = TestBus.dispatch(Ping.new!(id: 1) |> with_test_pid())
    assert_received {:telemetry_stop, %{duration: duration}, %{command: Ping, result_tag: :ok}}
    assert is_integer(duration)
  end

  test "validation middleware halts on protocol errors" do
    Application.put_env(:command_kit, TestBus,
      pipelines: [default: [CommandKit.Middleware.Validation]]
    )

    assert {:error, :negative} = TestBus.dispatch(%Ping{id: -1})
  end
end
