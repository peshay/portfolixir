defmodule Portfolixir.JournalTest do
  use Portfolixir.DataCase, async: true

  # User story:
  # As an operator who let an agent write financial data,
  # I want every committed security write recorded in the append-only journal,
  # so that any create, edit or deletion is attributable and reversible by
  # inspection (FR-28 / NFR-2, ADR-0017, first slice: Catalog).

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Journal

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(%{name: "Acme Corp", currency_code: "EUR", asset_class: "equity"}, overrides)
  end

  describe "create_security/2" do
    test "records exactly one create entry attributed to the actor" do
      actor = Actor.api_token_rw("token-7")
      {:ok, security} = Catalog.create_security(actor, valid_attrs(%{name: "Created Co"}))

      assert [entry] = Journal.list_entries(resource_type: "security")
      assert entry.operation == :create
      assert entry.actor_type == :api_token_rw
      assert entry.actor_label == "token-7"
      assert entry.resource_type == "security"
      assert entry.resource_id == to_string(security.id)
      assert entry.before == nil
      assert entry.after["name"] == "Created Co"
      assert entry.after["currency_code"] == "EUR"
      assert entry.scenario_id == nil
    end

    test "a rejected changeset commits nothing and journals nothing" do
      actor = Actor.owner_ui()
      assert {:error, %Ecto.Changeset{}} = Catalog.create_security(actor, %{name: ""})
      assert Journal.list_entries(resource_type: "security") == []
    end
  end

  describe "update_security/3" do
    test "records an update entry with before and after snapshots" do
      actor = Actor.owner_ui()
      {:ok, security} = Catalog.create_security(actor, valid_attrs(%{name: "Before Name"}))

      {:ok, _updated} = Catalog.update_security(actor, security, %{name: "After Name"})

      assert [update] = Journal.list_entries(resource_type: "security", operation: :update)
      assert update.actor_type == :owner_ui
      assert update.before["name"] == "Before Name"
      assert update.after["name"] == "After Name"
      assert update.resource_id == to_string(security.id)
    end
  end

  describe "delete_security/2" do
    test "journals the deletion so a removed security stays traceable" do
      actor = Actor.owner_ui()
      {:ok, security} = Catalog.create_security(actor, valid_attrs(%{name: "Doomed Co"}))

      {:ok, _} = Catalog.delete_security(actor, security)

      assert Catalog.get_security(security.id) == nil

      assert [delete] = Journal.list_entries(resource_type: "security", operation: :delete)
      assert delete.before["name"] == "Doomed Co"
      assert delete.resource_id == to_string(security.id)
    end
  end

  test "completeness: every committed security write produces exactly one entry" do
    actor = Actor.owner_ui()
    {:ok, security} = Catalog.create_security(actor, valid_attrs())
    {:ok, _} = Catalog.update_security(actor, security, %{name: "Renamed"})
    {:ok, _} = Catalog.delete_security(actor, security)

    operations =
      [resource_type: "security"]
      |> Journal.list_entries()
      |> Enum.map(& &1.operation)
      |> Enum.sort()

    assert operations == [:create, :delete, :update]
  end

  test "set_asset_class/3 journals one aggregate update entry for the bulk write" do
    actor = Actor.owner_ui()
    {:ok, a} = Catalog.create_security(actor, valid_attrs(%{name: "A", asset_class: nil}))
    {:ok, b} = Catalog.create_security(actor, valid_attrs(%{name: "B", asset_class: nil}))

    before = Journal.list_entries(operation: :update)
    assert Catalog.set_asset_class(actor, [a.id, b.id], "etf") == 2

    after_entries = Journal.list_entries(operation: :update)
    assert length(after_entries) == length(before) + 1

    [bulk | _] = after_entries
    assert bulk.resource_type == "security"
    assert bulk.resource_id == nil
    assert bulk.after["asset_class"] == "etf"
    assert Enum.sort(bulk.after["security_ids"]) == Enum.sort([a.id, b.id])
  end

  test "market-data writes (quotes) are not journaled (allowlist)" do
    actor = Actor.owner_ui()
    {:ok, security} = Catalog.create_security(actor, valid_attrs())
    creates = Journal.list_entries(resource_type: "security")

    {:ok, _count} =
      Quotes.upsert_many(security.id, [%{date: ~D[2026-01-02], close: "12.34", source: "manual"}])

    # No new journal entries appear for the quote write.
    assert Journal.list_entries() == creates
  end

  test "list_entries/1 filters real writes by default and includes scenarios on request" do
    actor = Actor.owner_ui()
    {:ok, _security} = Catalog.create_security(actor, valid_attrs())

    real_only = Journal.list_entries()
    assert Enum.all?(real_only, &is_nil(&1.scenario_id))

    with_scenarios = Journal.list_entries(include_scenarios: true)
    assert length(with_scenarios) >= length(real_only)
  end
end
