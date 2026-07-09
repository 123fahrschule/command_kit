# Metadata

Every command carries a `%CommandKit.Metadata{}` from construction — it is
never `nil` and stays attached to the command instead of being threaded
through dispatch APIs as a separate argument. Metadata answers three
questions about a command: what caused it, who acted, and when.

## The five fields

| Field            | Meaning                                                        |
| ---------------- | -------------------------------------------------------------- |
| `causation_id`   | Identity of the message that caused this command               |
| `correlation_id` | Identity of the message that started the whole chain           |
| `enacted_by`     | The acting user or system (string or `nil`)                    |
| `occurred_at`    | When the triggering fact occurred (UTC)                        |
| `received_at`    | When the trigger reached this service (UTC)                    |

These fields are fixed and owned by the library. They cannot be removed and
their types are validated.

## Command identity and the chain start

Commands are not persisted, so each command generates its identity inline:
a `command_id` (UUID, generated in `new/1`) and a kebab-case `command_name/0`
derived from the module (`RecordPayout` → `"record-payout"`, overridable via
a plain function definition — names must stay kebab-case). Together with the
`source:` prefix configured on the command base module they form the
command's URN:

```elixir
defmodule MyApp.Command do
  use CommandKit.Ecto.Command, source: "de.123fahrschule:my_app"
end

command = MyApp.Commands.RecordPayout.new!(params)
command.metadata.causation_id
#=> "de.123fahrschule:my_app:record-payout:<command_id>"
```

A freshly built command starts its own chain: `causation_id` and
`correlation_id` both equal the command's URN, and `occurred_at` equals
`received_at`.

## Commands caused by events

When a command is triggered by a consumed event, pipe it through
`CommandKit.Command.caused_by/2` with the raw decoded CloudEvents map:

```elixir
MyApp.Commands.AddEmployeeAbsence.new!(params)
|> CommandKit.Command.caused_by(event)
```

This sets `causation_id` to the event's `"type:id"`, inherits the event's
`correlation_id` and `actor`, takes `occurred_at` from the event's time, and
sets `received_at` to now. If the event carries its own `causation_id`, it is
preserved as the additional key `:original_causation_id`.

The command itself never appears mid-chain as a `causation_id` — commands are
not persisted, so such a link could not be looked up. Only a chain-start
command contributes its own URN.

## Enriching commands

Use the pipe-friendly functions in `CommandKit.Command`:

```elixir
MyApp.Commands.RecordPayout.new!(params)
|> CommandKit.Command.enacted_by("user-123")
|> CommandKit.Command.put_metadata(:tenant_id, "abc")
|> CommandKit.Command.put_metadata(idempotency_key: key, locale: "de")
```

## Additional metadata

Beyond the five fixed fields, metadata accepts arbitrary additional atom
keys. Read and write them through the accessor API — fixed and additional
keys work uniformly:

```elixir
meta = CommandKit.Metadata.put(command.metadata, :tenant_id, "abc")
CommandKit.Metadata.get(meta, :tenant_id) #=> "abc"
meta[:tenant_id]                          #=> "abc"
meta[:enacted_by]                         #=> "user-123"
```

Additional keys must be atoms. Fixed fields cannot be removed
(`pop_in(meta[:causation_id])` raises); additional keys can.

## Persisting metadata with events

Events inherit the command's metadata verbatim. Metadata is the
append/envelope context of a persisted event — not part of the domain event
itself — so it is handed to the append function as-is:

```elixir
def execute(%AddEmployeeAbsence{} = command) do
  metadata = command.metadata
  event = EmployeeAbsenceAddedEvent.for(...)
  append_event(event, metadata)
end
```

This works because `%CommandKit.Metadata{}` implements `Enumerable` over its
flat persistence view: event stores that normalize metadata with
`Enum.into(metadata, %{})` receive exactly the map that `to_map/1` returns —
the five fixed fields plus all additional pairs, no container key.

For event stores that expect a plain map instead of an enumerable, flatten
explicitly:

```elixir
append_event(event, CommandKit.Metadata.to_map(command.metadata))
```

Both forms are equivalent by construction.

## Event listeners: event → event correlation

When an event listener reacts to a persisted event by appending new events —
no command involved — derive the new metadata with
`CommandKit.Metadata.caused_by_event/4`. The receiver is `Metadata` because
that is what comes back: metadata caused by the given event.

The last argument supplies the URN source. Pass your command base module —
it already carries the `source:` configuration, so the prefix stays defined
in exactly one place:

```elixir
alias CommandKit.Metadata

derived =
  Metadata.caused_by_event(
    incoming_metadata,          # %CommandKit.Metadata{} or a plain map from the event store
    "employee-absence-added",   # kebab-case name of the triggering event
    event.id,                   # its id
    MyApp.Command               # base module with source: — or the source string itself
  )

append_event(follow_up_event, derived)
```

The new `causation_id` is the URN of the triggering event
(`"<source>:<event-name>:<event-id>"`); `correlation_id` and `enacted_by`
are inherited. `occurred_at` and `received_at` are set to now: the follow-up
event is a new fact, and the triggering event's own time stays reachable
through the causation chain.

When the listener dispatches a command instead of appending events directly,
attach the derived metadata with `with_metadata/2`:

```elixir
DeductVacation.new!(params)
|> CommandKit.Command.with_metadata(
  Metadata.caused_by_event(incoming_metadata, "employee-absence-added", event.id, MyApp.Command)
)
|> MyApp.CommandBus.dispatch()
```

See the [Migration guide](migration.md) for complete before/after examples.

## Metadata in the pipeline

The command is the single source of truth. Middleware reads metadata with
`CommandKit.Pipeline.metadata(pipeline)` and changes it with
`CommandKit.Pipeline.put_metadata/3`, which updates the command in the
pipeline — handlers always observe middleware changes:

```elixir
def call(pipeline, next, _opts) do
  pipeline
  |> CommandKit.Pipeline.put_metadata(:request_id, Logger.metadata()[:request_id])
  |> next.()
end
```

Async dispatch serializes identity and metadata with the command and
restores them verbatim — `command_id`, causation, correlation, and both
timestamps survive the queue unchanged.
