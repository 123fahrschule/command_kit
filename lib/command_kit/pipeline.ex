defmodule CommandKit.Pipeline do
  @moduledoc """
  State passed through a command bus pipeline.

  Middleware can update command, context, result, and halted state. The
  command's metadata is the single source of truth: read it with
  `metadata/1` and change it with `put_metadata/3`, which updates the
  command itself — so handlers always observe middleware changes. A halted
  pipeline skips later middleware and handler execution.
  """

  alias CommandKit.Context

  @enforce_keys [:command, :bus, :pipeline]
  defstruct command: nil,
            context: Context.new(),
            result: nil,
            halted?: false,
            bus: nil,
            pipeline: nil

  @type t :: %__MODULE__{
          command: struct(),
          context: Context.t(),
          result: term(),
          halted?: boolean(),
          bus: module(),
          pipeline: atom()
        }

  @doc "Returns the metadata of the command in the pipeline."
  @spec metadata(t()) :: CommandKit.Metadata.t() | nil
  def metadata(%__MODULE__{command: command}), do: Map.get(command, :metadata)

  @doc "Writes a metadata value onto the command in the pipeline."
  @spec put_metadata(t(), atom(), term()) :: t()
  def put_metadata(%__MODULE__{} = pipeline, key, value) do
    %{pipeline | command: CommandKit.Command.put_metadata(pipeline.command, key, value)}
  end

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
