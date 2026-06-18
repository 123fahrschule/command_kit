defprotocol CommandKit.Authorization do
  @moduledoc """
  Optional protocol for command authorization.

  Applications can also configure an authorizer module directly on
  `CommandKit.Middleware.Authorization`.
  """

  @fallback_to_any true

  @spec authorize(struct(), keyword() | map(), CommandKit.Context.t()) :: :ok | {:error, term()}
  def authorize(command, metadata, context)
end

defimpl CommandKit.Authorization, for: Any do
  def authorize(_command, _metadata, _context), do: :ok
end
