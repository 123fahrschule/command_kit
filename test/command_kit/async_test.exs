defmodule CommandKit.AsyncTest do
  use ExUnit.Case, async: false

  alias CommandKit.Metadata

  defmodule CommandBase do
    use CommandKit.Core.Command, source: "de.123fahrschule:testapp"
  end

  defmodule Ping do
    use CommandBase

    params do
      field :id, :integer
      field :paid_on, :date
      field :paid_at, :datetime
      field :amount, :decimal
      field :payload, :map
      field :items, :list
    end

    handler(CommandKit.AsyncTest.PingHandler)
  end

  defmodule PingHandler do
    def execute(command) do
      pid =
        Metadata.get(command.metadata, :test_pid) ||
          Process.whereis(:command_kit_async_test_pid)

      send(pid, {:async_ran, command.id})
      {:ok, command.id}
    end
  end

  defmodule FailingCommand do
    use CommandBase

    params do
      field :id, :integer
    end

    handler(CommandKit.AsyncTest.FailingHandler)
  end

  defmodule FailingHandler do
    def execute(_command), do: {:error, :payout_rejected}
  end

  defmodule TestBus do
    use CommandKit.Bus, otp_app: :command_kit
  end

  defmodule FakeWorker do
    def new(args, opts), do: {:job, args, opts}
  end

  defmodule FakeOban do
    def insert({:job, args, opts}) do
      send(self(), {:oban_insert, args, opts})
      {:ok, :job}
    end
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

  test "TaskSupervisor adapter schedules dispatch through the selected pipeline" do
    {:ok, supervisor} = start_supervised({Task.Supervisor, name: __MODULE__.TaskSupervisor})

    Application.put_env(:command_kit, TestBus,
      pipelines: [default: [], background: []],
      async_adapter: {CommandKit.Async.TaskSupervisor, supervisor: supervisor}
    )

    command = command(1) |> CommandKit.Command.put_metadata(:test_pid, self())

    assert {:ok, pid} = TestBus.dispatch_async(command, pipeline: :background)

    assert is_pid(pid)
    assert_receive {:async_ran, 1}
  end

  test "dispatch_async raises when adapter is missing" do
    Application.put_env(:command_kit, TestBus, pipelines: [default: []])

    assert_raise CommandKit.ConfigurationError, ~r/no async adapter/, fn ->
      TestBus.dispatch_async(command(1))
    end
  end

  # The built-in JSON module needs Elixir 1.18+; the library itself supports 1.17.
  if Version.match?(System.version(), ">= 1.18.0") do
    test "serialization preserves integer map keys" do
      command =
        Ping.new!(
          id: 5,
          paid_on: ~D[2026-06-17],
          paid_at: ~U[2026-06-17 10:15:00Z],
          amount: Decimal.new("1"),
          payload: %{1 => "one", "two" => %{2 => "nested"}},
          items: []
        )

      args = CommandKit.Serialization.dump_job(TestBus, command, :default)

      # survive a JSON encode/decode cycle like a real Oban job does
      args = args |> JSON.encode!() |> JSON.decode!()

      assert {TestBus, loaded, :default} = CommandKit.Serialization.load_job(args)
      assert loaded.payload == %{1 => "one", "two" => %{2 => "nested"}}
    end
  end

  test "serialization round-trips params, identity, and metadata without context" do
    command =
      command(2)
      |> CommandKit.Command.enacted_by("user-123")
      |> CommandKit.Command.put_metadata(:idempotency_key, "abc")

    args = CommandKit.Serialization.dump_job(TestBus, command, :background)

    refute Map.has_key?(args, "context")

    assert {TestBus, loaded, :background} = CommandKit.Serialization.load_job(args)
    assert loaded.id == 2
    assert loaded.paid_on == ~D[2026-06-17]
    assert loaded.paid_at == ~U[2026-06-17 10:15:00Z]
    assert loaded.amount == Decimal.new("12.34")
    assert loaded.payload == %{"source" => "test", "nested" => [%{"ok" => true}]}

    # identity and metadata are restored verbatim, not regenerated
    assert loaded.command_id == command.command_id
    assert loaded.metadata.causation_id == command.metadata.causation_id
    assert loaded.metadata.correlation_id == command.metadata.correlation_id
    assert loaded.metadata.enacted_by == "user-123"
    assert loaded.metadata.occurred_at == command.metadata.occurred_at
    assert loaded.metadata.received_at == command.metadata.received_at
    assert Metadata.get(loaded.metadata, :idempotency_key) == "abc"
  end

  test "serialization rejects unsupported additional metadata values" do
    command = command(1) |> CommandKit.Command.put_metadata(:bad, self())

    assert_raise CommandKit.SerializationError, ~r/unsupported serialization value/, fn ->
      CommandKit.Serialization.dump_job(TestBus, command, :default)
    end
  end

  test "Oban adapter builds insertable jobs" do
    Application.put_env(:command_kit, TestBus,
      pipelines: [default: []],
      async_adapter: {CommandKit.Async.Oban, worker: FakeWorker, oban: FakeOban, queue: :commands}
    )

    assert {:ok, :job} = TestBus.dispatch_async(command(3))

    assert_receive {:oban_insert,
                    %{
                      "bus_module" => _,
                      "command_module" => _,
                      "params" => _,
                      "command_id" => _,
                      "metadata" => _
                    }, opts}

    assert opts[:queue] == :commands
  end

  test "generic Oban worker reconstructs and dispatches" do
    Application.put_env(:command_kit, TestBus, pipelines: [default: []])

    Process.register(self(), :command_kit_async_test_pid)

    on_exit(fn ->
      if Process.whereis(:command_kit_async_test_pid) == self() do
        Process.unregister(:command_kit_async_test_pid)
      end
    end)

    args = CommandKit.Serialization.dump_job(TestBus, command(4), :default)

    assert {:ok, 4} = CommandKit.Async.Oban.Worker.perform(%Oban.Job{args: args})
    assert_receive {:async_ran, 4}
  end

  test "Oban worker propagates dispatch errors so Oban can retry" do
    Application.put_env(:command_kit, TestBus, pipelines: [default: []])

    args = CommandKit.Serialization.dump_job(TestBus, FailingCommand.new!(id: 9), :default)

    assert {:error, :payout_rejected} =
             CommandKit.Async.Oban.Worker.perform(%Oban.Job{args: args})
  end

  defp command(id) do
    Ping.new!(
      id: id,
      paid_on: ~D[2026-06-17],
      paid_at: ~U[2026-06-17 10:15:00Z],
      amount: Decimal.new("12.34"),
      payload: %{"source" => "test", "nested" => [%{"ok" => true}]},
      items: ["a", 1, true]
    )
  end
end
