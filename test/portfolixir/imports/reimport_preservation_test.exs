defmodule Portfolixir.Imports.ReimportPreservationTest do
  # Issue #664 (Sprint 6, risk-tier attention): the bounded verification that a
  # Portfolio Performance re-import preserves operator-maintained data. Story
  # 18.2 shipped the golden-path guarantee for classification/targets against a
  # MUTATED export (reimport_survival_test.exs); the owner's report claims a
  # fresh re-import destroys classification, target weights and the cash
  # target, and that `note` / `attributes` survival is untested. These tests
  # answer the claim on synthetic fixtures and stay as the permanent
  # regression guard ADR-0029 should have had.
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Applier.Result
  alias Portfolixir.Knowledge
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

  defp find_security!(fun), do: Enum.find(Catalog.list_securities(), fun) || raise("not found")

  # User story (issue #664, ADR-0029 §4 — an import never destroys
  # operator-maintained data):
  # As a local portfolio maintainer who re-applies the SAME Portfolio
  # Performance export a second time (the workflow the owner's agent reported
  # as destructive),
  # I want the re-import to be a content-hash no-op that leaves my custom
  # classification, all target weights, the cash target, and every security's
  # note and attributes exactly as they were,
  # so that refreshing my bookkeeping history can never silently delete
  # strategy configuration.
  #
  # Acceptance criteria:
  # - The second apply creates no securities and no transactions; every entry
  #   is a skipped duplicate.
  # - Classification assignments: same rows, same ids.
  # - All plan versions and their category/position target weights: same ids,
  #   exact Decimal values; the cash target Decimal-exact.
  # - `note` and `attributes` on both imported securities: byte-for-byte
  #   identical, including operator-added custom attribute keys.
  # - Security ids and `updated_at` unchanged (no silent rewrite).
  # - The research log (ADR-0044, #748): every entry appended before the
  #   re-import is still there, unchanged, in the same order — the guarantee
  #   #741 documents, pinned for the new table.
  test "re-importing the identical export preserves classification, targets, cash target, notes and attributes" do
    portfolio = setup_portfolio()
    owner = Actor.owner_ui()

    initial = parse_fixture!("golden_path_initial.json")

    assert {:ok, %Result{created_securities: 2, created_transactions: 3}} =
             Imports.apply(initial, %{portfolio_id: portfolio.id})

    btc = find_security!(&(&1.name == "Bitcoin"))
    acme = find_security!(&(&1.isin == "DE000ACME001"))

    # --- operator-maintained configuration -------------------------------
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

    {:ok, _targets} =
      Targets.set_targets(owner, portfolio.id, classification.id, [
        %{"category_id" => crypto_cat.id, "target_weight" => "0.25"},
        %{"category_id" => equity_cat.id, "target_weight" => "0.65"},
        %{
          "category_id" => equity_cat.id,
          "security_id" => acme.id,
          "target_weight" => "0.40"
        }
      ])

    :ok = Targets.set_cash_target(owner, portfolio.id, Decimal.new("0.10"))

    # Notes and attributes — including a custom operator key the import
    # pipeline knows nothing about.
    {:ok, btc} =
      Catalog.update_security(owner, btc, %{
        note: "cold storage; rebalance only on drift > 5pp",
        attributes: Map.put(btc.attributes || %{}, "custom_risk_bucket", "speculative")
      })

    {:ok, acme} =
      Catalog.update_security(owner, acme, %{
        note: "core holding",
        attributes: Map.put(acme.attributes || %{}, "review_after", "2026-12-31")
      })

    # The research log (ADR-0044): a thesis and a retraction on the imported
    # securities — the entries an agent would have written between two
    # imports of the same bookkeeping history.
    {:ok, thesis} =
      Knowledge.append_note(owner, %{
        security_id: acme.id,
        author: "agent",
        kind: "thesis",
        body: "core holding; pricing power intact",
        conviction: "high",
        source_quality: "primary",
        as_of: ~D[2026-07-01]
      })

    {:ok, _retraction} =
      Knowledge.append_note(owner, %{
        security_id: btc.id,
        author: "agent",
        kind: "evidence",
        body: "custody provider audit pending",
        source_quality: "awareness",
        as_of: ~D[2026-07-02]
      })

    snapshot = %{
      plans: plan_snapshot(portfolio.id),
      targets: target_snapshot(portfolio.id),
      assignments: assignment_snapshot([btc.id, acme.id], classification.id),
      securities: security_snapshot([btc.id, acme.id]),
      transaction_count: Ledger.count_transactions(),
      research_log: research_log_snapshot([btc.id, acme.id])
    }

    assert length(snapshot.research_log) == 2

    assert snapshot.securities |> Enum.map(& &1.note) |> Enum.all?(&is_binary/1)

    # --- the re-import of the identical file ------------------------------
    reimport = parse_fixture!("golden_path_initial.json")

    assert {:ok, %Result{} = result} = Imports.apply(reimport, %{portfolio_id: portfolio.id})

    # Content-hash idempotency: a full no-op.
    assert result.created_securities == 0
    assert result.created_transactions == 0
    assert result.skipped_duplicates == 3
    assert result.unresolved_entries == []

    # --- the survival contract, exactly -----------------------------------
    assert plan_snapshot(portfolio.id) == snapshot.plans
    assert target_snapshot(portfolio.id) == snapshot.targets
    assert assignment_snapshot([btc.id, acme.id], classification.id) == snapshot.assignments
    assert security_snapshot([btc.id, acme.id]) == snapshot.securities
    assert Ledger.count_transactions() == snapshot.transaction_count
    assert Decimal.equal?(Targets.get_cash_target(portfolio.id), Decimal.new("0.10"))
    assert Catalog.count_securities() == 2

    # The research log survives untouched: same rows, same ids, same bodies,
    # and the derived thesis state still reads from the same entry.
    assert research_log_snapshot([btc.id, acme.id]) == snapshot.research_log
    assert Knowledge.count_notes() == 2
    assert Knowledge.thesis_state(acme.id).derived_from_entry_id == thesis.id
  end

  # User story (issue #664 companion — the mutated re-import keeps notes and
  # attributes too):
  # As a local portfolio maintainer whose broker renamed a security and
  # changed an ISIN between exports,
  # I want the mutated re-import (the 18.2 golden path) to also preserve each
  # security's note and attributes,
  # so that identity resolution through aliases and overrides never rewrites
  # the catalog fields I maintain by hand.
  #
  # Acceptance criteria:
  # - After the mutated re-import (explicit override + former-ISIN alias),
  #   `note` and `attributes` on both securities are unchanged.
  # - The one genuinely new booking still lands; nothing else changes.
  test "a mutated re-import (rename + ISIN change) preserves notes and attributes" do
    portfolio = setup_portfolio()
    owner = Actor.owner_ui()

    initial = parse_fixture!("golden_path_initial.json")
    assert {:ok, %Result{}} = Imports.apply(initial, %{portfolio_id: portfolio.id})

    btc = find_security!(&(&1.name == "Bitcoin"))
    acme = find_security!(&(&1.isin == "DE000ACME001"))

    {:ok, btc} =
      Catalog.update_security(owner, btc, %{
        note: "cold storage",
        attributes: Map.put(btc.attributes || %{}, "custom_risk_bucket", "speculative")
      })

    {:ok, acme} =
      Catalog.update_security(owner, acme, %{
        note: "core holding",
        attributes: Map.put(acme.attributes || %{}, "review_after", "2026-12-31")
      })

    securities_before = security_snapshot([btc.id, acme.id])

    {:ok, %{security: acme}} = Catalog.record_isin_change(owner, acme, "DE000ACME119")

    mutated = parse_fixture!("golden_path_mutated.json")
    %{resolutions: resolutions} = Imports.resolve_securities(mutated)

    acme_res = Enum.find(resolutions, &(&1.ref.isin == "DE000ACME001"))
    btc_res = Enum.find(resolutions, &(&1.ref.name == "BTC (Cold Wallet)"))

    assert {:ok, %Result{created_securities: 0, created_transactions: 1}} =
             Imports.apply(mutated, %{
               portfolio_id: portfolio.id,
               security_mappings: %{btc_res.key => {:existing, btc.id}},
               approved_resolutions: %{acme_res.key => {:matched, acme.id}}
             })

    securities_after = security_snapshot([btc.id, acme.id])

    # note + attributes byte-for-byte; the recorded ISIN change is the ONLY
    # difference the mutated import may leave on the catalog rows.
    assert strip_isin(securities_after) == strip_isin(securities_before)
    assert Catalog.get_security!(acme.id).isin == "DE000ACME119"
    assert Catalog.get_security!(btc.id).name == "Bitcoin"
  end

  defp research_log_snapshot(security_ids) do
    for id <- security_ids, note <- Knowledge.list_notes(id) do
      %{
        id: note.id,
        security_id: note.security_id,
        kind: note.kind,
        body: note.body,
        as_of: note.as_of,
        source_quality: note.source_quality,
        inserted_at: note.inserted_at
      }
    end
  end

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

  # id + identity + the operator-maintained fields; updated_at pins "no
  # silent rewrite" on the identical re-import.
  defp security_snapshot(security_ids) do
    for security_id <- security_ids do
      security = Catalog.get_security!(security_id)

      %{
        id: security.id,
        name: security.name,
        isin: security.isin,
        note: security.note,
        attributes: security.attributes,
        updated_at: security.updated_at
      }
    end
  end

  defp strip_isin(snapshots), do: Enum.map(snapshots, &Map.drop(&1, [:isin, :updated_at]))

  defp decimal_str(nil), do: nil
  defp decimal_str(%Decimal{} = value), do: Decimal.to_string(value, :normal)
end
