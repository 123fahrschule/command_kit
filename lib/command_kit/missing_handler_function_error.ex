defmodule CommandKit.MissingHandlerFunctionError do
  @moduledoc "Raised when a handler exports none of execute/1, execute/2, or execute/3."
  defexception [:handler]

  @impl true
  def message(%__MODULE__{handler: handler}) do
    "#{inspect(handler)} must export execute/1, execute/2, or execute/3"
  end
end
