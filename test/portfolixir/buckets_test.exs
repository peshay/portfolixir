defmodule Portfolixir.BucketsTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Journal
  alias Portfolixir.Portfolios
  alias Portfolixir.Repo

  setup do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "Main",
        base_currency_code: "EUR"
      })

    {:ok, cash} =
      Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Giro",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(Portfolixir.Actor.owner_ui(), %{
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

    # User story (ADR-0024, epic story 5):
    # As the import applier tagging newly created accounts,
    # I want a find-or-create for a tag-dimension bucket by name,
    # so that an entered tag matching an existing bucket reuses it instead of
    # erroring on the unique name.
    test "ensure_tag_bucket creates a journaled tag bucket and reuses an existing name" do
      assert {:ok, bucket} = Buckets.ensure_tag_bucket(Actor.import_session(), "  PP Import  ")
      assert bucket.name == "PP Import"
      assert bucket.dimension == "tag"

      assert [entry] =
               Journal.list_entries(resource_type: "bucket", resource_id: to_string(bucket.id))

      assert entry.operation == :create
      assert entry.actor_type == :import_session

      # Same (trimmed) name → the existing bucket, regardless of dimension.
      assert {:ok, reused} = Buckets.ensure_tag_bucket(Actor.import_session(), "PP Import")
      assert reused.id == bucket.id
      assert length(Buckets.list_buckets()) == 1
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

    test "an assignment write records exactly one journal entry", %{depot: depot} do
      {:ok, b} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Tag"})
      :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), depot, [b.id])

      assert [_] = Journal.list_entries(resource_type: "depot_bucket_assignment")
    end

    test "duplicate bucket ids are de-duplicated rather than crashing", %{
      depot: depot,
      security: security
    } do
      {:ok, b} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Dup"})

      assert :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), depot, [b.id, b.id])
      assert Buckets.depot_default_bucket_ids(depot.id) == [b.id]

      assert :ok = Buckets.set_position_override(Actor.owner_ui(), depot, security, [b.id, b.id])
      assert Buckets.effective_position_buckets(depot.id, security.id) == [b.id]
    end

    test "position_override raises on a corrupt mixed (nil + bucket) row set", %{
      depot: depot,
      security: security
    } do
      {:ok, b} = Buckets.create_bucket(Actor.owner_ui(), %{name: "X"})

      # position_bucket_overrides is not guard-armed, so a raw insert can bypass
      # the context invariant that keeps explicit-empty and explicit sets apart.
      Repo.insert_all("position_bucket_overrides", [
        %{securities_account_id: depot.id, security_id: security.id, bucket_id: nil},
        %{securities_account_id: depot.id, security_id: security.id, bucket_id: b.id}
      ])

      assert_raise RuntimeError, ~r/mixes the explicit-empty marker/, fn ->
        Buckets.position_override(depot.id, security.id)
      end
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
      assert [_] = Journal.list_entries(resource_type: "cash_account_bucket_assignment")
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

  # User story:
  # As a local portfolio maintainer,
  # I want a per-portfolio scope that says whether a position or cash account is
  # in a chosen view, with no view meaning "everything",
  # so that analytics can restrict to a view over the single-count universe
  # without re-querying per holding (ADR-0018, #444).
  describe "load_scope/2 + membership" do
    test "nil view yields :unscoped and everything is in scope", %{
      depot: depot,
      cash: cash,
      security: security
    } do
      scope = Buckets.load_scope(depot.portfolio_id, nil)
      assert scope == :unscoped
      assert Buckets.position_in_scope?(scope, depot.id, security.id)
      assert Buckets.cash_in_scope?(scope, cash.id)
    end

    test "an include view scopes positions by their effective buckets (override beats depot default)",
         %{
           depot: depot,
           security: security
         } do
      {:ok, core} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Core"})
      {:ok, krypto} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Krypto"})
      {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "CoreView", include_all: false})
      :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, [core.id], [])

      # Depot default = Core -> position inherits and is in scope.
      :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), depot, [core.id])
      scope = Buckets.load_scope(depot.portfolio_id, view.id)
      assert Buckets.position_in_scope?(scope, depot.id, security.id)

      # Override to Krypto -> no longer in the Core view.
      :ok = Buckets.set_position_override(Actor.owner_ui(), depot, security, [krypto.id])
      scope = Buckets.load_scope(depot.portfolio_id, view.id)
      refute Buckets.position_in_scope?(scope, depot.id, security.id)
    end

    test "explicit-empty position is out of a specific include view but in :all", %{
      depot: depot,
      security: security
    } do
      {:ok, core} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Core"})
      :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), depot, [core.id])
      :ok = Buckets.set_position_override(Actor.owner_ui(), depot, security, [])

      {:ok, specific} = Buckets.create_view(Actor.owner_ui(), %{name: "Spec", include_all: false})
      :ok = Buckets.set_view_buckets(Actor.owner_ui(), specific, [core.id], [])

      refute Buckets.position_in_scope?(
               Buckets.load_scope(depot.portfolio_id, specific.id),
               depot.id,
               security.id
             )

      {:ok, everything} = Buckets.create_view(Actor.owner_ui(), %{name: "All", include_all: true})

      assert Buckets.position_in_scope?(
               Buckets.load_scope(depot.portfolio_id, everything.id),
               depot.id,
               security.id
             )
    end

    test "exclude wins and cash respects its bucket", %{
      depot: depot,
      cash: cash,
      security: security
    } do
      {:ok, leo} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Leo"})
      {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "NoLeo", include_all: true})
      :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, [], [leo.id])

      :ok = Buckets.set_position_override(Actor.owner_ui(), depot, security, [leo.id])
      :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), cash, [leo.id])

      scope = Buckets.load_scope(depot.portfolio_id, view.id)
      refute Buckets.position_in_scope?(scope, depot.id, security.id)
      refute Buckets.cash_in_scope?(scope, cash.id)
    end
  end

  # User story:
  # As a local maintainer (or an LLM over MCP),
  # I want assignment/view writes that reference a non-existent bucket to fail
  # cleanly rather than crash, so the API can return a 422 instead of a 500.
  describe "unknown bucket ids are rejected, not raised" do
    @unknown_bucket_id 999_999

    test "set_depot_default_buckets/set_cash_account_buckets/set_position_override reject unknown ids",
         %{depot: depot, cash: cash, security: security} do
      assert {:error, :bucket_ids} =
               Buckets.set_depot_default_buckets(Actor.owner_ui(), depot, [@unknown_bucket_id])

      assert {:error, :bucket_ids} =
               Buckets.set_cash_account_buckets(Actor.owner_ui(), cash, [@unknown_bucket_id])

      assert {:error, :bucket_ids} =
               Buckets.set_position_override(
                 Actor.owner_ui(),
                 depot,
                 security,
                 [@unknown_bucket_id]
               )
    end

    test "set_view_buckets rejects unknown include/exclude ids" do
      {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "V", include_all: false})

      assert {:error, :bucket_ids} =
               Buckets.set_view_buckets(Actor.owner_ui(), view, [@unknown_bucket_id], [])

      assert {:error, :bucket_ids} =
               Buckets.set_view_buckets(Actor.owner_ui(), view, [], [@unknown_bucket_id])
    end
  end

  # User story (ADR-0024 modification 2, epic story 2):
  # As a local portfolio maintainer upgrading to the buckets/views model,
  # I want one designated exclusive "scope" bucket dimension,
  # so that scoped totals keep adding up while free tag buckets stay overlapping.
  #
  # Acceptance criteria:
  # - A bucket carries a dimension: "tag" (default, overlapping) or "scope"
  #   (exclusive); anything else is rejected.
  # - The dimension is fixed at creation — flipping it later could silently
  #   break the at-most-one-scope-bucket invariant on existing assignments.
  # - A depot or cash account carries AT MOST ONE scope bucket; assigning a
  #   second returns a clear context error instead of writing.
  # - Tag buckets stay unrestricted (any number, alongside the scope bucket).
  describe "exclusive scope dimension" do
    test "buckets default to the tag dimension and accept scope at creation" do
      {:ok, tag} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Krypto"})
      assert tag.dimension == "tag"

      {:ok, scope} =
        Buckets.create_bucket(Actor.owner_ui(), %{name: "Main", dimension: "scope"})

      assert scope.dimension == "scope"

      assert {:error, changeset} =
               Buckets.create_bucket(Actor.owner_ui(), %{name: "Bad", dimension: "layer"})

      assert %{dimension: ["is invalid"]} = errors_on(changeset)
    end

    test "the dimension cannot be changed after creation" do
      {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Main"})

      assert {:error, changeset} =
               Buckets.update_bucket(Actor.owner_ui(), bucket, %{dimension: "scope"})

      assert %{dimension: ["cannot be changed after creation"]} = errors_on(changeset)

      # A no-op dimension value alongside a rename still goes through.
      assert {:ok, renamed} =
               Buckets.update_bucket(Actor.owner_ui(), bucket, %{
                 name: "Primary",
                 dimension: "tag"
               })

      assert renamed.name == "Primary"
    end

    test "a depot carries at most one scope bucket; tag buckets stay unrestricted",
         %{depot: depot} do
      {:ok, scope_a} = Buckets.create_bucket(Actor.owner_ui(), %{name: "A", dimension: "scope"})
      {:ok, scope_b} = Buckets.create_bucket(Actor.owner_ui(), %{name: "B", dimension: "scope"})
      {:ok, tag_x} = Buckets.create_bucket(Actor.owner_ui(), %{name: "X"})
      {:ok, tag_y} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Y"})

      assert {:error, :exclusive_bucket_conflict} =
               Buckets.set_depot_default_buckets(Actor.owner_ui(), depot, [
                 scope_a.id,
                 scope_b.id
               ])

      assert Buckets.depot_default_bucket_ids(depot.id) == []

      assert :ok =
               Buckets.set_depot_default_buckets(Actor.owner_ui(), depot, [
                 scope_a.id,
                 tag_x.id,
                 tag_y.id
               ])

      assert Buckets.depot_default_bucket_ids(depot.id) |> Enum.sort() ==
               Enum.sort([scope_a.id, tag_x.id, tag_y.id])
    end

    test "a cash account carries at most one scope bucket", %{cash: cash} do
      {:ok, scope_a} = Buckets.create_bucket(Actor.owner_ui(), %{name: "A", dimension: "scope"})
      {:ok, scope_b} = Buckets.create_bucket(Actor.owner_ui(), %{name: "B", dimension: "scope"})

      assert {:error, :exclusive_bucket_conflict} =
               Buckets.set_cash_account_buckets(Actor.owner_ui(), cash, [scope_a.id, scope_b.id])

      assert Buckets.cash_account_bucket_ids(cash.id) == []

      assert :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), cash, [scope_a.id])
      assert Buckets.cash_account_bucket_ids(cash.id) == [scope_a.id]
    end
  end
end
