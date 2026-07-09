defmodule CommandKit.Command do
  @moduledoc """
  Pipe-friendly helpers for enriching commands with metadata.

      RecordPayout.new!(params)
      |> CommandKit.Command.caused_by(event)
      |> CommandKit.Command.enacted_by("user-123")
      |> CommandKit.Command.put_metadata(:tenant_id, "abc")

  Every command carries a `CommandKit.Metadata` struct from construction.
  These helpers update it; they work on any command built through a
  CommandKit command base module.
  """

  alias CommandKit.Metadata

  @doc """
  Marks the command as caused by an external event.

  Accepts the raw decoded CloudEvents map with string keys (`"type"`,
  `"id"`, `"correlation_id"`, `"causation_id"`, `"actor"`, `"time"`).
  Sets `causation_id` to `"type:id"` of the event, inherits the event's
  `correlation_id` (falling back to `"type:id"`) and `actor`, sets
  `occurred_at` to the event's time (UTC), and `received_at` to now. When
  the event carries its own `causation_id`, it is preserved as the
  additional metadata key `:original_causation_id`.
  """
  @spec caused_by(struct(), map()) :: struct()
  def caused_by(%{metadata: %Metadata{} = metadata} = command, %{} = event) do
    %{command | metadata: Metadata.from_cloud_event(metadata, event)}
  end

  @doc """
  Replaces the command's metadata with an already-built `CommandKit.Metadata`.

  Used in event listeners where the metadata is derived from a persisted
  event first:

      DeductVacation.new!(params)
      |> CommandKit.Command.with_metadata(
        CommandKit.Metadata.caused_by_event(
          incoming_metadata,
          "employee-absence-added",
          event_id,
          MyApp.Command
        )
      )
  """
  @spec with_metadata(struct(), Metadata.t()) :: struct()
  def with_metadata(%{metadata: %Metadata{}} = command, %Metadata{} = metadata) do
    %{command | metadata: metadata}
  end

  @doc """
  Sets the acting user or system on the command's metadata.
  """
  @spec enacted_by(struct(), String.t() | nil) :: struct()
  def enacted_by(%{metadata: %Metadata{}} = command, actor) do
    put_metadata(command, :enacted_by, actor)
  end

  @doc """
  Writes one metadata value on the command.

  Fixed metadata fields are validated; any other atom key is stored as
  additional metadata.
  """
  @spec put_metadata(struct(), atom(), term()) :: struct()
  def put_metadata(%{metadata: %Metadata{} = metadata} = command, key, value) do
    %{command | metadata: Metadata.put(metadata, key, value)}
  end

  @doc """
  Writes several metadata values at once from a keyword list or map.

      CommandKit.Command.put_metadata(command, tenant_id: "abc", locale: "de")
  """
  @spec put_metadata(struct(), keyword() | map()) :: struct()
  def put_metadata(%{metadata: %Metadata{}} = command, entries)
      when is_list(entries) or is_map(entries) do
    Enum.reduce(entries, command, fn {key, value}, command ->
      put_metadata(command, key, value)
    end)
  end

  @doc false
  def __attach_identity__(command_module, values) do
    name = validated_command_name!(command_module)
    command_id = Ecto.UUID.generate()
    source = command_module.__command_kit_source__()
    urn = CommandKit.URN.generate(source, name, command_id)

    values
    |> Map.put(:command_id, command_id)
    |> Map.put(:metadata, Metadata.chain_start(urn))
  end

  defp validated_command_name!(command_module) do
    Metadata.ensure_kebab_case!(command_module.command_name(), "command names")
  end
end
