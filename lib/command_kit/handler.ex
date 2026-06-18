defprotocol CommandKit.Handler do
  @moduledoc """
  Optional protocol for resolving command handlers outside the command DSL.

  The recommended path is declaring `handler MyApp.Service` inside the command
  module. This protocol remains available for applications that prefer a
  separate registration style.
  """

  @fallback_to_any true

  @spec handler(struct()) :: module() | nil
  def handler(command)
end

defimpl CommandKit.Handler, for: Any do
  def handler(_command), do: nil
end
