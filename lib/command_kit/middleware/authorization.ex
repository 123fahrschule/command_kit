defmodule CommandKit.Middleware.Authorization do
  @moduledoc """
  Authorizes commands through an application authorizer or protocol.

  Configure `authorizer: MyApp.Authorizer` to call a module. The module may
  export `authorize/2` (command, context) or `authorize/1` (command).
  Without an authorizer, the `CommandKit.Authorization` protocol is used.
  Authorizers read the actor from `command.metadata.enacted_by`.
  """

  @behaviour CommandKit.Middleware

  @impl true
  def call(pipeline, next, opts) do
    case authorize(pipeline, opts) do
      :ok -> next.(pipeline)
      {:error, _reason} = error -> CommandKit.Pipeline.halt(pipeline, error)
    end
  end

  defp authorize(pipeline, opts) do
    case Keyword.get(opts, :authorizer) do
      nil ->
        CommandKit.Authorization.authorize(pipeline.command, pipeline.context)

      authorizer ->
        Code.ensure_loaded?(authorizer)

        cond do
          function_exported?(authorizer, :authorize, 2) ->
            authorizer.authorize(pipeline.command, pipeline.context)

          function_exported?(authorizer, :authorize, 1) ->
            authorizer.authorize(pipeline.command)

          true ->
            raise CommandKit.ConfigurationError,
                  "#{inspect(authorizer)} must export authorize/1 or authorize/2"
        end
    end
  end
end
