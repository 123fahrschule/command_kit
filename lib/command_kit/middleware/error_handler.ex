defmodule CommandKit.Middleware.ErrorHandler do
  @moduledoc """
  Catches exceptions, reports them, and halts with a public error result.

  Options:

    * `:reporter` - module implementing `report_exception/3` or
      `report_error/3`
    * `:result` - public result returned to the caller, defaults to
      `{:error, :command_failed}`
  """

  @behaviour CommandKit.Middleware

  require Logger

  @impl true
  def call(pipeline, next, opts) do
    try do
      next.(pipeline)
    rescue
      error ->
        stacktrace = __STACKTRACE__
        report(error, stacktrace, pipeline, opts)
        CommandKit.Pipeline.halt(pipeline, Keyword.get(opts, :result, {:error, :command_failed}))
    end
  end

  defp report(error, stacktrace, pipeline, opts) do
    info = %{
      command: pipeline.command.__struct__,
      bus: pipeline.bus,
      pipeline: pipeline.pipeline,
      metadata: CommandKit.Pipeline.metadata(pipeline)
    }

    case Keyword.get(opts, :reporter) do
      nil ->
        Logger.error(Exception.format(:error, error, stacktrace))

      reporter when is_atom(reporter) ->
        Code.ensure_loaded?(reporter)

        cond do
          function_exported?(reporter, :report_exception, 3) ->
            reporter.report_exception(error, stacktrace, info)

          function_exported?(reporter, :report_error, 3) ->
            reporter.report_error(error, stacktrace, info)

          true ->
            Logger.error("#{inspect(reporter)} must export report_exception/3 or report_error/3")
        end
    end
  end
end
