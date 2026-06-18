defmodule CommandKit.MiddlewareTest do
  use ExUnit.Case, async: false

  defmodule CommandBase do
    use CommandKit.Core.Command
  end

  defmodule Ping do
    use CommandBase

    params do
      field :id, :integer
    end

    handler(CommandKit.MiddlewareTest.PingHandler)
  end

  defmodule PingHandler do
    def execute(command, metadata) do
      send(metadata.test_pid, {:ran, command.id})
      {:ok, command.id}
    end
  end

  defimpl CommandKit.Validation, for: Ping do
    def validate(%{id: -1}), do: {:error, :negative}
    def validate(_command), do: :ok
  end

  defmodule RaisingHandler do
    def execute(_command, _metadata), do: raise("boom")
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
      send(pipeline.metadata.test_pid, {:before, opts[:name]})
      pipeline = next.(pipeline)
      send(pipeline.metadata.test_pid, {:after, opts[:name]})
      pipeline
    end
  end

  defmodule RejectAuthorizer do
    def authorize(_command, _metadata, _context), do: {:error, :unauthorized}
  end

  defmodule Reporter do
    def report_exception(error, _stacktrace, info) do
      send(info.metadata.test_pid, {:reported, Exception.message(error), info.pipeline})
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

  test "middleware ordering wraps handler execution" do
    Application.put_env(:command_kit, TestBus,
      pipelines: [
        default: [
          {Recorder, name: :outer},
          {Recorder, name: :inner}
        ]
      ]
    )

    assert {:ok, 1} = TestBus.dispatch(Ping.new!(id: 1), %{test_pid: self()})

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

    assert {:error, :unauthorized} = TestBus.dispatch(Ping.new!(id: 1), %{test_pid: self()})
    refute_received {:ran, _}
  end

  test "error handler reports and normalizes exceptions" do
    Application.put_env(:command_kit, TestBus,
      pipelines: [default: [{CommandKit.Middleware.ErrorHandler, reporter: Reporter}]]
    )

    assert {:error, :command_failed} = TestBus.dispatch(Boom.new!(id: 1), %{test_pid: self()})
    assert_received {:reported, "boom", :default}
  end

  test "idempotency middleware caches successful results" do
    Application.put_env(:command_kit, TestBus,
      pipelines: [default: [CommandKit.Middleware.Idempotency]]
    )

    command = Ping.new!(id: System.unique_integer([:positive]))
    metadata = %{test_pid: self(), idempotency_key: "key-#{System.unique_integer([:positive])}"}

    assert {:ok, first_id} = TestBus.dispatch(command, metadata)
    assert first_id == command.id
    assert_received {:ran, _}

    assert {:ok, second_id} = TestBus.dispatch(command, metadata)
    assert second_id == command.id
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

    assert {:ok, 1} = TestBus.dispatch(Ping.new!(id: 1), %{test_pid: self()})
    assert_received {:telemetry_stop, %{duration: duration}, %{command: Ping, result_tag: :ok}}
    assert is_integer(duration)
  end

  test "validation middleware halts on protocol errors" do
    Application.put_env(:command_kit, TestBus,
      pipelines: [default: [CommandKit.Middleware.Validation]]
    )

    assert {:error, :negative} = TestBus.dispatch(%Ping{id: -1}, %{test_pid: self()})
  end
end
