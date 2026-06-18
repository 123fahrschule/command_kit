defmodule CommandKit.AsyncTest do
  use ExUnit.Case, async: false

  defmodule CommandBase do
    use CommandKit.Core.Command
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
    def execute(command, metadata) do
      pid = Map.get(metadata, :test_pid) || Process.whereis(:command_kit_async_test_pid)
      send(pid, {:async_ran, command.id})
      {:ok, command.id}
    end
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

    command = command(1)

    assert {:ok, pid} =
             TestBus.dispatch_async(command, %{test_pid: self()}, pipeline: :background)

    assert is_pid(pid)
    assert_receive {:async_ran, 1}
  end

  test "dispatch_async raises when adapter is missing" do
    Application.put_env(:command_kit, TestBus, pipelines: [default: []])

    assert_raise CommandKit.ConfigurationError, ~r/no async adapter/, fn ->
      TestBus.dispatch_async(command(1), %{test_pid: self()})
    end
  end

  test "serialization round-trips command params and metadata without context" do
    args =
      CommandKit.Serialization.dump_job(
        TestBus,
        command(2),
        [idempotency_key: "abc"],
        :background
      )

    refute Map.has_key?(args, "context")

    assert {TestBus, loaded, metadata, :background} = CommandKit.Serialization.load_job(args)
    assert loaded.id == 2
    assert loaded.paid_on == ~D[2026-06-17]
    assert loaded.paid_at == ~U[2026-06-17 10:15:00Z]
    assert loaded.amount == Decimal.new("12.34")
    assert loaded.payload == %{"source" => "test", "nested" => [%{"ok" => true}]}
    assert metadata.idempotency_key == "abc"
  end

  test "serialization rejects unsupported metadata values" do
    assert_raise CommandKit.SerializationError, ~r/unsupported serialization value/, fn ->
      CommandKit.Serialization.dump_job(TestBus, command(1), %{bad: self()}, :default)
    end
  end

  test "Oban adapter builds insertable jobs" do
    Application.put_env(:command_kit, TestBus,
      pipelines: [default: []],
      async_adapter: {CommandKit.Async.Oban, worker: FakeWorker, oban: FakeOban, queue: :commands}
    )

    assert {:ok, :job} = TestBus.dispatch_async(command(3), %{})

    assert_receive {:oban_insert, %{"bus_module" => _, "command_module" => _, "params" => _},
                    opts}

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

    args = CommandKit.Serialization.dump_job(TestBus, command(4), %{}, :default)

    assert :ok = CommandKit.Async.Oban.Worker.perform(%Oban.Job{args: args})
    assert_receive {:async_ran, 4}
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
