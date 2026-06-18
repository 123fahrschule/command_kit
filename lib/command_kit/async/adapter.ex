defmodule CommandKit.Async.Adapter do
  @moduledoc """
  Behaviour for async command scheduling adapters.
  """

  @callback schedule(module(), struct(), keyword() | map(), atom(), keyword()) :: term()
end
