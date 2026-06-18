defmodule CommandKit.Types do
  @moduledoc false

  @supported_types [:string, :integer, :boolean, :decimal, :date, :datetime, :map, :list]

  def supported_types, do: @supported_types

  def normalize_type!(type) when type in @supported_types, do: type

  def normalize_type!(type) do
    raise ArgumentError,
          "unsupported command parameter type #{inspect(type)}. " <>
            "Supported types: #{Enum.map_join(@supported_types, ", ", &inspect/1)}"
  end

  def cast_core(:string, value) when is_binary(value), do: {:ok, value}
  def cast_core(:integer, value) when is_integer(value), do: {:ok, value}
  def cast_core(:boolean, value) when is_boolean(value), do: {:ok, value}
  def cast_core(:decimal, %Decimal{} = value), do: {:ok, value}
  def cast_core(:date, %Date{} = value), do: {:ok, value}
  def cast_core(:datetime, %DateTime{} = value), do: {:ok, value}

  def cast_core(:map, value) when is_map(value) do
    if supported_value?(value), do: {:ok, value}, else: :error
  end

  def cast_core(:list, value) when is_list(value) do
    if supported_value?(value), do: {:ok, value}, else: :error
  end

  def cast_core(_type, _value), do: :error

  def supported_value?(value)
      when is_nil(value) or is_binary(value) or is_integer(value) or is_boolean(value),
      do: true

  def supported_value?(%Decimal{}), do: true
  def supported_value?(%Date{}), do: true
  def supported_value?(%DateTime{}), do: true

  def supported_value?(value) when is_list(value), do: Enum.all?(value, &supported_value?/1)

  def supported_value?(value) when is_map(value) do
    Enum.all?(value, fn {key, nested} -> supported_key?(key) and supported_value?(nested) end)
  end

  def supported_value?(_value), do: false

  defp supported_key?(key) when is_binary(key) or is_integer(key), do: true
  defp supported_key?(_key), do: false
end
