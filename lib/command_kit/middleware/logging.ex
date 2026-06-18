defmodule CommandKit.Middleware.Logging do
  @moduledoc """
  Logs command dispatch start and completion with generic command metadata.
  """

  @behaviour CommandKit.Middleware

  require Logger

  @impl true
  def call(pipeline, next, _opts) do
    command = inspect(pipeline.command.__struct__)

    Logger.info(fn ->
      "CommandKit dispatch start command=#{command} bus=#{inspect(pipeline.bus)} pipeline=#{inspect(pipeline.pipeline)}"
    end)

    start_time = System.monotonic_time(:millisecond)
    next_pipeline = next.(pipeline)
    duration = System.monotonic_time(:millisecond) - start_time

    Logger.info(fn ->
      "CommandKit dispatch stop command=#{command} pipeline=#{inspect(pipeline.pipeline)} result=#{inspect(CommandKit.Result.tag(next_pipeline.result))} duration_ms=#{duration}"
    end)

    next_pipeline
  end
end
