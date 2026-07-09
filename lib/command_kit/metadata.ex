defmodule CommandKit.Metadata do
  @moduledoc """
  Correlation metadata carried by every command.

  Metadata is a fixed concept owned by the library. Every command struct
  carries a `%CommandKit.Metadata{}` from construction — it is never `nil`.
  The five semantic fields are:

    * `:causation_id` - identity of the message that caused this command
    * `:correlation_id` - identity of the message that started the chain
    * `:enacted_by` - the acting user or system, a string or `nil`
    * `:occurred_at` - when the triggering fact occurred (UTC)
    * `:received_at` - when the trigger reached this service (UTC)

  A freshly constructed command starts its own chain: `causation_id` and
  `correlation_id` both equal the command's URN, and both timestamps are the
  construction time. Use `CommandKit.Command.caused_by/2` when the command is
  triggered by an external event instead.

  ## Additional metadata

  Arbitrary additional key-value pairs are supported through `get/2`, `put/3`,
  and the `Access` behaviour. Additional keys must be atoms.

      meta = CommandKit.Metadata.put(meta, :tenant_id, "abc")
      CommandKit.Metadata.get(meta, :tenant_id)
      #=> "abc"
      meta[:tenant_id]
      #=> "abc"

  Fixed fields are read as struct fields (`meta.enacted_by`) or through the
  same accessors. The five fixed fields cannot be removed: `pop_in/2` on them
  raises `ArgumentError`.

  ## Persistence

  Metadata is the append/envelope context of persisted events, and events
  inherit the command's metadata verbatim. The struct implements
  `Enumerable` over its flat persistence view, so event stores that collect
  metadata with `Enum.into(metadata, %{})` accept it directly:

      append_event(event, command.metadata)

  For stores that expect a plain map, `to_map/1` returns the identical flat
  view of fixed fields and additional pairs:

      append_event(event, CommandKit.Metadata.to_map(command.metadata))
  """

  @behaviour Access

  @fixed_fields [:causation_id, :correlation_id, :enacted_by, :occurred_at, :received_at]

  defstruct causation_id: nil,
            correlation_id: nil,
            enacted_by: nil,
            occurred_at: nil,
            received_at: nil,
            __extra__: %{}

  @type t :: %__MODULE__{
          causation_id: String.t() | nil,
          correlation_id: String.t() | nil,
          enacted_by: String.t() | nil,
          occurred_at: DateTime.t() | nil,
          received_at: DateTime.t() | nil
        }

  @doc false
  def __fixed_fields__, do: @fixed_fields

  @doc """
  Reads a fixed field or an additional metadata value.

  Returns `nil` for absent additional keys. Keys must be atoms.
  """
  @spec get(t(), atom()) :: term()
  def get(%__MODULE__{} = metadata, key) when is_atom(key) do
    if key in @fixed_fields do
      Map.fetch!(metadata, key)
    else
      Map.get(metadata.__extra__, key)
    end
  end

  def get(%__MODULE__{}, key), do: raise_atom_only(key)

  @doc """
  Writes a fixed field or an additional metadata value.

  Fixed fields are validated: `:enacted_by` must be a string or `nil`,
  `:occurred_at` and `:received_at` must be `DateTime`. Keys must be atoms.
  """
  @spec put(t(), atom(), term()) :: t()
  def put(%__MODULE__{} = metadata, key, value) when is_atom(key) do
    if key in @fixed_fields do
      Map.put(metadata, key, validate_fixed!(key, value))
    else
      %{metadata | __extra__: Map.put(metadata.__extra__, key, value)}
    end
  end

  def put(%__MODULE__{}, key, _value), do: raise_atom_only(key)

  @doc """
  Returns one flat map of the five fixed fields and all additional pairs.

  Use this to attach the command's metadata to persisted events.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{__extra__: extra} = metadata) do
    metadata
    |> Map.from_struct()
    |> Map.delete(:__extra__)
    |> Map.merge(extra)
  end

  @doc """
  Derives metadata caused by a persisted event.

  Used in event listeners and in handlers that append an event caused by
  another event. The new `causation_id` is the URN of the triggering event;
  `correlation_id` and `enacted_by` are inherited. `occurred_at` and
  `received_at` are both set to now (UTC) — the follow-up message is a new
  fact; the triggering event's own time stays reachable through the
  causation chain.

  Accepts a `%CommandKit.Metadata{}` or a plain metadata map (as read back
  from an event store). `source` is either the URN prefix string or the
  command base module that carries it as `source:`, so the prefix stays
  configured in one place:

      CommandKit.Metadata.caused_by_event(
        metadata,
        "employee-absence-added",
        event.id,
        MyApp.Command
      )
  """
  @spec caused_by_event(t() | map(), String.t(), term(), String.t() | module()) :: t()
  def caused_by_event(metadata, event_name, event_id, source)
      when is_binary(event_name) and is_binary(source) do
    ensure_kebab_case!(event_name, "event names")
    now = DateTime.utc_now()

    %__MODULE__{
      causation_id: CommandKit.URN.generate(source, event_name, event_id),
      correlation_id: validate_fixed!(:correlation_id, inherited(metadata, :correlation_id)),
      enacted_by: validate_fixed!(:enacted_by, inherited(metadata, :enacted_by)),
      occurred_at: now,
      received_at: now
    }
  end

  def caused_by_event(metadata, event_name, event_id, command_base)
      when is_binary(event_name) and is_atom(command_base) do
    unless function_exported?(command_base, :__command_kit_source__, 0) do
      raise ArgumentError,
            "#{inspect(command_base)} is not a CommandKit command base module. " <>
              "Pass a module defined with `use CommandKit.Core.Command, source: ...` " <>
              "(or CommandKit.Ecto.Command), or pass the source string directly."
    end

    caused_by_event(metadata, event_name, event_id, command_base.__command_kit_source__())
  end

  @doc false
  def chain_start(urn) when is_binary(urn) do
    now = DateTime.utc_now()

    %__MODULE__{
      causation_id: urn,
      correlation_id: urn,
      occurred_at: now,
      received_at: now
    }
  end

  @doc false
  def from_cloud_event(%__MODULE__{} = metadata, %{} = event) do
    type = fetch_event_value!(event, "type")
    id = fetch_event_value!(event, "id")
    causation_id = "#{type}:#{id}"

    metadata = %{
      metadata
      | causation_id: causation_id,
        correlation_id:
          validate_fixed!(:correlation_id, Map.get(event, "correlation_id") || causation_id),
        enacted_by: validate_fixed!(:enacted_by, Map.get(event, "actor")),
        occurred_at: parse_event_time!(event),
        received_at: DateTime.utc_now()
    }

    case Map.get(event, "causation_id") do
      nil -> metadata
      original -> put(metadata, :original_causation_id, original)
    end
  end

  @doc false
  def from_flat_map(%{} = flat) do
    Enum.reduce(flat, %__MODULE__{}, fn {key, value}, metadata ->
      put(metadata, key, value)
    end)
  end

  @impl Access
  def fetch(%__MODULE__{} = metadata, key) when is_atom(key) do
    if key in @fixed_fields do
      {:ok, Map.fetch!(metadata, key)}
    else
      Map.fetch(metadata.__extra__, key)
    end
  end

  def fetch(%__MODULE__{}, key), do: raise_atom_only(key)

  @impl Access
  def get_and_update(%__MODULE__{} = metadata, key, fun) when is_atom(key) do
    current = get(metadata, key)

    case fun.(current) do
      {get_value, new_value} -> {get_value, put(metadata, key, new_value)}
      :pop -> pop(metadata, key)
    end
  end

  def get_and_update(%__MODULE__{}, key, _fun), do: raise_atom_only(key)

  @impl Access
  def pop(%__MODULE__{} = metadata, key) when is_atom(key) do
    if key in @fixed_fields do
      raise ArgumentError,
            "cannot remove fixed metadata field #{inspect(key)}. " <>
              "The five fixed fields are structural; set a new value with put/3 instead."
    else
      {value, extra} = Map.pop(metadata.__extra__, key)
      {value, %{metadata | __extra__: extra}}
    end
  end

  def pop(%__MODULE__{}, key), do: raise_atom_only(key)

  defp inherited(%__MODULE__{} = metadata, key), do: Map.fetch!(metadata, key)
  defp inherited(%{} = metadata, key), do: Map.get(metadata, key)

  defp validate_fixed!(key, value)
       when key in [:enacted_by, :causation_id, :correlation_id] and
              (is_binary(value) or is_nil(value)),
       do: value

  defp validate_fixed!(key, value) when key in [:enacted_by, :causation_id, :correlation_id] do
    raise ArgumentError, "#{key} must be a string or nil, got: #{inspect(value)}"
  end

  defp validate_fixed!(key, value)
       when key in [:occurred_at, :received_at] and is_struct(value, DateTime),
       do: value

  defp validate_fixed!(key, value) when key in [:occurred_at, :received_at] do
    raise ArgumentError, "#{key} must be a DateTime, got: #{inspect(value)}"
  end

  defp fetch_event_value!(event, key) do
    case Map.get(event, key) do
      value when is_binary(value) and value != "" ->
        value

      other ->
        raise ArgumentError,
              "event is missing a usable #{inspect(key)}, got: #{inspect(other)}"
    end
  end

  defp parse_event_time!(event) do
    time = fetch_event_value!(event, "time")

    case DateTime.from_iso8601(time) do
      {:ok, datetime, _offset} ->
        DateTime.shift_zone!(datetime, "Etc/UTC")

      {:error, reason} ->
        raise ArgumentError,
              "event \"time\" #{inspect(time)} is not a valid ISO 8601 datetime: #{inspect(reason)}"
    end
  end

  defp raise_atom_only(key) do
    raise ArgumentError, "metadata keys must be atoms, got: #{inspect(key)}"
  end

  @doc false
  def ensure_kebab_case!(name, label) do
    if String.contains?(name, "_") do
      suggestion = String.replace(name, "_", "-")

      raise ArgumentError,
            "#{label} use '-' instead of '_', like this: #{inspect(suggestion)}"
    end

    name
  end
end

defimpl Inspect, for: CommandKit.Metadata do
  import Inspect.Algebra

  def inspect(metadata, opts) do
    concat(["#CommandKit.Metadata<", to_doc(CommandKit.Metadata.to_map(metadata), opts), ">"])
  end
end

defimpl Enumerable, for: CommandKit.Metadata do
  # Enumerates exactly the flat persistence view of to_map/1, so event
  # stores using Enum.into(metadata, %{}) receive the same map that
  # to_map/1 returns.

  def count(metadata), do: Enumerable.count(CommandKit.Metadata.to_map(metadata))

  def member?(metadata, element),
    do: Enumerable.member?(CommandKit.Metadata.to_map(metadata), element)

  def reduce(metadata, acc, fun),
    do: Enumerable.reduce(CommandKit.Metadata.to_map(metadata), acc, fun)

  def slice(metadata), do: Enumerable.slice(CommandKit.Metadata.to_map(metadata))
end
