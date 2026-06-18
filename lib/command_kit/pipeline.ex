defmodule CommandKit.Pipeline do
  @moduledoc """
  State passed through a command bus pipeline.

  Middleware can update command, metadata, context, result, and halted state.
  A halted pipeline skips later middleware and handler execution.
  """

  alias CommandKit.Context

  @enforce_keys [:command, :bus, :pipeline]
  defstruct command: nil,
            metadata: %{},
            context: Context.new(),
            result: nil,
            halted?: false,
            bus: nil,
            pipeline: nil

  @type t :: %__MODULE__{
          command: struct(),
          metadata: map() | keyword(),
          context: Context.t(),
          result: term(),
          halted?: boolean(),
          bus: module(),
          pipeline: atom()
        }

  @doc "Halts the pipeline with a final result."
  @spec halt(t(), term()) :: t()
  def halt(%__MODULE__{} = pipeline, result), do: %{pipeline | result: result, halted?: true}

  @doc "Stores a value in the runtime context."
  @spec put_context(t(), Context.key(), term()) :: t()
  def put_context(%__MODULE__{} = pipeline, key, value) do
    %{pipeline | context: Context.put(pipeline.context, key, value)}
  end

  @doc "Updates a value in the runtime context."
  @spec update_context(t(), Context.key(), term(), (term() -> term())) :: t()
  def update_context(%__MODULE__{} = pipeline, key, initial, fun) do
    %{pipeline | context: Context.update(pipeline.context, key, initial, fun)}
  end
end
