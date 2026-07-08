# Metadata

Command metadata carries caller context — who issued the command, tracing IDs,
timestamps — separately from domain parameters. Unlike domain params, metadata
fields are the same across all commands in an application.

## Defining a metadata module

```elixir
defmodule MyApp.CommandMetadata do
  use CommandKit.Metadata

  field :enacted_by,     :string,   optional: true
  field :correlation_id, :string,   optional: true
  field :causation_id,   :string,   optional: true
  field :message_id,     :string,   optional: true
  field :message_uuid,   :string,   default: Ecto.UUID.generate()
  field :occurred_at,    :datetime, default: DateTime.utc_now()
  field :received_at,    :datetime, default: DateTime.utc_now()
end
```

Field options:

- `:optional` — field is not required (default: `false`)
- `:default` — expression evaluated fresh on each `new/1` call when the field
  is absent; implies `optional: true`

Supported types are the same as command params: `:string`, `:integer`,
`:boolean`, `:decimal`, `:date`, `:datetime`, `:map`, `:list`.

## Attaching metadata to commands

Pass the metadata module once in the command base:

```elixir
defmodule MyApp.Command do
  use CommandKit.Ecto.Command, metadata: MyApp.CommandMetadata
end
```

Every command that uses `MyApp.Command` automatically gets a `metadata` field
typed as `%MyApp.CommandMetadata{}`.

## Building commands with metadata

Pass metadata inline as the `:metadata` key:

```elixir
MyApp.Commands.RecordPayout.new!(%{
  funding_request_id: 42,
  paid_on: ~D[2026-06-17],
  amount: Decimal.new("120.00"),
  metadata: %{enacted_by: "user-123"}
})
```

Or as a second argument:

```elixir
meta = MyApp.CommandMetadata.new!(%{enacted_by: "user-123"})
MyApp.Commands.RecordPayout.new!(params, meta)
```

Fields with `default:` are applied automatically when absent. Unknown fields
return a `%CommandKit.CommandError{}`.

## Accessing metadata in handlers

```elixir
defmodule MyApp.FundingRequests.RecordPayout do
  def execute(%MyApp.Commands.RecordPayout{} = command) do
    command.metadata.enacted_by
    command.metadata.correlation_id
    {:ok, %{payout_id: 123}}
  end
end
```

## Passing arbitrary data

For cases where the set of metadata fields is not known in advance, add an
`:extra` field of type `:map`:

```elixir
defmodule MyApp.CommandMetadata do
  use CommandKit.Metadata

  field :enacted_by, :string,   optional: true
  field :occurred_at, :datetime, default: DateTime.utc_now()
  field :extra,      :map,      optional: true
end
```

Pass any key-value pairs under `:extra`:

```elixir
MyCommand.new!(params,
  enacted_by: "user-1",
  extra: %{"tenant_id" => "abc", "ip_address" => "1.2.3.4"}
)
```

Access in the handler:

```elixir
command.metadata.extra["tenant_id"]
```

## Dispatching

When a command carries metadata, dispatch without a separate metadata argument:

```elixir
MyApp.CommandBus.dispatch(command)
```

The bus reads metadata from `command.metadata` automatically. Passing an
explicit metadata map to `dispatch/2` still works and takes precedence — useful
for legacy handlers that use `execute/2`.
