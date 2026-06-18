defmodule CommandKit.Async.TaskSupervisor do
  @moduledoc """
  Non-durable async adapter backed by `Task.Supervisor`.

  Configure it on a bus:

      config :my_app, MyApp.CommandBus,
        async_adapter: {CommandKit.Async.TaskSupervisor, supervisor: MyApp.CommandTaskSupervisor}
  """

  @behaviour CommandKit.Async.Adapter

  @impl true
  def schedule(bus, command, metadata, pipeline, opts) do
    supervisor =
      Keyword.get(opts, :supervisor) ||
        raise CommandKit.ConfigurationError,
              "CommandKit.Async.TaskSupervisor requires :supervisor option"

    Task.Supervisor.start_child(supervisor, fn ->
      bus.dispatch(command, metadata, pipeline: pipeline)
    end)
  end
end
