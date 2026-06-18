defmodule CommandKit.Async.Oban do
  @moduledoc """
  Durable async adapter backed by Oban.

  Configure it on a bus:

      config :my_app, MyApp.CommandBus,
        async_adapter: {CommandKit.Async.Oban, queue: :commands}

  Job args include bus module, command module, serialized command params,
  metadata, and pipeline name. Runtime context is never serialized.
  """

  @behaviour CommandKit.Async.Adapter

  @impl true
  def schedule(bus, command, metadata, pipeline, opts) do
    worker = Keyword.get(opts, :worker, CommandKit.Async.Oban.Worker)
    oban = Keyword.get(opts, :oban, Oban)

    job_opts =
      Keyword.take(opts, [:queue, :max_attempts, :priority, :tags, :unique, :scheduled_at])

    args = CommandKit.Serialization.dump_job(bus, command, metadata, pipeline)

    args
    |> worker.new(job_opts)
    |> oban.insert()
  end
end
