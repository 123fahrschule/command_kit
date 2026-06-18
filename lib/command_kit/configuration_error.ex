defmodule CommandKit.ConfigurationError do
  @moduledoc "Raised when command bus or adapter configuration is invalid."
  defexception [:message]
end
