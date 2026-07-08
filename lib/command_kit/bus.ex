defmodule CommandKit.Bus do
  @moduledoc """
  Defines an application command bus.

      defmodule MyApp.CommandBus do
        use CommandKit.Bus, otp_app: :my_app
      end

  Configure named pipelines under the bus module:

      config :my_app, MyApp.CommandBus,
        default_pipeline: :default,
        pipelines: [
          default: [
            CommandKit.Middleware.Telemetry,
            CommandKit.Middleware.Logging
          ],
          system: []
        ]
  """

  alias CommandKit.ConfigurationError
  alias CommandKit.MissingHandlerError
  alias CommandKit.MissingHandlerFunctionError
  alias CommandKit.Pipeline

  defmacro __using__(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)

    quote bind_quoted: [otp_app: otp_app] do
      @command_kit_otp_app otp_app

      @doc "Dispatches a command through the configured default or selected pipeline."
      def dispatch(command, opts \\ []) when is_struct(command) and is_list(opts) do
        CommandKit.Bus.dispatch(__MODULE__, @command_kit_otp_app, command, opts)
      end

      @doc "Schedules a command with the configured async adapter."
      def dispatch_async(command, opts \\ []) when is_struct(command) and is_list(opts) do
        CommandKit.Bus.dispatch_async(__MODULE__, @command_kit_otp_app, command, opts)
      end

      @doc false
      def __command_kit_otp_app__, do: @command_kit_otp_app
    end
  end

  @doc false
  def dispatch(bus, otp_app, command, opts) do
    config = config(otp_app, bus)
    pipeline_name = Keyword.get(opts, :pipeline, Keyword.get(config, :default_pipeline, :default))
    stack = pipeline_stack!(config, pipeline_name)

    %Pipeline{command: command, bus: bus, pipeline: pipeline_name}
    |> run(stack)
    |> Map.fetch!(:result)
  end

  @doc false
  def dispatch_async(bus, otp_app, command, opts) do
    config = config(otp_app, bus)
    pipeline_name = Keyword.get(opts, :pipeline, Keyword.get(config, :default_pipeline, :default))
    async_adapter = Keyword.get(config, :async_adapter)

    unless async_adapter do
      raise ConfigurationError,
            "no async adapter configured for #{inspect(bus)}. Set :async_adapter in config."
    end

    {adapter, adapter_opts} = normalize_adapter(async_adapter)
    adapter.schedule(bus, command, pipeline_name, Keyword.merge(adapter_opts, opts))
  end

  defp config(otp_app, bus), do: Application.get_env(otp_app, bus, [])

  defp pipeline_stack!(config, pipeline_name) do
    pipelines = Keyword.get(config, :pipelines, default: [])

    case Keyword.fetch(pipelines, pipeline_name) do
      {:ok, stack} ->
        stack

      :error ->
        raise ConfigurationError,
              "unknown CommandKit pipeline #{inspect(pipeline_name)}. " <>
                "Configured pipelines: #{inspect(Keyword.keys(pipelines))}"
    end
  end

  defp run(%Pipeline{halted?: true} = pipeline, _stack), do: pipeline

  defp run(%Pipeline{} = pipeline, [middleware | rest]) do
    call_middleware(middleware, pipeline, fn next_pipeline -> run(next_pipeline, rest) end)
  end

  defp run(%Pipeline{halted?: false} = pipeline, []) do
    handler = resolve_handler!(pipeline.command)
    result = execute_handler!(handler, pipeline)
    %{pipeline | result: result}
  end

  defp call_middleware(middleware, pipeline, next) do
    {module, opts} = normalize_middleware(middleware)
    Code.ensure_loaded?(module)

    cond do
      function_exported?(module, :call, 3) -> module.call(pipeline, next, opts)
      function_exported?(module, :call, 2) -> module.call(pipeline, next)
      true -> raise ConfigurationError, "#{inspect(module)} must export call/2 or call/3"
    end
  end

  defp normalize_middleware({module, opts}) when is_atom(module) and is_list(opts),
    do: {module, opts}

  defp normalize_middleware(module) when is_atom(module), do: {module, []}

  defp normalize_middleware(other) do
    raise ConfigurationError, "invalid middleware entry #{inspect(other)}"
  end

  defp normalize_adapter({module, opts}) when is_atom(module) and is_list(opts),
    do: {module, opts}

  defp normalize_adapter(module) when is_atom(module), do: {module, []}

  defp normalize_adapter(other) do
    raise ConfigurationError, "invalid async adapter #{inspect(other)}"
  end

  defp resolve_handler!(command) do
    handler =
      if function_exported?(command.__struct__, :__command_kit_handler__, 0) do
        command.__struct__.__command_kit_handler__()
      end

    handler = handler || CommandKit.Handler.handler(command)

    if handler do
      handler
    else
      raise MissingHandlerError, command: command
    end
  end

  defp execute_handler!(handler, %Pipeline{} = pipeline) do
    Code.ensure_loaded?(handler)

    cond do
      function_exported?(handler, :execute, 1) ->
        handler.execute(pipeline.command)

      function_exported?(handler, :execute, 2) ->
        handler.execute(pipeline.command, pipeline.context)

      true ->
        raise MissingHandlerFunctionError, handler: handler
    end
  end
end
