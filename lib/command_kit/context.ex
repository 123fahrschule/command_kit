defmodule CommandKit.Context do
  @moduledoc """
  Runtime-only execution context for a command dispatch.

  Context is intended for execution services and middleware state, not command
  data. Prefer namespaced tuple keys such as `{MyApp, :repo}` to avoid
  collisions between application code, middleware, and adapters.
  """

  @enforce_keys [:values]
  defstruct values: %{}

  @type key :: atom() | tuple()
  @type t :: %__MODULE__{values: map()}

  @doc "Creates an empty runtime context."
  @spec new() :: t()
  def new, do: %__MODULE__{values: %{}}

  @doc "Stores a runtime context value."
  @spec put(t(), key(), term()) :: t()
  def put(%__MODULE__{} = context, key, value) do
    %{context | values: Map.put(context.values, key, value)}
  end

  @doc "Reads a runtime context value, returning `default` when missing."
  @spec get(t(), key(), term()) :: term()
  def get(%__MODULE__{} = context, key, default \\ nil), do: Map.get(context.values, key, default)

  @doc "Fetches a runtime context value."
  @spec fetch(t(), key()) :: {:ok, term()} | :error
  def fetch(%__MODULE__{} = context, key), do: Map.fetch(context.values, key)

  @doc "Fetches a runtime context value or raises."
  @spec fetch!(t(), key()) :: term()
  def fetch!(%__MODULE__{} = context, key) do
    case fetch(context, key) do
      {:ok, value} -> value
      :error -> raise CommandKit.MissingContextValueError, key: key
    end
  end

  @doc "Updates a runtime context value."
  @spec update(t(), key(), term(), (term() -> term())) :: t()
  def update(%__MODULE__{} = context, key, initial, fun) when is_function(fun, 1) do
    %{context | values: Map.update(context.values, key, initial, fun)}
  end
end
