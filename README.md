# CommandKit

CommandKit is a small Elixir library for typed commands, command handlers,
named middleware pipelines, runtime execution context, telemetry, idempotency,
and async dispatch.

It is designed for layered Phoenix applications where application services and
command handlers must be callable from controllers, LiveViews, jobs, CLIs, and
tests with simple adapter-safe values.

## Installation

```elixir
def deps do
  [
    {:command_kit, "~> 0.1.0"}
  ]
end
```

## Quickstart

Define an application command base:

```elixir
defmodule MyApp.Command do
  use CommandKit.Ecto.Command
end
```

Define a command:

```elixir
defmodule MyApp.Commands.RecordPayout do
  use MyApp.Command

  params do
    field :funding_request_id, :integer
    field :paid_on, :date
    field :amount, :decimal
    field :reference, :string, optional: true
  end

  handler MyApp.FundingRequests.RecordPayout
end
```

Define a handler:

```elixir
defmodule MyApp.FundingRequests.RecordPayout do
  def execute(command, metadata) do
    {:ok, %{payout_id: 123}}
  end
end
```

For dynamic handler resolution, omit `handler ...` in the command and implement
`CommandKit.Handler` for the command type. See the
[Commands guide](docs/guides/commands.md#protocol-based-handler-resolution).

Define and configure a bus:

```elixir
defmodule MyApp.CommandBus do
  use CommandKit.Bus, otp_app: :my_app
end

config :my_app, MyApp.CommandBus,
  default_pipeline: :default,
  pipelines: [
    default: [
      CommandKit.Middleware.Telemetry,
      CommandKit.Middleware.Logging,
      CommandKit.Middleware.ErrorHandler,
      CommandKit.Middleware.Authorization,
      CommandKit.Middleware.Idempotency
    ],
    system: [
      CommandKit.Middleware.Telemetry,
      CommandKit.Middleware.ErrorHandler
    ]
  ]
```

Build and dispatch:

```elixir
{:ok, command} =
  MyApp.Commands.RecordPayout.new(%{
    "funding_request_id" => "42",
    "paid_on" => "2026-06-17",
    "amount" => "120.00"
  })

MyApp.CommandBus.dispatch(command, %{enacted_by: "system"})
```

## Guides

- [Commands](docs/guides/commands.md)
- [Context](docs/guides/context.md)
- [Pipelines and Middleware](docs/guides/pipelines-and-middleware.md)
- [Async Dispatch](docs/guides/async.md)
- [Testing](docs/guides/testing.md)
