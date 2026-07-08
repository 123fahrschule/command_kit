defmodule CommandKit.CommandDefinitionTest do
  use ExUnit.Case, async: true

  defmodule CoreCommand do
    use CommandKit.Core.Command, source: "de.123fahrschule:testapp"
  end

  defmodule EctoCommand do
    use CommandKit.Ecto.Command, source: "de.123fahrschule:testapp"
  end

  defmodule Handler do
    def execute(_command), do: :ok
  end

  defmodule RecordPayoutCore do
    use CoreCommand

    params do
      field :funding_request_id, :integer
      field :paid_on, :date
      field :paid_amount, :decimal
      field :paid_reference, :string, optional: true
      field :tags, :list, optional: true
    end

    handler(CommandKit.CommandDefinitionTest.Handler)
  end

  defmodule RecordPayoutEcto do
    use EctoCommand

    params do
      field :funding_request_id, :integer
      field :paid_on, :date
      field :paid_at, :datetime
      field :paid_amount, :decimal
      field :paid_reference, :string, optional: true
      field :details, :map, optional: true
    end

    handler(CommandKit.CommandDefinitionTest.Handler)
  end

  test "core commands build from already typed values" do
    assert {:ok, command} =
             RecordPayoutCore.new(%{
               "funding_request_id" => 12,
               "paid_on" => ~D[2026-06-17],
               "paid_amount" => Decimal.new("42.50"),
               "tags" => ["paid", 123]
             })

    assert command.funding_request_id == 12
    assert command.paid_on == ~D[2026-06-17]
    assert command.paid_amount == Decimal.new("42.50")
    assert command.paid_reference == nil
    assert command.tags == ["paid", 123]
  end

  test "core commands return structured construction errors" do
    assert {:error, %CommandKit.CommandError{command: RecordPayoutCore, errors: errors}} =
             RecordPayoutCore.new(%{
               funding_request_id: nil,
               paid_on: "2026-06-17",
               paid_amount: Decimal.new("1")
             })

    assert Enum.any?(
             errors,
             &match?(
               %CommandKit.ParamError{
                 path: [:funding_request_id],
                 code: :required,
                 expected: :integer
               },
               &1
             )
           )

    assert Enum.any?(
             errors,
             &match?(
               %CommandKit.ParamError{path: [:paid_on], code: :invalid_type, expected: :date},
               &1
             )
           )
  end

  test "new! raises the structured command error" do
    assert_raise CommandKit.CommandError, ~r/invalid/, fn ->
      RecordPayoutCore.new!(paid_on: ~D[2026-06-17], paid_amount: Decimal.new("1"))
    end
  end

  test "command introspection includes optional metadata and handler" do
    assert [
             %{name: :funding_request_id, type: :integer, required?: true, optional?: false},
             %{name: :paid_on, type: :date, required?: true, optional?: false},
             %{name: :paid_amount, type: :decimal, required?: true, optional?: false},
             %{name: :paid_reference, type: :string, required?: false, optional?: true},
             %{name: :tags, type: :list, required?: false, optional?: true}
           ] = RecordPayoutCore.__command_kit_params__()

    assert RecordPayoutCore.__command_kit_handler__() == Handler
  end

  test "ecto commands cast string params without exposing changesets" do
    assert {:ok, command} =
             RecordPayoutEcto.new(%{
               "funding_request_id" => "12",
               "paid_on" => "2026-06-17",
               "paid_at" => "2026-06-17T10:15:00Z",
               "paid_amount" => "42.50",
               "details" => %{"source" => "test"}
             })

    assert command.funding_request_id == 12
    assert command.paid_on == ~D[2026-06-17]
    assert command.paid_at == ~U[2026-06-17 10:15:00Z]
    assert command.paid_amount == Decimal.new("42.50")
    assert command.paid_reference == nil
    assert command.details == %{"source" => "test"}
  end

  test "ecto commands return command errors for invalid casts" do
    assert {:error, %CommandKit.CommandError{errors: errors}} =
             RecordPayoutEcto.new(%{
               funding_request_id: "not-int",
               paid_on: "no-date",
               paid_at: "no-datetime",
               paid_amount: "no-decimal"
             })

    assert Enum.all?(errors, &match?(%CommandKit.ParamError{code: :invalid_type}, &1))
    refute match?(%Ecto.Changeset{}, errors)
  end

  test "unsupported custom parameter types are rejected at definition time" do
    assert_raise ArgumentError, ~r/unsupported command parameter type/, fn ->
      defmodule UnsupportedCommand do
        use CoreCommand

        params do
          field :custom, :custom
        end
      end
    end
  end

  test "reserved field names are rejected at definition time" do
    assert_raise ArgumentError, ~r/:metadata is a reserved command field name/, fn ->
      defmodule ReservedMetadataCommand do
        use CoreCommand

        params do
          field :metadata, :map
        end
      end
    end

    assert_raise ArgumentError, ~r/:command_id is a reserved command field name/, fn ->
      defmodule ReservedIdCommand do
        use CoreCommand

        params do
          field :command_id, :string
        end
      end
    end
  end
end
