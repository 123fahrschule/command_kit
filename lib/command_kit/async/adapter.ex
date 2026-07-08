defmodule CommandKit.Async.Adapter do
  @moduledoc """
  Behaviour for async command scheduling adapters.

  Metadata travels inside the command; adapters receive no separate
  metadata argument.
  """

  @callback schedule(module(), struct(), atom(), keyword()) :: term()
end
