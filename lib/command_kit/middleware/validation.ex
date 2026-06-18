defmodule CommandKit.Middleware.Validation do
  @moduledoc """
  Runs optional command validation before handler execution.
  """

  @behaviour CommandKit.Middleware

  @impl true
  def call(pipeline, next, _opts) do
    case CommandKit.Validation.validate(pipeline.command) do
      :ok -> next.(pipeline)
      {:error, reason} -> CommandKit.Pipeline.halt(pipeline, {:error, reason})
    end
  end
end
