# Commands

Commands represent a single application intent. They carry domain parameters and,
optionally, a typed metadata struct with caller context such as `enacted_by` and
`correlation_id`. Execution services belong in the runtime context instead.

## Command Base Modules

Applications define a local base module:

```elixir
defmodule MyApp.Command do
  use CommandKit.Core.Command
end
```

or:

```elixir
defmodule MyApp.Command do
  use CommandKit.Ecto.Command
end
```

`CommandKit.Core.Command` validates already-typed values.
`CommandKit.Ecto.Command` uses Ecto internally to cast adapter input such as
form or JSON strings. Command modules do not expose `Ecto.Schema`,
`embedded_schema`, or `changeset`.

To attach a typed metadata struct to every command, pass the `metadata:` option:

```elixir
defmodule MyApp.Command do
  use CommandKit.Ecto.Command, metadata: MyApp.CommandMetadata
end
```

See the [Metadata guide](metadata.md) for how to define `MyApp.CommandMetadata`.

## Params

```elixir
params do
  field :employee_id, :integer
  field :starts_on, :date
  field :ends_on, :date
  field :comment, :string, optional: true
end
```

Fields are required by default. Use `optional: true` only for data that does
not change the command intent, such as comments, references, or external IDs.

Supported command field types in v1:

- `:string`
- `:integer`
- `:boolean`
- `:decimal`
- `:date`
- `:datetime`
- `:map`
- `:list`

Maps and lists must contain supported scalar/value types. Custom parameter
types are intentionally out of scope for v1 so handlers stay callable from all
application adapters.

## Constructors

Commands expose:

```elixir
Command.new(attrs)
Command.new!(attrs)
```

`new/1` returns `{:ok, command}` or `{:error, %CommandKit.CommandError{}}`.
`new!/1` returns the command or raises the same `CommandKit.CommandError`.

When the command base module has a `metadata:` module configured, metadata can
be passed inline as the `:metadata` key:

```elixir
Command.new(%{field: value, metadata: %{enacted_by: "user-123"}})
```

or as a second argument (map, keyword, or already-built struct):

```elixir
Command.new(%{field: value}, %{enacted_by: "user-123"})
Command.new(%{field: value}, MyApp.CommandMetadata.new!(%{enacted_by: "user-123"}))
```

Construction errors are command-level errors:

```elixir
%CommandKit.CommandError{
  command: MyApp.Commands.RecordPayout,
  errors: [
    %CommandKit.ParamError{
      path: [:paid_on],
      code: :required,
      expected: :date
    }
  ]
}
```

Rejected values are not included by default to avoid leaking personal data or
secrets into logs or API responses.

## Handler DSL

Declare the handler next to the command:

```elixir
handler MyApp.FundingRequests.RecordPayout
```

The bus dispatches to whichever arity the handler exports: `execute/1`,
`execute/2`, or `execute/3`. Use `execute/1` when the command carries typed
metadata inside:

```elixir
def execute(command) do
  command.metadata.enacted_by
  {:ok, %{id: 123}}
end
```

Use `execute/2` when metadata is passed separately, or `execute/3` when you
also need runtime context.

A handler module must export a single arity. If multiple arities are defined
(e.g., for different commands), the bus picks the first match by priority:
`execute/1` > `execute/2` > `execute/3`. Use separate handler modules when
different commands require different arities.

Handlers should return the command result, not the command itself. Recommended
result shapes are `:ok`, `{:ok, value}`, and `{:error, reason}`.

## Protocol-Based Handler Resolution

For the common one-command-to-one-handler case, prefer the `handler` DSL because
it keeps the command wiring local and easy to read.

If a command does not declare `handler`, the bus falls back to the
`CommandKit.Handler` protocol. That allows applications to resolve handlers
outside the command module, including with pattern matching on already-typed
command data:

```elixir
defmodule MyApp.Commands.SendEmail do
  use MyApp.Command

  params do
    field :delivery, :string
    field :recipient_id, :integer
  end
end

defimpl CommandKit.Handler, for: MyApp.Commands.SendEmail do
  def handler(%{delivery: "transactional"}), do: MyApp.Mail.SendTransactionalEmail
  def handler(%{delivery: "bulk"}), do: MyApp.Mail.SendBulkEmail
end
```

Use protocol-based resolution deliberately. It is useful when routing is a
technical execution choice for the same application intent. If different
branches represent different business intents, define separate commands with
clear names instead.
