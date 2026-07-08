defmodule CommandKit.Metadata do
  @moduledoc """
  Defines a typed metadata struct for commands.

      defmodule MyApp.CommandMetadata do
        use CommandKit.Metadata

        field :enacted_by, :string, optional: true
        field :correlation_id, :string, optional: true
        field :causation_id, :string, optional: true
        field :message_id, :string, optional: true
        field :message_uuid, :string, default: Ecto.UUID.generate()
        field :occurred_at, :datetime, default: DateTime.utc_now()
        field :received_at, :datetime, default: DateTime.utc_now()
      end

  Attach to a command base module:

      defmodule MyApp.Command do
        use CommandKit.Core.Command, metadata: MyApp.CommandMetadata
      end

  Build a metadata struct and pass it when constructing a command:

      meta = MyApp.CommandMetadata.new!(%{enacted_by: "user-123"})
      cmd  = MyApp.DoSomethingCommand.new!(attrs, meta)

  Or pass a plain map — the command constructor casts it automatically:

      cmd = MyApp.DoSomethingCommand.new!(attrs, %{enacted_by: "user-123"})

  The handler receives the typed struct:

      def execute(%DoSomethingCommand{} = cmd, %MyApp.CommandMetadata{} = meta) do
        meta.enacted_by
      end

  ## Field options

    * `:optional` — when `true`, the field is not required (defaults to `false`)
    * `:default` — an expression evaluated fresh on each `new/1` call when the
      field is absent. Setting a default implies `optional: true`.
  """

  defmacro __using__(_opts) do
    quote do
      Module.register_attribute(__MODULE__, :command_kit_metadata_fields, accumulate: true)
      import CommandKit.Metadata, only: [field: 2, field: 3]
      @before_compile CommandKit.Metadata
    end
  end

  defmacro field(name, type, opts \\ []) do
    optional? = Keyword.get(opts, :optional, false)
    has_default? = Keyword.has_key?(opts, :default)
    default_expr = Keyword.get(opts, :default)

    field_registration =
      quote do
        unless is_atom(unquote(name)) do
          raise ArgumentError, "metadata field names must be atoms, got: #{inspect(unquote(name))}"
        end

        CommandKit.Types.normalize_type!(unquote(type))

        @command_kit_metadata_fields %{
          name: unquote(name),
          type: unquote(type),
          required?: not unquote(optional?) and not unquote(has_default?),
          optional?: unquote(optional?) or unquote(has_default?),
          has_default?: unquote(has_default?)
        }
      end

    if has_default? do
      quote do
        unquote(field_registration)

        def __command_kit_metadata_default__(unquote(name)), do: unquote(default_expr)
      end
    else
      field_registration
    end
  end

  defmacro __before_compile__(env) do
    fields =
      env.module
      |> Module.get_attribute(:command_kit_metadata_fields)
      |> Enum.reverse()

    field_names = Enum.map(fields, & &1.name)

    quote do
      defstruct unquote(field_names)

      def __command_kit_metadata_default__(_), do: :no_default

      @doc "Builds a typed metadata struct from attributes."
      @spec new(map() | keyword()) :: {:ok, struct()} | {:error, CommandKit.CommandError.t()}
      def new(attrs \\ %{}), do: CommandKit.Metadata.Builder.new(__MODULE__, attrs)

      @doc "Builds a typed metadata struct from attributes or raises `CommandKit.CommandError`."
      @spec new!(map() | keyword()) :: struct()
      def new!(attrs \\ %{}), do: CommandKit.Metadata.Builder.new!(__MODULE__, attrs)

      @doc false
      def __command_kit_metadata_fields__, do: unquote(Macro.escape(fields))

      @doc false
      def __command_kit_metadata__?, do: true
    end
  end
end
