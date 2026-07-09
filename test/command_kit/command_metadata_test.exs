defmodule CommandKit.CommandMetadataTest do
  use ExUnit.Case, async: true

  alias CommandKit.Metadata

  defmodule CommandBase do
    use CommandKit.Core.Command, source: "de.123fahrschule:testapp"
  end

  defmodule RecordPayout do
    use CommandBase

    params do
      field :amount, :decimal
    end
  end

  defmodule RenamedCommand do
    use CommandBase

    params do
      field :id, :integer
    end

    def command_name, do: "record-manual-payout"
  end

  defmodule BadlyRenamedCommand do
    use CommandBase

    params do
      field :id, :integer
    end

    def command_name, do: "record_manual_payout"
  end

  # Shaped like absence's test/fixtures/domain-events CloudEvents fixtures.
  @cloud_event %{
    "id" => "05dec22b-0b01-42b3-87fd-334d668c1edc",
    "type" => "de.123fahrschule:absence:employee-absence-added",
    "time" => "2021-02-22T14:49:59+01:00",
    "actor" => "de.123fahrschule:absence",
    "causation_id" => "de.123fahrschule:absence:add-employee-absence:05dec22b",
    "correlation_id" => "de.123fahrschule:absence:add-employee-absence:05dec22b"
  }

  defp new_command, do: RecordPayout.new!(amount: Decimal.new("12.34"))

  describe "command identity" do
    test "command_name is derived from the module in kebab-case" do
      assert RecordPayout.command_name() == "record-payout"
    end

    test "command_name is overridable" do
      assert RenamedCommand.command_name() == "record-manual-payout"
      command = RenamedCommand.new!(id: 1)
      assert command.metadata.causation_id =~ ":record-manual-payout:"
    end

    test "underscored override is rejected at construction time" do
      assert_raise ArgumentError, ~r/"record-manual-payout"/, fn ->
        BadlyRenamedCommand.new!(id: 1)
      end
    end

    test "each construction generates a distinct command_id" do
      first = new_command()
      second = new_command()

      assert is_binary(first.command_id)
      assert first.command_id != second.command_id
    end

    test "missing source on the base module raises with an example" do
      assert_raise ArgumentError, ~r/requires a :source option.*source:/s, fn ->
        defmodule NoSourceBase do
          use CommandKit.Core.Command
        end
      end
    end

    test "blank source on the base module is rejected" do
      assert_raise ArgumentError, ~r/requires a :source option/, fn ->
        defmodule BlankSourceBase do
          use CommandKit.Core.Command, source: "   "
        end
      end
    end

    test "per-command source override is rejected" do
      assert_raise ArgumentError, ~r/cannot be overridden per command/, fn ->
        defmodule OverridingCommand do
          use CommandKit.CommandMetadataTest.CommandBase, source: "de.123fahrschule:other"

          params do
            field :id, :integer
          end
        end
      end
    end
  end

  describe "chain-start metadata" do
    test "new commands are self-caused via their URN" do
      command = new_command()
      urn = "de.123fahrschule:testapp:record-payout:#{command.command_id}"

      assert %Metadata{} = command.metadata
      assert command.metadata.causation_id == urn
      assert command.metadata.correlation_id == urn
      assert command.metadata.enacted_by == nil
      assert command.metadata.occurred_at == command.metadata.received_at
    end
  end

  describe "caused_by/2" do
    test "takes causation and correlation from the CloudEvents map" do
      command = new_command() |> CommandKit.Command.caused_by(@cloud_event)

      assert command.metadata.causation_id ==
               "#{@cloud_event["type"]}:#{@cloud_event["id"]}"

      assert command.metadata.correlation_id == @cloud_event["correlation_id"]
      assert command.metadata.enacted_by == @cloud_event["actor"]
      assert command.metadata.occurred_at == ~U[2021-02-22 13:49:59Z]
      assert DateTime.compare(command.metadata.received_at, command.metadata.occurred_at) == :gt
    end

    test "falls back to type:id when the event has no correlation_id" do
      event = Map.drop(@cloud_event, ["correlation_id", "causation_id"])
      command = new_command() |> CommandKit.Command.caused_by(event)

      assert command.metadata.correlation_id == command.metadata.causation_id
    end

    test "preserves the event's own causation_id as :original_causation_id" do
      command = new_command() |> CommandKit.Command.caused_by(@cloud_event)

      assert command.metadata[:original_causation_id] == @cloud_event["causation_id"]
    end

    test "raises on malformed event time" do
      event = Map.put(@cloud_event, "time", "not-a-time")

      assert_raise ArgumentError, ~r/not a valid ISO 8601/, fn ->
        CommandKit.Command.caused_by(new_command(), event)
      end
    end
  end

  describe "pipe API" do
    test "enacted_by and put_metadata enrich the command" do
      command =
        new_command()
        |> CommandKit.Command.enacted_by("user-123")
        |> CommandKit.Command.put_metadata(:tenant_id, "abc")

      assert command.metadata.enacted_by == "user-123"
      assert Metadata.get(command.metadata, :tenant_id) == "abc"
    end

    test "put_metadata/2 assigns in bulk from keyword or map" do
      from_keyword =
        CommandKit.Command.put_metadata(new_command(), tenant_id: "abc", locale: "de")

      from_map = CommandKit.Command.put_metadata(new_command(), %{enacted_by: "user-1"})

      assert from_keyword.metadata[:tenant_id] == "abc"
      assert from_keyword.metadata[:locale] == "de"
      assert from_map.metadata.enacted_by == "user-1"
    end
  end

  describe "caused_by_event/4 with a command base module as source" do
    test "reads the source from the base module" do
      derived =
        Metadata.caused_by_event(new_command().metadata, "payout-recorded", "ev-1", CommandBase)

      assert derived.causation_id == "de.123fahrschule:testapp:payout-recorded:ev-1"
    end

    test "rejects modules that are no command base" do
      assert_raise ArgumentError, ~r/not a CommandKit command base module/, fn ->
        Metadata.caused_by_event(new_command().metadata, "payout-recorded", "ev-1", Enum)
      end
    end
  end

  describe "with_metadata/2" do
    test "replaces the command's metadata with a derived one" do
      incoming = new_command().metadata |> Metadata.put(:enacted_by, "user-9")
      derived = Metadata.caused_by_event(incoming, "payout-recorded", "ev-1", CommandBase)

      command = new_command() |> CommandKit.Command.with_metadata(derived)

      assert command.metadata.causation_id == "de.123fahrschule:testapp:payout-recorded:ev-1"
      assert command.metadata.enacted_by == "user-9"
    end

    test "rejects plain maps" do
      assert_raise ArgumentError, ~r/expects a %CommandKit.Metadata/, fn ->
        CommandKit.Command.with_metadata(new_command(), %{enacted_by: "user-1"})
      end
    end
  end
end
