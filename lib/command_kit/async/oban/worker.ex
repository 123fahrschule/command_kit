defmodule CommandKit.Async.Oban.Worker do
  @moduledoc """
  Generic Oban worker for durable CommandKit dispatch.

  `{:error, reason}` dispatch results are returned to Oban so the job is
  marked failed and retried. The recognized success shapes (`:ok`,
  `:unchanged`, `{:ok, value}`) complete the job; any other handler result
  is logged and treated as success rather than triggering retries.
  """

  use Oban.Worker, queue: :command_kit

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    {bus, command, pipeline} = CommandKit.Serialization.load_job(args)

    case bus.dispatch(command, pipeline: pipeline) do
      :ok ->
        :ok

      :unchanged ->
        :ok

      {:ok, _value} = ok ->
        ok

      {:error, _reason} = error ->
        error

      other ->
        Logger.warning(
          "CommandKit Oban worker treating non-standard dispatch result as success: #{inspect(other)}"
        )

        :ok
    end
  end
end
