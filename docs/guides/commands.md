# Commands

Commands represent a single application intent. They carry domain parameters,
an identity (`command_id` plus a kebab-case command name), and correlation
metadata (see the [Metadata guide](metadata.md)). Execution services belong
in the runtime context.

## Command Base Modules

Applications define a local base module with the service's URN source:

```elixir
defmodule MyApp.Command do
  use CommandKit.Core.Command, source: "de.123fahrschule:my_app"
end
```

or:

```elixir
defmodule MyApp.Command do
  use CommandKit.Ecto.Command, source: "de.123fahrschule:my_app"
end
```

The `:source` option is required — it prefixes the URNs used for causation
and correlation. `CommandKit.Core.Command` validates already-typed values.
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
The names `:metadata` and `:command_id` are reserved by CommandKit and cannot
be declared as params.

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

Construction also generates the command's identity: a fresh `command_id`
(UUID) and chain-start metadata. The command name defaults to the module's
last segment in kebab-case (`RecordPayout` → `"record-payout"`) and can be
overridden by defining `command_name/0` — overrides must stay kebab-case,
underscores raise at construction time. Enrich metadata with the pipe API:

```elixir
MyApp.Commands.RecordPayout.new!(attrs)
|> CommandKit.Command.enacted_by("user-123")
|> CommandKit.Command.put_metadata(:tenant_id, "abc")
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

The bus calls `execute/1` when the handler exports it, otherwise it falls back
to `execute/2` with the runtime context. Metadata is read from the command:

```elixir
def execute(command) do
  command.metadata.enacted_by
  {:ok, %{id: 123}}
end

def execute(command, context), do: {:ok, %{id: 123}}
```

Use `execute/2` only when the handler needs runtime context.

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
