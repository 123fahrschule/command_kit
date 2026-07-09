defmodule CommandKit.Core.Command do
  @moduledoc """
  Defines an application-local base module for dependency-light commands.

      defmodule MyApp.Command do
        use CommandKit.Core.Command, source: "de.123fahrschule:my_app"
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

  The required `:source` option is the application-wide URN prefix used for
  command identity and correlation (see `CommandKit.Metadata`). It must be a
  compile-time string.

  Core commands validate already-typed values. Use `CommandKit.Ecto.Command`
  when callers should be able to pass strings and have Ecto cast them into
  typed command values.
  """

  defmacro __using__(opts \\ []) do
    CommandKit.Core.Command.define_base(opts, "CommandKit.Core.Command")
  end

  @doc false
  def define_base(opts, base_name) do
    escaped_opts = Macro.escape(opts)

    quote bind_quoted: [escaped_opts: escaped_opts, base_name: base_name] do
      @command_kit_source CommandKit.Core.Command.validate_source!(
                            Keyword.get(escaped_opts, :source),
                            base_name
                          )

      @doc false
      def __command_kit_source__, do: @command_kit_source

      @command_kit_base_opts escaped_opts

      # The base module installs its own __using__/1 on the application's
      # command base so every command module inherits the base opts
      # (:source, :builder). Merging happens here rather than in the Schema
      # so per-command opts can be rejected — :source is application-wide.
      defmacro __using__(command_opts \\ []) do
        if Keyword.has_key?(command_opts, :source) do
          raise ArgumentError,
                ":source is the application-wide URN prefix and is configured once on " <>
                  "#{inspect(__MODULE__)} — it cannot be overridden per command"
        end

        opts = Keyword.merge(@command_kit_base_opts, command_opts)

        quote do
          use CommandKit.Core.Command.Schema, unquote(Macro.escape(opts))
        end
      end
    end
  end

  @doc false
  def validate_source!(source, base_name) when is_binary(source) do
    if String.trim(source) == "" do
      invalid_source!(source, base_name)
    else
      source
    end
  end

  def validate_source!(source, base_name), do: invalid_source!(source, base_name)

  defp invalid_source!(source, base_name) do
    raise ArgumentError, """
    #{base_name} requires a :source option with the application-wide URN prefix, \
    got: #{inspect(source)}

    Example:

        use #{base_name}, source: "de.123fahrschule:my_app"
    """
  end
end
