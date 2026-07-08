defmodule CommandKit.Ecto.Command do
  @moduledoc """
  Defines an application-local command base module backed by Ecto casting.

  Command modules still use CommandKit's command DSL:

      defmodule MyApp.Command do
        use CommandKit.Ecto.Command, source: "de.123fahrschule:my_app"
      end

      defmodule MyApp.Commands.RequestAbsence do
        use MyApp.Command

        params do
          field :employee_id, :integer
          field :starts_on, :date
          field :ends_on, :date
          field :comment, :string, optional: true
        end
      end

  The required `:source` option is the application-wide URN prefix used for
  command identity and correlation (see `CommandKit.Metadata`). It must be a
  compile-time string.

  Ecto remains an implementation detail. Command modules do not define
  `embedded_schema` or `changeset` functions.
  """

  defmacro __using__(opts \\ []) do
    opts = Keyword.put_new(opts, :builder, CommandKit.Ecto.Command.Builder)
    CommandKit.Core.Command.define_base(opts, "CommandKit.Ecto.Command")
  end
end
