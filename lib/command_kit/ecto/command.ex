defmodule CommandKit.Ecto.Command do
  @moduledoc """
  Defines an application-local command base module backed by Ecto casting.

  Command modules still use CommandKit's command DSL:

      defmodule MyApp.Command do
        use CommandKit.Ecto.Command
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

  Ecto remains an implementation detail. Command modules do not define
  `embedded_schema` or `changeset` functions.
  """

  defmacro __using__(opts \\ []) do
    opts = Keyword.put_new(opts, :builder, CommandKit.Ecto.Command.Builder)
    escaped_opts = Macro.escape(opts)

    quote do
      defmacro __using__(command_opts \\ []) do
        opts = Keyword.merge(unquote(escaped_opts), command_opts)

        quote do
          use CommandKit.Core.Command.Schema, unquote(Macro.escape(opts))
        end
      end
    end
  end
end
