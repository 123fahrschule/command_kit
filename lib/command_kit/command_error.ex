defmodule CommandKit.CommandError do
  @moduledoc """
  Raised or returned when command construction fails.

  `new/1` returns `{:error, %CommandKit.CommandError{}}`; `new!/1` raises the
  same struct. Rejected values are intentionally not stored by default.
  """

  defexception [:command, errors: []]

  @type t :: %__MODULE__{
          command: module() | nil,
          errors: [CommandKit.ParamError.t()]
        }

  @impl true
  def message(%__MODULE__{command: command, errors: errors}) do
    command_name = if command, do: inspect(command), else: "command"

    details =
      errors
      |> Enum.map(&format_param_error/1)
      |> Enum.join(", ")

    "invalid #{command_name}: #{details}"
  end

  defp format_param_error(%CommandKit.ParamError{} = error) do
    path = Enum.map_join(error.path, ".", &to_string/1)
    expected = if is_nil(error.expected), do: "", else: " expected=#{inspect(error.expected)}"
    message = if is_nil(error.message), do: "", else: " #{error.message}"
    "#{path} #{error.code}#{expected}#{message}"
  end
end
