defmodule Portfolixir.Imports.ReimportSurvivalTest do
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Applier.Result
  alias Portfolixir.Imports.SecurityResolver
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Targets

  @fixtures Path.expand("../../support/fixtures/portfolio_performance", __DIR__)

  defp parse_fixture!(name) do
    {:ok, preview} =
      Imports.parse_portfolio_performance(File.read!(Path.join(@fixtures, name)), filename: name)

    preview
  end

  defp setup_portfolio do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Import target",
        base_currency_code: "EUR"
      })

    portfolio
  end

  defp security!(attrs) do
    {:ok, security} =
      Catalog.create_security(
        Actor.owner_ui(),
        Map.merge(%{name: "Example AG", currency_code: "EUR"}, attrs)
      )

    security
  end

  defp find_security!(fun), do: Enum.find(Catalog.list_securities(), fun) || raise("not found")

  # User story (ADR-0029 §4 — the epic acceptance criterion):
  # As a local portfolio maintainer with accumulated strategy configuration,
  # I want a re-import of a mutated Portfolio Performance export (a renamed
  # ISIN-less security, a changed ISIN routed through a §3 alias, drifted
  # decimal formatting) to leave every piece of strategy configuration
  # intact — same rows, same ids, exact Decimal values,
  # so that my classification trees, plan versions, cash target and position
  # targets never silently stop describing the portfolio I hold.
  #
  # Acceptance criteria:
  # - Custom classification, categories, and stored assignments: unchanged
  #   rows, same ids.
  # - All plan versions (active + draft + archived, ADR-0027) with names,
  #   statuses and per-category weights intact; the cash target intact.
  # - Position targets (ADR-0030) on both mutated securities: same ids,
  #   Decimal.eq? weights.
  # - The renamed ISIN-less security is surfaced (create row + pre-apply
  #   inverse check leftover) and resolves via an explicit override; the
  #   changed ISIN resolves through the recorded former-ISIN alias.
  # - No duplicate securities, no duplicate bookings; only the genuinely new
  #   booking imports, onto the same security id.
  test "golden path: strategy configuration survives a mutated re-import exactly" do
    portfolio = setup_portfolio()

    # --- initial import from the fixture file -----------------------------
    initial = parse_fixture!("golden_path_initial.json")

    assert {:ok, %Result{created_securities: 2, created_transactions: 3}} =
             Imports.apply(initial, %{portfolio_id: portfolio.id})

    btc = find_security!(&(&1.name == "Bitcoin"))
    acme = find_security!(&(&1.isin == "DE000ACME001"))

    # --- attach the strategy configuration --------------------------------
    owner = Actor.owner_ui()

    {:ok, classification} = Classifications.create_classification(owner, %{name: "Strategy"})

    {:ok, crypto_cat} =
      Classifications.create_category(owner, %{
        classification_id: classification.id,
        name: "Crypto"
      })

    {:ok, equity_cat} =
      Classifications.create_category(owner, %{
        classification_id: classification.id,
        name: "Equities"
      })

    {:ok, _} = Classifications.assign_security(owner, btc.id, classification.id, crypto_cat.id)
    {:ok, _} = Classifications.assign_security(owner, acme.id, classification.id, equity_cat.id)

    # Active plan v1 with category weights and position targets (ADR-0030)
    # on BOTH the to-be-renamed ISIN-less security and the to-be-ISIN-changed
    # security.
    {:ok, _targets} =
      Targets.set_targets(owner, portfolio.id, classification.id, [
        %{"category_id" => crypto_cat.id, "target_weight" => "0.30"},
        %{"category_id" => equity_cat.id, "target_weight" => "0.60"},
        %{
          "category_id" => crypto_cat.id,
          "security_id" => btc.id,
          "target_weight" => "0.30"
        },
        %{
          "category_id" => equity_cat.id,
          "security_id" => acme.id,
          "target_weight" => "0.45"
        }
      ])

    [plan_v1] = Targets.list_plans(portfolio.id, classification_id: classification.id)
    {:ok, _} = Targets.rename_plan(owner, plan_v1, "Version 1")

    # Version 2 (duplicate -> activate archives v1), version 3 stays a draft.
    {:ok, plan_v2} = Targets.duplicate_plan(owner, plan_v1, %{name: "Version 2"})
    {:ok, plan_v2} = Targets.activate_plan(owner, plan_v2)
    {:ok, _plan_v3} = Targets.duplicate_plan(owner, plan_v2, %{name: "Version 3 draft"})

    # Per-view cash target on the portfolio-wide cash-only plan (ADR-0020).
    :ok = Targets.set_cash_target(owner, portfolio.id, Decimal.new("0.10"))

    snapshot_plans = plan_snapshot(portfolio.id)
    snapshot_targets = target_snapshot(portfolio.id)
    snapshot_assignments = assignment_snapshot([btc.id, acme.id], classification.id)

    assert length(snapshot_plans) == 4
    assert Enum.count(snapshot_targets, & &1.security_id) == 6

    # --- the §3 ISIN change is recorded BEFORE the re-import ---------------
    {:ok, %{security: acme}} = Catalog.record_isin_change(owner, acme, "DE000ACME119")

    # --- preview of the mutated export surfaces the rename -----------------
    mutated = parse_fixture!("golden_path_mutated.json")

    %{resolutions: resolutions, unmatched_config: unmatched} =
      Imports.resolve_securities(mutated)

    acme_res = Enum.find(resolutions, &(&1.ref.isin == "DE000ACME001"))
    assert acme_res.status == :matched
    assert acme_res.matched == %{security_id: acme.id, tier: :former_isin}

    btc_res = Enum.find(resolutions, &(&1.ref.name == "BTC (Cold Wallet)"))
    assert btc_res.status == :create

    # Pre-apply inverse check: the renamed, config-bearing Bitcoin matches
    # zero entries and is surfaced as a leftover, never dropped (FR-7).
    assert Enum.map(unmatched, & &1.security.id) == [btc.id]

    # --- apply with the explicit override for the renamed security ---------
    approved = %{acme_res.key => {:matched, acme.id}}

    assert {:ok, %Result{} = result} =
             Imports.apply(mutated, %{
               portfolio_id: portfolio.id,
               security_mappings: %{btc_res.key => {:existing, btc.id}},
               approved_resolutions: approved
             })

    # Drifted formatting + identity changes: everything dedups except the one
    # genuinely new booking; the old-ISIN rows are labeled alias matches.
    assert result.created_securities == 0
    assert result.created_transactions == 1
    assert result.skipped_duplicates == 3
    assert result.unresolved_entries == []
    assert Enum.all?(result.alias_matches, &(&1.former_isin == "DE000ACME001"))
    assert [%{security_id: override_id, recorded_isin_change: false}] = result.security_overrides
    assert override_id == btc.id

    # The new booking lands on the SAME security row via the alias.
    new_booking =
      Ledger.list_transactions() |> Enum.find(&(&1.date == ~D[2025-01-10]))

    assert new_booking.security_id == acme.id
    assert Catalog.count_securities() == 2

    # --- the survival contract, exactly ------------------------------------
    assert plan_snapshot(portfolio.id) == snapshot_plans
    assert target_snapshot(portfolio.id) == snapshot_targets
    assert assignment_snapshot([btc.id, acme.id], classification.id) == snapshot_assignments

    # Cash target still exact.
    assert Decimal.equal?(Targets.get_cash_target(portfolio.id), Decimal.new("0.10"))

    # Security ids and the recorded identity survive.
    assert Catalog.get_security!(btc.id).name == "Bitcoin"
    assert Catalog.get_security!(acme.id).isin == "DE000ACME119"
    assert [%{former_isin: "DE000ACME001"}] = Catalog.list_identifier_aliases(acme)
  end

  # Plan versions with name/status/cash weight, Decimal serialized exactly so
  # comparison is Decimal-exact and id-exact at once.
  defp plan_snapshot(portfolio_id) do
    portfolio_id
    |> Targets.list_plans()
    |> Enum.map(fn plan ->
      %{
        id: plan.id,
        classification_id: plan.classification_id,
        name: plan.name,
        status: plan.status,
        cash_target_weight: decimal_str(plan.cash_target_weight)
      }
    end)
    |> Enum.sort_by(& &1.id)
  end

  defp target_snapshot(portfolio_id) do
    for plan <- Targets.list_plans(portfolio_id),
        target <-
          Targets.list_targets(portfolio_id, plan: plan) ++
            Targets.list_position_targets(portfolio_id, plan: plan) do
      %{
        id: target.id,
        plan_id: target.plan_id,
        category_id: target.category_id,
        security_id: target.security_id,
        target_weight: decimal_str(target.target_weight)
      }
    end
    |> Enum.sort_by(& &1.id)
  end

  defp assignment_snapshot(security_ids, classification_id) do
    for security_id <- security_ids do
      assignment = Classifications.get_assignment(security_id, classification_id)
      %{id: assignment.id, security_id: security_id, category_id: assignment.category_id}
    end
  end

  defp decimal_str(nil), do: nil
  defp decimal_str(%Decimal{} = value), do: Decimal.to_string(value, :normal)

  # User story (ADR-0029 §4 companion fixtures):
  # As a local portfolio maintainer,
  # I want ambiguous identities in an export — two existing securities
  # sharing a WKN, or sharing (name, currency) — surfaced as decisions,
  # so that the import neither matches nor creates silently.
  #
  # Acceptance criteria:
  # - Both fixture imports report the entry unresolved.
  # - No security is created, no transaction booked, no silent pick.
  describe "companion fixtures: shared identifiers surface decisions" do
    test "two securities sharing a WKN" do
      portfolio = setup_portfolio()
      _a = security!(%{name: "Share Class A", wkn: "AMB001"})
      _b = security!(%{name: "Share Class B", wkn: "AMB001"})

      preview = parse_fixture!("ambiguous_wkn.json")

      assert {:ok, %Result{} = result} = Imports.apply(preview, %{portfolio_id: portfolio.id})

      assert [%{reason: reason}] = result.unresolved_entries
      assert reason =~ "ambiguous"
      assert result.created_securities == 0
      assert result.created_transactions == 0
      assert Catalog.count_securities() == 2
    end

    test "two securities sharing (name, currency)" do
      portfolio = setup_portfolio()
      _a = security!(%{name: "Duplicate Name AG", isin: "DE000DUPA001"})
      _b = security!(%{name: "Duplicate Name AG", isin: "DE000DUPB001"})

      preview = parse_fixture!("ambiguous_name_currency.json")

      assert {:ok, %Result{} = result} = Imports.apply(preview, %{portfolio_id: portfolio.id})

      assert [%{reason: reason}] = result.unresolved_entries
      assert reason =~ "ambiguous"
      assert result.created_securities == 0
      assert result.created_transactions == 0
    end
  end

  # User story (ADR-0029 §3/§4 wrong-ordering variant):
  # As a local portfolio maintainer who imports an export already carrying a
  # security's NEW identity before recording the §3 ISIN change,
  # I want the stronger-identifier veto and the pre-apply inverse check to
  # surface the conflict,
  # so that no silent merge and no silent duplicate happens in the window.
  #
  # Acceptance criteria:
  # - The entry is surfaced (veto conflict), not matched, not created.
  # - The preview's inverse check lists the config-bearing existing security.
  test "wrong ordering: a new identity before the alias is recorded is surfaced" do
    portfolio = setup_portfolio()

    initial = parse_fixture!("golden_path_initial.json")
    {:ok, _} = Imports.apply(initial, %{portfolio_id: portfolio.id})

    acme = find_security!(&(&1.isin == "DE000ACME001"))

    owner = Actor.owner_ui()
    {:ok, classification} = Classifications.create_classification(owner, %{name: "Strategy"})

    {:ok, category} =
      Classifications.create_category(owner, %{classification_id: classification.id, name: "Eq"})

    {:ok, _} = Classifications.assign_security(owner, acme.id, classification.id, category.id)

    preview = parse_fixture!("wrong_ordering_new_identity.json")

    %{resolutions: resolutions, unmatched_config: unmatched} =
      Imports.resolve_securities(preview)

    assert [%{status: :needs_decision, conflict: %{type: :identifier_veto}}] = resolutions
    # The veto candidate IS the config-bearing security — it is in front of
    # the user via the decision row, so the inverse check has nothing extra.
    assert unmatched == []

    assert {:ok, %Result{} = result} = Imports.apply(preview, %{portfolio_id: portfolio.id})

    assert [%{reason: reason}] = result.unresolved_entries
    assert reason =~ "stronger identifier"
    assert result.created_securities == 0
    assert result.created_transactions == 0
    assert Catalog.get_security!(acme.id).isin == "DE000ACME001"
  end

  # User story (ADR-0029 §2/§4 preview→apply divergence):
  # As a local portfolio maintainer whose preview went stale,
  # I want apply to abort back to the preview when a fixture entry's
  # resolution differs from what was approved,
  # so that stale consent never books onto the wrong security.
  #
  # Acceptance criteria:
  # - The apply aborts with {:error, {:resolution_diverged, key}}.
  # - Nothing is committed.
  test "preview→apply divergence aborts the whole import" do
    portfolio = setup_portfolio()

    initial = parse_fixture!("golden_path_initial.json")
    {:ok, _} = Imports.apply(initial, %{portfolio_id: portfolio.id})

    acme = find_security!(&(&1.isin == "DE000ACME001"))
    transactions_before = Ledger.count_transactions()

    mutated = parse_fixture!("golden_path_mutated.json")
    %{resolutions: resolutions} = Imports.resolve_securities(mutated)

    acme_res = Enum.find(resolutions, &(&1.ref.isin == "DE000ACME001"))
    btc_res = Enum.find(resolutions, &(&1.ref.name == "BTC (Cold Wallet)"))
    assert acme_res.status == :matched

    # Between preview and apply the owner records the ISIN change — the
    # entry's resolution flips from the current-ISIN tier match onto the
    # alias tier... which still selects the same id, so to force a real
    # divergence the security instead disappears behind a NEW identity: the
    # ISIN is edited away and a different security takes it over.
    {:ok, _} = Catalog.update_security(Actor.owner_ui(), acme, %{isin: "DE000GONE001"})
    _impostor = security!(%{name: "Impostor AG", isin: "DE000ACME001"})

    assert {:error, {:resolution_diverged, _key}} =
             Imports.apply(mutated, %{
               portfolio_id: portfolio.id,
               security_mappings: %{btc_res.key => :create},
               approved_resolutions: %{acme_res.key => {:matched, acme.id}}
             })

    assert Ledger.count_transactions() == transactions_before
  end

  # Nail down that SecurityResolver keys stay derivable from parsed entries —
  # the LiveView and any future API client depend on this equivalence.
  test "resolution keys equal the keys derived from parsed entries" do
    preview = parse_fixture!("golden_path_initial.json")
    %{resolutions: resolutions} = Imports.resolve_securities(preview)

    entry_keys =
      preview.entries
      |> Enum.filter(& &1.security)
      |> Enum.map(&SecurityResolver.key(SecurityResolver.effective_ref(&1)))
      |> Enum.uniq()
      |> Enum.sort()

    assert Enum.sort(Enum.map(resolutions, & &1.key)) == entry_keys
  end
end
