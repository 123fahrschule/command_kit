defmodule CommandKit do
  @moduledoc """
  CommandKit provides typed command definitions, command bus dispatch,
  middleware pipelines, runtime context, and async dispatch adapters.

  A typical application defines a local command base module and a bus:

      defmodule MyApp.Command do
        use CommandKit.Ecto.Command
      end

      defmodule MyApp.CommandBus do
        use CommandKit.Bus, otp_app: :my_app
      end

  Individual commands then use the application base module and can declare
  params and handlers without exposing implementation details such as Ecto
  schemas or changesets.
  """
end
