defmodule CommandKit.MissingContextValueError do
  @moduledoc "Raised when a required runtime context value is missing."
  defexception [:key]

  @impl true
  def message(%__MODULE__{key: key}) do
    "missing CommandKit context value for key #{inspect(key)}"
  end
end
