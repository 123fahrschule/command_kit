defmodule CommandKit.Serialization do
  @moduledoc """
  Serializes command dispatch data for durable async adapters.

  Runtime context is intentionally not serialized. It is rebuilt when the
  command is executed through the selected bus pipeline.
  """

  alias CommandKit.SerializationError

  @type job_args :: map()

  @spec dump_job(module(), struct(), keyword() | map() | struct(), atom()) :: job_args()
  def dump_job(bus, command, metadata, pipeline) do
    resolved_metadata = resolve_metadata_for_dump(command, metadata)

    %{
      "bus_module" => Atom.to_string(bus),
      "command_module" => Atom.to_string(command.__struct__),
      "params" => dump_command_params(command),
      "metadata" => dump_metadata(resolved_metadata),
      "pipeline" => Atom.to_string(pipeline)
    }
  end

  @spec load_job(job_args()) :: {module(), struct(), map() | keyword(), atom()}
  def load_job(args) when is_map(args) do
    bus = module_from_string!(Map.fetch!(args, "bus_module"))
    command_module = module_from_string!(Map.fetch!(args, "command_module"))
    pipeline = atom_from_string!(Map.fetch!(args, "pipeline"))
    params = load_command_params(command_module, Map.fetch!(args, "params"))
    metadata = load_metadata(Map.fetch!(args, "metadata"))

    meta_module = command_module.__command_kit_metadata_module__()

    case build_command_with_metadata(command_module, params, metadata, meta_module) do
      {:ok, command} -> {bus, command, metadata, pipeline}
      {:error, error} -> raise SerializationError, message: Exception.message(error)
    end
  end

  defp resolve_metadata_for_dump(command, metadata) when metadata == %{} do
    case Map.fetch(command, :metadata) do
      {:ok, %{__struct__: _} = meta} -> Map.from_struct(meta)
      _ -> metadata
    end
  end

  defp resolve_metadata_for_dump(_command, %{__struct__: _} = metadata) do
    Map.from_struct(metadata)
  end

  defp resolve_metadata_for_dump(_command, metadata), do: metadata

  defp build_command_with_metadata(command_module, params, _metadata, nil) do
    command_module.new(params)
  end

  defp build_command_with_metadata(command_module, params, metadata, _meta_module) do
    command_module.new(params, metadata)
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

  @spec dump_metadata(keyword() | map()) :: list()
  def dump_metadata(metadata) when is_list(metadata) or is_map(metadata) do
    metadata
    |> Enum.map(fn {key, value} -> %{"key" => dump_key(key), "value" => dump_value(value)} end)
  end

  @spec load_metadata(list()) :: map()
  def load_metadata(entries) when is_list(entries) do
    entries
    |> Enum.map(fn %{"key" => key, "value" => value} -> {load_key(key), load_value(value)} end)
    |> Map.new()
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
    value
    |> Enum.map(fn {key, nested} -> {dump_map_key(key), dump_value(nested)} end)
    |> Map.new()
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

  defp dump_map_key(key) when is_binary(key), do: key
  defp dump_map_key(key) when is_integer(key), do: Integer.to_string(key)

  defp dump_map_key(key) do
    raise SerializationError, message: "unsupported map key #{inspect(key)}"
  end

  defp module_from_string!(value), do: String.to_existing_atom(value)
  defp atom_from_string!(value), do: String.to_existing_atom(value)
end
