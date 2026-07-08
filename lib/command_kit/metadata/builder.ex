defmodule CommandKit.Metadata.Builder do
  @moduledoc false

  alias CommandKit.CommandError
  alias CommandKit.ParamError

  def new(meta_module, attrs) when is_atom(meta_module) do
    attrs = attrs |> normalize_input() |> apply_defaults(meta_module)

    with {:ok, attr_map} <- normalize_attrs(meta_module, attrs),
         {:ok, values} <- cast_fields(meta_module, attr_map) do
      {:ok, struct(meta_module, values)}
    end
  end

  def new!(meta_module, attrs \\ %{}) do
    case new(meta_module, attrs) do
      {:ok, metadata} -> metadata
      {:error, %CommandError{} = error} -> raise error
    end
  end

  defp normalize_input(attrs) when is_list(attrs), do: Map.new(attrs)
  defp normalize_input(attrs) when is_map(attrs), do: attrs

  defp apply_defaults(attrs, meta_module) do
    Enum.reduce(meta_module.__command_kit_metadata_fields__(), attrs, fn field, acc ->
      if field.has_default? and not Map.has_key?(acc, field.name) do
        Map.put(acc, field.name, meta_module.__command_kit_metadata_default__(field.name))
      else
        acc
      end
    end)
  end

  defp normalize_attrs(meta_module, attrs) do
    fields = meta_module.__command_kit_metadata_fields__()
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
              message: "is not declared by the metadata"
            }

            {normalized, [error | errors]}
        end
      end)

    if errors == [] do
      {:ok, normalized}
    else
      {:error, %CommandError{command: meta_module, errors: Enum.reverse(errors)}}
    end
  end

  defp cast_fields(meta_module, attrs) do
    {values, errors} =
      Enum.reduce(meta_module.__command_kit_metadata_fields__(), {%{}, []}, fn field,
                                                                               {values, errors} ->
        case cast_field(field, attrs) do
          {:ok, value} -> {Map.put(values, field.name, value), errors}
          {:error, error} -> {values, [error | errors]}
        end
      end)

    if errors == [] do
      {:ok, values}
    else
      {:error, %CommandError{command: meta_module, errors: Enum.reverse(errors)}}
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

  defp cast_value(name, type, value) do
    case CommandKit.Types.cast_core(type, value) do
      {:ok, casted} ->
        {:ok, casted}

      :error ->
        {:error,
         %ParamError{
           path: [name],
           code: :invalid_type,
           expected: type,
           message: "has an unsupported value for the declared type"
         }}
    end
  end

  defp required_error(name, type) do
    {:error, %ParamError{path: [name], code: :required, expected: type, message: "is required"}}
  end
end
