defmodule CommandKit.Async.Oban.Worker do
  @moduledoc """
  Generic Oban worker for durable CommandKit dispatch.
  """

  use Oban.Worker, queue: :command_kit

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    {bus, command, metadata, pipeline} = CommandKit.Serialization.load_job(args)
    bus.dispatch(command, metadata, pipeline: pipeline)
    :ok
  end
end
