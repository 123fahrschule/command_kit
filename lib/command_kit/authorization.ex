defprotocol CommandKit.Authorization do
  @moduledoc """
  Optional protocol for command authorization.

  Authorizers read the actor from the command's metadata
  (`command.metadata.enacted_by`). Applications can also configure an
  authorizer module directly on `CommandKit.Middleware.Authorization`.
  """

  @fallback_to_any true

  @spec authorize(struct(), CommandKit.Context.t()) :: :ok | {:error, term()}
  def authorize(command, context)
end

defimpl CommandKit.Authorization, for: Any do
  def authorize(_command, _context), do: :ok
end
