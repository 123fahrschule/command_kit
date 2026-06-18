defmodule CommandKit.MissingHandlerError do
  @moduledoc "Raised when a command has no registered handler."
  defexception [:command]

  @impl true
  def message(%__MODULE__{command: command}) do
    "no CommandKit handler registered for #{inspect(command.__struct__)}"
  end
end
