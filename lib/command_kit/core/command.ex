defmodule CommandKit.Core.Command do
  @moduledoc """
  Defines an application-local base module for dependency-light commands.

      defmodule MyApp.Command do
        use CommandKit.Core.Command
      end

      defmodule MyApp.Commands.RecordPayout do
        use MyApp.Command

        params do
          field :funding_request_id, :integer
          field :paid_on, :date
          field :paid_reference, :string, optional: true
        end

        handler MyApp.FundingRequests.RecordPayout
      end

  Core commands validate already-typed values. Use `CommandKit.Ecto.Command`
  when callers should be able to pass strings and have Ecto cast them into
  typed command values.
  """

  defmacro __using__(opts \\ []) do
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
