defmodule CommandKit.Ecto.Command.Builder do
  @moduledoc false

  alias CommandKit.CommandError
  alias CommandKit.ParamError

  def new(command_module, attrs) when is_atom(command_module) do
    {metadata, attrs} = extract_metadata(attrs)

    with {:ok, attr_map} <- normalize_attrs(command_module, attrs),
         {:ok, values} <- cast_fields(command_module, attr_map),
         {:ok, values} <- maybe_cast_metadata(command_module, values, metadata) do
      {:ok, struct(command_module, values)}
    end
  end

  def new(command_module, attrs, metadata) when is_atom(command_module) do
    meta_module = command_module.__command_kit_metadata_module__()

    with {:ok, attr_map} <- normalize_attrs(command_module, attrs),
         {:ok, values} <- cast_fields(command_module, attr_map),
         {:ok, meta} <- cast_metadata(meta_module, metadata) do
      {:ok, struct(command_module, Map.put(values, :metadata, meta))}
    end
  end

  def new!(command_module, attrs) do
    case new(command_module, attrs) do
      {:ok, command} -> command
      {:error, %CommandError{} = error} -> raise error
    end
  end

  def new!(command_module, attrs, metadata) do
    case new(command_module, attrs, metadata) do
      {:ok, command} -> command
      {:error, %CommandError{} = error} -> raise error
    end
  end

  defp extract_metadata(attrs) when is_list(attrs), do: Keyword.pop(attrs, :metadata)
  defp extract_metadata(attrs) when is_map(attrs), do: Map.pop(attrs, :metadata)

  defp maybe_cast_metadata(_command_module, values, nil), do: {:ok, values}

  defp maybe_cast_metadata(command_module, values, metadata) do
    meta_module = command_module.__command_kit_metadata_module__()

    with {:ok, meta} <- cast_metadata(meta_module, metadata) do
      {:ok, Map.put(values, :metadata, meta)}
    end
  end

  defp cast_metadata(_meta_module, %{__struct__: _} = metadata), do: {:ok, metadata}

  defp cast_metadata(meta_module, metadata) when is_atom(meta_module) do
    CommandKit.Metadata.Builder.new(meta_module, metadata)
  end

  defp normalize_attrs(command_module, attrs) when is_list(attrs) do
    normalize_attrs(command_module, Map.new(attrs))
  end

  defp normalize_attrs(command_module, attrs) when is_map(attrs) do
    fields = command_module.__command_kit_params__()
    names = MapSet.new(Enum.map(fields, & &1.name))
    string_names = MapSet.new(Enum.map(fields, &to_string(&1.name)))

    {normalized, errors} =
      Enum.reduce(attrs, {%{}, []}, fn {key, value}, {normalized, errors} ->
        cond do
          is_atom(key) and MapSet.member?(names, key) ->
            {Map.put(normalized, key, value), errors}

          is_binary(key) and MapSet.member?(string_names, key) ->
            {Map.put(normalized, String.to_existing_atom(key), value), errors}

          true ->
            error = %ParamError{
              path: [key],
              code: :unknown_field,
              message: "is not declared by the command"
            }

            {normalized, [error | errors]}
        end
      end)

    if errors == [] do
      {:ok, normalized}
    else
      {:error, %CommandError{command: command_module, errors: Enum.reverse(errors)}}
    end
  end

  defp normalize_attrs(command_module, _attrs) do
    {:error,
     %CommandError{
       command: command_module,
       errors: [
         %ParamError{
           path: [],
           code: :invalid_attributes,
           message: "must be a map or keyword list"
         }
       ]
     }}
  end

  defp cast_fields(command_module, attrs) do
    {values, errors} =
      Enum.reduce(command_module.__command_kit_params__(), {%{}, []}, fn field,
                                                                         {values, errors} ->
        case cast_field(field, attrs) do
          {:ok, value} -> {Map.put(values, field.name, value), errors}
          {:error, error} -> {values, [error | errors]}
        end
      end)

    if errors == [] do
      {:ok, values}
    else
      {:error, %CommandError{command: command_module, errors: Enum.reverse(errors)}}
    end
  end

  defp cast_field(%{name: name, type: type, required?: true}, attrs) do
    case Map.fetch(attrs, name) do
      {:ok, nil} -> required_error(name, type)
      {:ok, value} -> cast_value(name, type, value)
      :error -> required_error(name, type)
    end
  end

  defp cast_field(%{name: name, type: type, required?: false}, attrs) do
    case Map.fetch(attrs, name) do
      {:ok, nil} -> {:ok, nil}
      {:ok, value} -> cast_value(name, type, value)
      :error -> {:ok, nil}
    end
  end

  defp cast_value(name, type, value) when type in [:map, :list] do
    case CommandKit.Types.cast_core(type, value) do
      {:ok, casted} -> {:ok, casted}
      :error -> invalid_type_error(name, type)
    end
  end

  defp cast_value(name, type, value) do
    ecto_type = ecto_type(type)

    case Ecto.Type.cast(ecto_type, value) do
      {:ok, casted} -> {:ok, casted}
      :error -> invalid_type_error(name, type)
      {:error, _metadata} -> invalid_type_error(name, type)
    end
  end

  defp ecto_type(:string), do: :string
  defp ecto_type(:integer), do: :integer
  defp ecto_type(:boolean), do: :boolean
  defp ecto_type(:decimal), do: :decimal
  defp ecto_type(:date), do: :date
  defp ecto_type(:datetime), do: :utc_datetime

  defp invalid_type_error(name, type) do
    {:error,
     %ParamError{
       path: [name],
       code: :invalid_type,
       expected: type,
       message: "cannot be cast to the declared type"
     }}
  end

  defp required_error(name, type) do
    {:error, %ParamError{path: [name], code: :required, expected: type, message: "is required"}}
  end
end
