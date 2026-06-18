defmodule CommandKit.Result do
  @moduledoc false

  def tag(:ok), do: :ok
  def tag(:unchanged), do: :unchanged
  def tag({:ok, _value}), do: :ok
  def tag({:error, reason}), do: {:error, reason}
  def tag(other), do: {:other, other}

  def cacheable?(:ok), do: true
  def cacheable?(:unchanged), do: true
  def cacheable?({:ok, _value}), do: true
  def cacheable?(_other), do: false
end
