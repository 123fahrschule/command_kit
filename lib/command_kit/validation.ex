defprotocol CommandKit.Validation do
  @moduledoc """
  Optional protocol for command validation middleware.
  """

  @fallback_to_any true

  @spec validate(struct()) :: :ok | {:error, term()}
  def validate(command)
end

defimpl CommandKit.Validation, for: Any do
  def validate(_command), do: :ok
end
