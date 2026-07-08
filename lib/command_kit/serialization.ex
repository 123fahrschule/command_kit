defmodule CommandKit.Serialization do
  @moduledoc """
  Serializes command dispatch data for durable async adapters.

  Runtime context is intentionally not serialized. It is rebuilt when the
  command is executed through the selected bus pipeline.
  """

  alias CommandKit.SerializationError

  @type job_args :: map()

  @spec dump_job(module(), struct(), atom()) :: job_args()
  def dump_job(bus, command, pipeline) do
    %{
      "bus_module" => Atom.to_string(bus),
      "command_module" => Atom.to_string(command.__struct__),
      "params" => dump_command_params(command),
      "command_id" => command.command_id,
      "metadata" => dump_metadata(command.metadata),
      "pipeline" => Atom.to_string(pipeline)
    }
  end

  @spec load_job(job_args()) :: {module(), struct(), atom()}
  def load_job(args) when is_map(args) do
    bus = module_from_string!(Map.fetch!(args, "bus_module"))
    command_module = module_from_string!(Map.fetch!(args, "command_module"))
    pipeline = atom_from_string!(Map.fetch!(args, "pipeline"))
    params = load_command_params(command_module, Map.fetch!(args, "params"))
    metadata = load_metadata(Map.fetch!(args, "metadata"))

    case command_module.new(params) do
      {:ok, command} ->
        command = %{command | command_id: Map.fetch!(args, "command_id"), metadata: metadata}
        {bus, command, pipeline}

      {:error, error} ->
        raise SerializationError, message: Exception.message(error)
    end
  end

  @spec dump_command_params(struct()) :: map()
  def dump_command_params(command) do
    command.__struct__.__command_kit_params__()
    |> Enum.map(fn field ->
      {to_string(field.name), dump_value(Map.get(command, field.name))}
    end)
    |> Map.new()
  end

  @spec load_command_params(module(), map()) :: map()
  def load_command_params(command_module, params) do
    command_module.__command_kit_params__()
    |> Enum.map(fn field ->
      {field.name, load_value(Map.get(params, to_string(field.name)))}
    end)
    |> Map.new()
  end

  @spec dump_metadata(CommandKit.Metadata.t()) :: list()
  def dump_metadata(%CommandKit.Metadata{} = metadata) do
    metadata
    |> CommandKit.Metadata.to_map()
    |> Enum.map(fn {key, value} -> %{"key" => dump_key(key), "value" => dump_value(value)} end)
  end

  @spec load_metadata(list()) :: CommandKit.Metadata.t()
  def load_metadata(entries) when is_list(entries) do
    entries
    |> Enum.map(fn %{"key" => key, "value" => value} -> {load_key(key), load_value(value)} end)
    |> Map.new()
    |> CommandKit.Metadata.from_flat_map()
  end

  def dump_value(nil), do: nil
  def dump_value(value) when is_binary(value) or is_integer(value) or is_boolean(value), do: value

  def dump_value(%Decimal{} = value) do
    %{"__command_kit_type__" => "decimal", "value" => Decimal.to_string(value)}
  end

  def dump_value(%Date{} = value) do
    %{"__command_kit_type__" => "date", "value" => Date.to_iso8601(value)}
  end

  def dump_value(%DateTime{} = value) do
    %{"__command_kit_type__" => "datetime", "value" => DateTime.to_iso8601(value)}
  end

  def dump_value(value) when is_list(value), do: Enum.map(value, &dump_value/1)

  def dump_value(value) when is_map(value) do
    if Enum.all?(Map.keys(value), &is_binary/1) do
      value
      |> Enum.map(fn {key, nested} -> {key, dump_value(nested)} end)
      |> Map.new()
    else
      # Integer keys would be silently stringified by JSON encoding, so maps
      # containing them are dumped as an entry list that round-trips both
      # key types.
      %{
        "__command_kit_type__" => "map_entries",
        "entries" =>
          Enum.map(value, fn {key, nested} -> [dump_map_key(key), dump_value(nested)] end)
      }
    end
  end

  def dump_value(value) do
    raise SerializationError, message: "unsupported serialization value #{inspect(value)}"
  end

  def load_value(%{"__command_kit_type__" => "decimal", "value" => value}), do: Decimal.new(value)

  def load_value(%{"__command_kit_type__" => "date", "value" => value}),
    do: Date.from_iso8601!(value)

  def load_value(%{"__command_kit_type__" => "datetime", "value" => value}) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      {:error, reason} -> raise SerializationError, message: "invalid datetime #{inspect(reason)}"
    end
  end

  def load_value(%{"__command_kit_type__" => "map_entries", "entries" => entries}) do
    Map.new(entries, fn [key, value] -> {key, load_value(value)} end)
  end

  def load_value(value) when is_list(value), do: Enum.map(value, &load_value/1)

  def load_value(value) when is_map(value) do
    value
    |> Enum.map(fn {key, nested} -> {key, load_value(nested)} end)
    |> Map.new()
  end

  def load_value(value)
      when is_nil(value) or is_binary(value) or is_integer(value) or is_boolean(value) do
    value
  end

  defp dump_key(key) when is_atom(key), do: %{"type" => "atom", "value" => Atom.to_string(key)}
  defp dump_key(key) when is_binary(key), do: %{"type" => "string", "value" => key}

  defp dump_key(key) do
    raise SerializationError, message: "unsupported metadata key #{inspect(key)}"
  end

  defp load_key(%{"type" => "atom", "value" => value}), do: atom_from_string!(value)
  defp load_key(%{"type" => "string", "value" => value}), do: value

  defp dump_map_key(key) when is_binary(key) or is_integer(key), do: key

  defp dump_map_key(key) do
    raise SerializationError, message: "unsupported map key #{inspect(key)}"
  end

  defp module_from_string!(value), do: String.to_existing_atom(value)
  defp atom_from_string!(value), do: String.to_existing_atom(value)
end
