defmodule CommandKit.SerializationError do
  @moduledoc "Raised when command serialization or reconstruction fails."
  defexception [:message]
end
