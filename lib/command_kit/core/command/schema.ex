defmodule CommandKit.Core.Command.Schema do
  @moduledoc false

  defmacro __using__(opts) do
    builder = Keyword.get(opts, :builder, CommandKit.Core.Command.Builder)

    quote bind_quoted: [builder: builder] do
      @command_kit_builder builder
      @command_kit_handler nil

      Module.register_attribute(__MODULE__, :command_kit_fields, accumulate: true)

      import CommandKit.Core.Command.Schema,
        only: [params: 1, field: 2, field: 3, handler: 1]

      @before_compile CommandKit.Core.Command.Schema
    end
  end

  defmacro params(do: block), do: block

  defmacro field(name, type, opts \\ []) do
    quote bind_quoted: [name: name, type: type, opts: opts] do
      unless is_atom(name) do
        raise ArgumentError, "command field names must be atoms, got: #{inspect(name)}"
      end

      type = CommandKit.Types.normalize_type!(type)
      optional? = Keyword.get(opts, :optional, false)

      unless is_boolean(optional?) do
        raise ArgumentError, "field #{inspect(name)} option :optional must be a boolean"
      end

      @command_kit_fields %{
        name: name,
        type: type,
        required?: not optional?,
        optional?: optional?
      }
    end
  end

  defmacro handler(handler_module) do
    expanded = Macro.expand(handler_module, __CALLER__)

    unless is_atom(expanded) do
      raise ArgumentError,
            "handler must be a module alias, got: #{Macro.to_string(handler_module)}"
    end

    quote bind_quoted: [handler_module: expanded] do
      @command_kit_handler handler_module
    end
  end

  defmacro __before_compile__(env) do
    fields =
      env.module
      |> Module.get_attribute(:command_kit_fields)
      |> Enum.reverse()

    field_names = Enum.map(fields, & &1.name)
    handler = Module.get_attribute(env.module, :command_kit_handler)
    builder = Module.get_attribute(env.module, :command_kit_builder)

    quote do
      defstruct unquote(field_names)

      @doc "Builds a typed command struct from attributes."
      @spec new(map() | keyword()) :: {:ok, struct()} | {:error, CommandKit.CommandError.t()}
      def new(attrs), do: unquote(builder).new(__MODULE__, attrs)

      @doc "Builds a typed command struct from attributes or raises `CommandKit.CommandError`."
      @spec new!(map() | keyword()) :: struct()
      def new!(attrs), do: unquote(builder).new!(__MODULE__, attrs)

      @doc false
      def __command_kit_params__, do: unquote(Macro.escape(fields))

      @doc false
      def __command_kit_handler__, do: unquote(handler)

      @doc false
      def __command_kit_command__?, do: true
    end
  end
end
