# Commands

Commands represent a single application intent. They contain command data only;
caller metadata and execution services belong elsewhere.

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

The bus calls `execute/3` when the handler exports it, otherwise it falls back
to `execute/2`.

```elixir
def execute(command, metadata), do: :ok

def execute(command, metadata, context), do: {:ok, %{id: 123}}
```

Use `execute/3` only when the handler needs runtime context.

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
