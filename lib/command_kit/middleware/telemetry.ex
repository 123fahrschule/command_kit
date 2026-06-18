defmodule CommandKit.Middleware.Telemetry do
  @moduledoc """
  Emits telemetry events around command dispatch.

  Events:

    * `[:command_kit, :dispatch, :start]`
    * `[:command_kit, :dispatch, :stop]`
    * `[:command_kit, :dispatch, :exception]`
  """

  @behaviour CommandKit.Middleware

  @impl true
  def call(pipeline, next, _opts) do
    metadata = telemetry_metadata(pipeline)
    start_time = System.monotonic_time()

    :telemetry.execute(
      [:command_kit, :dispatch, :start],
      %{system_time: System.system_time()},
      metadata
    )

    try do
      next_pipeline = next.(pipeline)
      duration = System.monotonic_time() - start_time

      :telemetry.execute(
        [:command_kit, :dispatch, :stop],
        %{duration: duration},
        Map.merge(metadata, %{
          halted?: next_pipeline.halted?,
          result_tag: CommandKit.Result.tag(next_pipeline.result)
        })
      )

      next_pipeline
    rescue
      error ->
        duration = System.monotonic_time() - start_time

        :telemetry.execute(
          [:command_kit, :dispatch, :exception],
          %{duration: duration},
          Map.merge(metadata, %{kind: :error, reason: error, stacktrace: __STACKTRACE__})
        )

        reraise error, __STACKTRACE__
    end
  end

  defp telemetry_metadata(pipeline) do
    %{
      bus: pipeline.bus,
      pipeline: pipeline.pipeline,
      command: pipeline.command.__struct__
    }
  end
end
