defmodule CommandKit.ParamError do
  @moduledoc """
  Describes a single command parameter construction error.

  `path` identifies the failing field and can later represent nested map or
  list locations. `code` is a stable machine-readable reason such as
  `:required`, `:invalid_type`, `:unknown_field`, or `:unsupported_type`.
  `expected` carries the declared command type when one applies.
  """

  @enforce_keys [:path, :code]
  defstruct [:path, :code, :expected, :message]

  @type t :: %__MODULE__{
          path: [atom() | String.t() | non_neg_integer()],
          code: atom(),
          expected: term(),
          message: String.t() | nil
        }
end
