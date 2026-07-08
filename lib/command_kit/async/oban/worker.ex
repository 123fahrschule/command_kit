defmodule CommandKit.Async.Oban.Worker do
  @moduledoc """
  Generic Oban worker for durable CommandKit dispatch.
  """

  use Oban.Worker, queue: :command_kit

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    {bus, command, pipeline} = CommandKit.Serialization.load_job(args)

    case bus.dispatch(command, pipeline: pipeline) do
      :ok -> :ok
      {:ok, _value} = ok -> ok
      {:error, _reason} = error -> error
      _other -> :ok
    end
  end
end
