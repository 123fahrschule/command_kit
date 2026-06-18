defmodule CommandKit.Middleware do
  @moduledoc """
  Behaviour for CommandKit middleware.

  Middleware receives the current pipeline, a continuation, and optional
  middleware-specific options. It can continue, transform, or halt the
  pipeline.
  """

  alias CommandKit.Pipeline

  @callback call(Pipeline.t(), (Pipeline.t() -> Pipeline.t()), keyword()) :: Pipeline.t()
end
