defmodule CommandKit.MissingHandlerFunctionError do
  @moduledoc "Raised when a handler exports neither execute/1 nor execute/2."
  defexception [:handler]

  @impl true
  def message(%__MODULE__{handler: handler}) do
    "#{inspect(handler)} must export execute/1 or execute/2 (command, context)"
  end
end
