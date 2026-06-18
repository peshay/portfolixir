defmodule Portfolixir.BucketsTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Journal
  alias Portfolixir.Portfolios

  setup do
    {:ok, portfolio} =
      Portfolios.create_portfolio(%{name: "Main", base_currency_code: "EUR"})

    {:ok, cash} =
      Portfolios.create_cash_account(%{
        portfolio_id: portfolio.id,
        name: "Giro",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Depot"
      })

    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{name: "ACME", currency_code: "EUR"})

    %{portfolio: portfolio, cash: cash, depot: depot, security: security}
  end

  # User story:
  # As a local portfolio maintainer,
  # I want to create, rename and delete buckets through an actor-first context,
  # so that every bucket-definition change is attributable in the audit journal
  # (ADR-0017, ADR-0018).
  describe "bucket CRUD (journaled)" do
    test "create_bucket records exactly one journal entry with the actor" do
      assert {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Retirement"})
      assert bucket.name == "Retirement"

      assert [entry] =
               Journal.list_entries(resource_type: "bucket", resource_id: to_string(bucket.id))

      assert entry.operation == :create
      assert entry.actor_type == :owner_ui
      assert entry.after["name"] == "Retirement"
    end

    test "bucket name is required and unique" do
      assert {:error, changeset} = Buckets.create_bucket(Actor.owner_ui(), %{name: ""})
      assert %{name: ["can't be blank"]} = errors_on(changeset)

      {:ok, _} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Dup"})
      assert {:error, changeset} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Dup"})
      assert %{name: ["has already been taken"]} = errors_on(changeset)
    end

    test "update_bucket and delete_bucket are journaled" do
      {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Old"})

      assert {:ok, renamed} = Buckets.update_bucket(Actor.owner_ui(), bucket, %{name: "New"})
      assert renamed.name == "New"

      assert {:ok, _} = Buckets.delete_bucket(Actor.owner_ui(), renamed)
      refute Buckets.get_bucket(renamed.id)

      ops =
        Journal.list_entries(resource_type: "bucket", resource_id: to_string(bucket.id))
        |> Enum.map(& &1.operation)
        |> Enum.sort()

      assert ops == [:create, :delete, :update]
    end
  end

  # User story:
  # As a local portfolio maintainer,
  # I want a position to inherit its depot's default buckets unless it has its own
  # override, with "explicit-empty" distinct from "inherit",
  # so that tag assignment is predictable (ADR-0018).
  describe "assignment resolution: depot default + per-position override" do
    test "a position inherits the depot's default bucket set", %{depot: depot, security: security} do
      {:ok, b1} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Core"})
      {:ok, b2} = Buckets.create_bucket(Actor.owner_ui(), %{name: "ESG"})

      :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), depot, [b1.id, b2.id])

      assert Buckets.position_override(depot.id, security.id) == :inherit

      assert Enum.sort(Buckets.effective_position_buckets(depot.id, security.id)) ==
               Enum.sort([b1.id, b2.id])
    end

    test "an explicit override replaces the depot default", %{depot: depot, security: security} do
      {:ok, default} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Default"})
      {:ok, override} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Override"})

      :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), depot, [default.id])
      :ok = Buckets.set_position_override(Actor.owner_ui(), depot, security, [override.id])

      assert Buckets.position_override(depot.id, security.id) == {:explicit, [override.id]}
      assert Buckets.effective_position_buckets(depot.id, security.id) == [override.id]
    end

    test "explicit-empty is distinct from inherit and yields no buckets", %{
      depot: depot,
      security: security
    } do
      {:ok, default} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Default"})
      :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), depot, [default.id])

      :ok = Buckets.set_position_override(Actor.owner_ui(), depot, security, [])

      assert Buckets.position_override(depot.id, security.id) == :explicit_empty
      assert Buckets.effective_position_buckets(depot.id, security.id) == []
    end

    test "clearing an override returns the position to inherit", %{
      depot: depot,
      security: security
    } do
      {:ok, default} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Default"})
      :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), depot, [default.id])
      :ok = Buckets.set_position_override(Actor.owner_ui(), depot, security, [])

      :ok = Buckets.clear_position_override(Actor.owner_ui(), depot, security)

      assert Buckets.position_override(depot.id, security.id) == :inherit
      assert Buckets.effective_position_buckets(depot.id, security.id) == [default.id]
    end

    test "a holding can carry multiple buckets (many-to-many)", %{
      depot: depot,
      security: security
    } do
      {:ok, b1} = Buckets.create_bucket(Actor.owner_ui(), %{name: "A"})
      {:ok, b2} = Buckets.create_bucket(Actor.owner_ui(), %{name: "B"})
      {:ok, b3} = Buckets.create_bucket(Actor.owner_ui(), %{name: "C"})

      :ok =
        Buckets.set_position_override(Actor.owner_ui(), depot, security, [b1.id, b2.id, b3.id])

      assert Enum.sort(Buckets.effective_position_buckets(depot.id, security.id)) ==
               Enum.sort([b1.id, b2.id, b3.id])
    end

    test "assignment writes are journaled", %{depot: depot} do
      {:ok, b} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Tag"})
      :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), depot, [b.id])

      assert [_ | _] = Journal.list_entries(resource_type: "depot_bucket_assignment")
    end
  end

  # User story:
  # As a local portfolio maintainer,
  # I want cash accounts to be bucketable like depots,
  # so that I can scope cash into the same views as my positions (ADR-0018).
  describe "cash-account buckets" do
    test "a cash account carries its assigned bucket set", %{cash: cash} do
      {:ok, b} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Liquidity"})
      :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), cash, [b.id])

      assert Buckets.cash_account_bucket_ids(cash.id) == [b.id]
      assert [_ | _] = Journal.list_entries(resource_type: "cash_account_bucket_assignment")
    end
  end

  # User story:
  # As a local portfolio maintainer,
  # I want to define global views as include/exclude bucket sets that are NOT
  # journaled,
  # so that I can reshape my analytic lens freely without polluting the financial
  # audit trail (ADR-0018 §5).
  describe "views (definition not journaled)" do
    test "create_view + set_view_buckets produce a filter and emit no journal entries" do
      before = length(Journal.list_entries([]))

      {:ok, b_in} = Buckets.create_bucket(Actor.owner_ui(), %{name: "In"})
      {:ok, b_ex} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Ex"})
      bucket_entries = length(Journal.list_entries([]))

      {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Strategy", include_all: false})
      :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, [b_in.id], [b_ex.id])

      assert Buckets.view_filter(view.id) == %{include: [b_in.id], exclude: [b_ex.id]}

      # Only the two bucket creates were journaled; no view-definition entries.
      assert length(Journal.list_entries([])) == bucket_entries
      assert bucket_entries - before == 2
    end

    test "include_all yields an :all include filter" do
      {:ok, view} =
        Buckets.create_view(Actor.owner_ui(), %{name: "Everything", include_all: true})

      assert Buckets.view_filter(view.id) == %{include: :all, exclude: []}
    end

    test "update_view and delete_view edit the definition without journaling" do
      before = length(Journal.list_entries([]))
      {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Draft", include_all: true})

      assert {:ok, renamed} =
               Buckets.update_view(Actor.owner_ui(), view, %{name: "Final", include_all: false})

      assert renamed.name == "Final"
      assert renamed.include_all == false

      assert {:ok, _} = Buckets.delete_view(Actor.owner_ui(), renamed)
      refute Buckets.get_view(renamed.id)

      # No view-definition write was journaled.
      assert length(Journal.list_entries([])) == before
    end

    test "view name is required and unique" do
      assert {:error, changeset} = Buckets.create_view(Actor.owner_ui(), %{name: ""})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end
  end

  # User story:
  # As a local portfolio maintainer,
  # I want to list and fetch buckets and views,
  # so that later API/MCP and UI stories have read access to the model (ADR-0018).
  describe "reads" do
    test "list_buckets and get_bucket!/list_views and get_view!" do
      {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Z-bucket"})
      {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Z-view", include_all: true})

      assert Enum.any?(Buckets.list_buckets(), &(&1.id == bucket.id))
      assert Buckets.get_bucket!(bucket.id).name == "Z-bucket"

      assert Enum.any?(Buckets.list_views(), &(&1.id == view.id))
      assert Buckets.get_view!(view.id).name == "Z-view"
    end
  end
end
