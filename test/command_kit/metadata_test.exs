defmodule CommandKit.MetadataTest do
  use ExUnit.Case, async: true

  alias CommandKit.Metadata

  defp meta(overrides \\ []) do
    base = Metadata.chain_start("de.123fahrschule:test:record-payout:uuid-1")
    Enum.reduce(overrides, base, fn {key, value}, meta -> Metadata.put(meta, key, value) end)
  end

  describe "fixed fields" do
    test "chain start sets causation and correlation to the URN and both timestamps to now" do
      meta = meta()

      assert meta.causation_id == "de.123fahrschule:test:record-payout:uuid-1"
      assert meta.correlation_id == meta.causation_id
      assert meta.enacted_by == nil
      assert %DateTime{} = meta.occurred_at
      assert meta.occurred_at == meta.received_at
    end

    test "get and put route fixed keys to struct fields" do
      meta = Metadata.put(meta(), :enacted_by, "user-1")

      assert meta.enacted_by == "user-1"
      assert Metadata.get(meta, :enacted_by) == "user-1"
      refute Map.has_key?(Metadata.to_map(meta), :__extra__)
    end

    test "enacted_by must be a string or nil" do
      assert_raise ArgumentError, ~r/enacted_by must be a string or nil/, fn ->
        Metadata.put(meta(), :enacted_by, 123)
      end
    end

    test "timestamps must be DateTime" do
      assert_raise ArgumentError, ~r/occurred_at must be a DateTime/, fn ->
        Metadata.put(meta(), :occurred_at, ~D[2026-07-08])
      end
    end

    test "causation and correlation ids must be strings or nil" do
      assert_raise ArgumentError, ~r/correlation_id must be a string or nil/, fn ->
        Metadata.put(meta(), :correlation_id, 123)
      end

      assert_raise ArgumentError, ~r/causation_id must be a string or nil/, fn ->
        Metadata.put(meta(), :causation_id, :urn)
      end

      assert Metadata.put(meta(), :causation_id, "urn").causation_id == "urn"
    end
  end

  describe "additional metadata" do
    test "put and get work without any container concept" do
      meta = Metadata.put(meta(), :tenant_id, "abc")

      assert Metadata.get(meta, :tenant_id) == "abc"
      assert meta[:tenant_id] == "abc"
      assert Metadata.get(meta, :missing) == nil
    end

    test "string keys are rejected" do
      assert_raise ArgumentError, ~r/metadata keys must be atoms/, fn ->
        Metadata.put(meta(), "tenant_id", "abc")
      end

      assert_raise ArgumentError, ~r/metadata keys must be atoms/, fn ->
        Metadata.get(meta(), "tenant_id")
      end
    end

    test "additional keys cannot shadow fixed fields" do
      meta =
        meta()
        |> Metadata.put(:tenant_id, "abc")
        |> Metadata.put(:enacted_by, "user-1")

      map = Metadata.to_map(meta)

      # the fixed field wins its key; the additional pair stays separate
      assert map.enacted_by == "user-1"
      assert map.tenant_id == "abc"
      assert map_size(map) == 6
      assert meta.enacted_by == "user-1"
    end
  end

  describe "Access behaviour" do
    test "reads fixed and additional keys" do
      meta = meta(tenant_id: "abc")

      assert meta[:causation_id] == meta.causation_id
      assert meta[:tenant_id] == "abc"
      assert meta[:missing] == nil
    end

    test "get_and_update writes through put" do
      {previous, meta} =
        Access.get_and_update(meta(), :tenant_id, fn current -> {current, "abc"} end)

      assert previous == nil
      assert meta[:tenant_id] == "abc"
    end

    test "get_and_update rejects non-atom keys" do
      assert_raise ArgumentError, ~r/metadata keys must be atoms/, fn ->
        Access.get_and_update(meta(), "tenant_id", fn value -> {value, "x"} end)
      end
    end

    test "popping an additional key works" do
      meta = meta(tenant_id: "abc")
      {value, meta} = Access.pop(meta, :tenant_id)

      assert value == "abc"
      assert meta[:tenant_id] == nil
    end

    test "popping a fixed field raises" do
      assert_raise ArgumentError, ~r/cannot remove fixed metadata field/, fn ->
        Access.pop(meta(), :causation_id)
      end

      assert_raise ArgumentError, ~r/cannot remove fixed metadata field/, fn ->
        pop_in(meta()[:enacted_by])
      end
    end
  end

  describe "to_map/1" do
    test "returns one flat map of fixed fields and additional pairs" do
      map = meta(tenant_id: "abc", locale: "de") |> Metadata.to_map()

      assert map.tenant_id == "abc"
      assert map.locale == "de"
      assert map.causation_id == "de.123fahrschule:test:record-payout:uuid-1"
      refute Map.has_key?(map, :__extra__)
    end
  end

  describe "Enumerable" do
    test "Enum.into/2 yields exactly the flat persistence view" do
      meta = meta(tenant_id: "abc", locale: "de")

      assert Enum.into(meta, %{}) == Metadata.to_map(meta)
    end

    test "an event store collecting metadata via Enum.into accepts the struct directly" do
      # mirrors Shared.EventStore, which normalizes metadata with Enum.into(metadata, %{})
      append_event = fn _event, metadata -> Enum.into(metadata, %{}) end

      meta = meta(tenant_id: "abc")
      persisted = append_event.(:event, meta)

      assert persisted.causation_id == meta.causation_id
      assert persisted.tenant_id == "abc"
      refute Map.has_key?(persisted, :__extra__)
    end

    test "count and membership follow the flat view" do
      meta = meta(tenant_id: "abc")

      assert Enum.count(meta) == 6
      assert {:tenant_id, "abc"} in meta
      assert Enum.sort(meta) == Enum.sort(Metadata.to_map(meta))
    end
  end

  describe "inspect" do
    test "renders one flat view without the container name" do
      output = inspect(meta(tenant_id: "abc"))

      assert output =~ "#CommandKit.Metadata<"
      assert output =~ "tenant_id"
      assert output =~ "causation_id"
      refute output =~ "__extra__"
    end
  end

  describe "caused_by_event/4" do
    test "derives follow-up event metadata from a metadata struct" do
      incoming =
        meta()
        |> Metadata.put(:enacted_by, "user-1")

      derived =
        Metadata.caused_by_event(
          incoming,
          "employee-absence-added",
          "event-uuid",
          "de.123fahrschule:absence"
        )

      assert derived.causation_id ==
               "de.123fahrschule:absence:employee-absence-added:event-uuid"

      assert derived.correlation_id == incoming.correlation_id
      assert derived.enacted_by == "user-1"
    end

    test "derives from a plain metadata map as read back from an event store" do
      incoming = %{correlation_id: "chain-root", enacted_by: "user-2", occurred_at: :ignored}

      derived =
        Metadata.caused_by_event(incoming, "holiday-changed", 42, "de.123fahrschule:absence")

      assert derived.causation_id == "de.123fahrschule:absence:holiday-changed:42"
      assert derived.correlation_id == "chain-root"
      assert derived.enacted_by == "user-2"
    end

    test "sets fresh timestamps instead of inheriting the triggering event's time" do
      incoming = meta()
      derived = Metadata.caused_by_event(incoming, "x-y", "id", "src")

      assert %DateTime{} = derived.occurred_at
      assert derived.occurred_at == derived.received_at
      assert DateTime.compare(derived.occurred_at, incoming.occurred_at) in [:gt, :eq]
    end

    test "rejects underscored event names with a kebab-case suggestion" do
      assert_raise ArgumentError, ~r/"employee-absence-added"/, fn ->
        Metadata.caused_by_event(meta(), "employee_absence_added", "id", "src")
      end
    end
  end

  describe "CommandKit.URN" do
    test "generates source:name:id" do
      assert CommandKit.URN.generate("de.123fahrschule:absence", "record-payout", "abc") ==
               "de.123fahrschule:absence:record-payout:abc"

      assert CommandKit.URN.generate("src", "name", 42) == "src:name:42"
    end
  end
end
