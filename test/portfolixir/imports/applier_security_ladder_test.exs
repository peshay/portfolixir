defmodule Portfolixir.Imports.ApplierSecurityLadderTest do
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Applier.Result
  alias Portfolixir.Imports.Entry
  alias Portfolixir.Imports.Preview
  alias Portfolixir.Imports.SecurityResolver
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

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

  defp buy_entry(security_ref, opts \\ []) do
    %Entry{
      source_row: Keyword.get(opts, :row, 1),
      kind: "buy",
      date: Keyword.get(opts, :date, ~D[2024-04-01]),
      time: Keyword.get(opts, :time),
      currency_code: "EUR",
      gross_amount: Keyword.get(opts, :gross, Decimal.new("1500.00")),
      fees: Decimal.new("0"),
      taxes: Decimal.new("0"),
      quantity: Keyword.get(opts, :quantity, Decimal.new("10")),
      price: Keyword.get(opts, :price, Decimal.new("150.00")),
      security: security_ref,
      pp_portfolio_name: "Test-Depot",
      pp_account_name: "Test-Cash"
    }
  end

  defp preview(entries), do: %Preview{format: :json, entries: entries}

  defp ref_key(entry), do: SecurityResolver.key(SecurityResolver.effective_ref(entry))

  # User story:
  # As a local portfolio maintainer re-importing a PP export,
  # I want the applier to resolve securities through the full §2 ladder
  # (ISIN, WKN, ticker+currency, name+currency),
  # so that a renamed security still matches via a weaker identifier instead
  # of minting a duplicate.
  #
  # Acceptance criteria:
  # - A WKN match books onto the existing security; nothing is created.
  # - A ticker+currency match does the same below a missing WKN.
  describe "apply/2 ladder tiers 2-3" do
    test "resolves a renamed security by unique WKN" do
      portfolio = setup_portfolio()
      security = security!(%{wkn: "ABC123"})

      entry =
        buy_entry(%{isin: nil, wkn: "abc123", ticker: nil, name: "Renamed AG", currency: "EUR"})

      assert {:ok, %Result{} = result} =
               Imports.apply(preview([entry]), %{portfolio_id: portfolio.id})

      assert result.created_securities == 0
      assert result.created_transactions == 1
      assert result.resolved_security_ids == [security.id]
      assert [transaction] = Ledger.list_transactions()
      assert transaction.security_id == security.id
      # Matching never mutates matched master data: the rename stays out.
      assert Catalog.get_security!(security.id).name == "Example AG"
    end

    test "resolves by ticker+currency below a missing WKN" do
      portfolio = setup_portfolio()
      security = security!(%{ticker_symbol: "EXA"})

      entry =
        buy_entry(%{isin: nil, wkn: nil, ticker: "EXA", name: "Renamed AG", currency: "EUR"})

      assert {:ok, %Result{} = result} =
               Imports.apply(preview([entry]), %{portfolio_id: portfolio.id})

      assert result.created_securities == 0
      assert result.resolved_security_ids == [security.id]
    end
  end

  # User story:
  # As a local portfolio maintainer,
  # I want the non-interactive apply path to fail closed (ADR-0029 §2):
  # entries the ladder flags (ambiguity, veto conflict, config-at-risk) are
  # reported as unresolved, never auto-created or auto-matched,
  # so that a scripted or future API import can never silently merge or
  # strand configuration.
  #
  # Acceptance criteria:
  # - Flagged entries appear in `unresolved_entries` with row and reason.
  # - No transaction and no security is created for them.
  # - Unflagged entries in the same file still import.
  describe "apply/2 fails closed on surfaced decisions" do
    test "an ambiguous WKN entry is reported unresolved, not picked or created" do
      portfolio = setup_portfolio()
      _a = security!(%{name: "Share Class A", wkn: "AMB001"})
      _b = security!(%{name: "Share Class B", wkn: "AMB001"})

      flagged =
        buy_entry(%{isin: nil, wkn: "AMB001", ticker: nil, name: "Ambiguous", currency: "EUR"})

      clean =
        buy_entry(%{isin: nil, wkn: nil, ticker: nil, name: "Clean New AG", currency: "EUR"},
          row: 2,
          date: ~D[2024-04-02]
        )

      assert {:ok, %Result{} = result} =
               Imports.apply(preview([flagged, clean]), %{portfolio_id: portfolio.id})

      assert [%{row: 1, reason: reason}] = result.unresolved_entries
      assert reason =~ "ambiguous"
      assert result.created_transactions == 1
      assert result.created_securities == 1
      assert Catalog.count_securities() == 3
    end

    test "a veto conflict (unrecorded ISIN change shape) is reported unresolved" do
      portfolio = setup_portfolio()
      _existing = security!(%{isin: "DE000OLD0009", wkn: "WRG111"})

      flagged =
        buy_entry(%{isin: "DE000NEW0007", wkn: "WRG111", ticker: nil, name: "X", currency: "EUR"})

      assert {:ok, %Result{} = result} =
               Imports.apply(preview([flagged]), %{portfolio_id: portfolio.id})

      assert [%{row: 1, reason: reason}] = result.unresolved_entries
      assert reason =~ "stronger identifier"
      assert result.created_transactions == 0
      assert result.created_securities == 0
      assert Ledger.count_transactions() == 0
    end

    test "a config-at-risk creation is reported unresolved without an explicit mapping" do
      portfolio = setup_portfolio()
      at_risk = security!(%{name: "Config AG", currency_code: "USD"})

      {:ok, classification} =
        Portfolixir.Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

      {:ok, category} =
        Portfolixir.Classifications.create_category(Actor.owner_ui(), %{
          classification_id: classification.id,
          name: "Core"
        })

      {:ok, _} =
        Portfolixir.Classifications.assign_security(
          Actor.owner_ui(),
          at_risk.id,
          classification.id,
          category.id
        )

      flagged =
        buy_entry(%{isin: nil, wkn: nil, ticker: nil, name: "Config AG", currency: "EUR"})

      assert {:ok, %Result{} = result} =
               Imports.apply(preview([flagged]), %{portfolio_id: portfolio.id})

      assert [%{row: 1, reason: reason}] = result.unresolved_entries
      assert reason =~ "configuration"
      assert result.created_securities == 0
    end
  end

  # User story:
  # As a local portfolio maintainer (or a future API client),
  # I want explicit per-entry security mappings to resolve flagged entries —
  # remap to an existing security, acknowledge a creation, or remap AND
  # record the entry's ISIN as a §3 ISIN change,
  # so that surfaced decisions are resolvable without weakening the
  # fail-closed default.
  #
  # Acceptance criteria:
  # - `{:existing, id}` books the flagged entry onto that security.
  # - `:create` acknowledges a config-at-risk creation.
  # - `{:existing, id, :record_isin_change}` records the journaled ISIN
  #   change in the same import transaction.
  describe "apply/2 explicit security mappings" do
    test "remaps an ambiguous entry onto a chosen existing security" do
      portfolio = setup_portfolio()
      chosen = security!(%{name: "Share Class A", wkn: "AMB001"})
      _other = security!(%{name: "Share Class B", wkn: "AMB001"})

      entry =
        buy_entry(%{isin: nil, wkn: "AMB001", ticker: nil, name: "Ambiguous", currency: "EUR"})

      assert {:ok, %Result{} = result} =
               Imports.apply(preview([entry]), %{
                 portfolio_id: portfolio.id,
                 security_mappings: %{ref_key(entry) => {:existing, chosen.id}}
               })

      assert result.unresolved_entries == []
      assert result.created_securities == 0
      assert result.resolved_security_ids == [chosen.id]
      assert [%{security_id: mapped_id}] = result.security_overrides
      assert mapped_id == chosen.id
    end

    test "an explicit :create mapping acknowledges a config-at-risk creation" do
      portfolio = setup_portfolio()
      at_risk = security!(%{name: "Config AG", currency_code: "USD"})

      {:ok, classification} =
        Portfolixir.Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

      {:ok, category} =
        Portfolixir.Classifications.create_category(Actor.owner_ui(), %{
          classification_id: classification.id,
          name: "Core"
        })

      {:ok, _} =
        Portfolixir.Classifications.assign_security(
          Actor.owner_ui(),
          at_risk.id,
          classification.id,
          category.id
        )

      entry = buy_entry(%{isin: nil, wkn: nil, ticker: nil, name: "Config AG", currency: "EUR"})

      assert {:ok, %Result{} = result} =
               Imports.apply(preview([entry]), %{
                 portfolio_id: portfolio.id,
                 security_mappings: %{ref_key(entry) => :create}
               })

      assert result.unresolved_entries == []
      assert result.created_securities == 1
      assert result.created_transactions == 1
    end

    test "remap with :record_isin_change records the journaled §3 change" do
      portfolio = setup_portfolio()
      existing = security!(%{isin: "DE000OLD0009", wkn: "WRG111"})

      entry =
        buy_entry(%{isin: "DE000NEW0007", wkn: "WRG111", ticker: nil, name: "X", currency: "EUR"})

      assert {:ok, %Result{} = result} =
               Imports.apply(preview([entry]), %{
                 portfolio_id: portfolio.id,
                 security_mappings: %{
                   ref_key(entry) => {:existing, existing.id, :record_isin_change}
                 }
               })

      assert result.unresolved_entries == []
      assert result.created_securities == 0
      assert result.resolved_security_ids == [existing.id]
      assert [%{security_id: mapped_id, recorded_isin_change: true}] = result.security_overrides
      assert mapped_id == existing.id

      updated = Catalog.get_security!(existing.id)
      assert updated.isin == "DE000NEW0007"
      assert [alias_row] = Catalog.list_identifier_aliases(updated)
      assert alias_row.former_isin == "DE000OLD0009"
    end

    test "a mapping onto a missing security id rolls the import back" do
      portfolio = setup_portfolio()

      entry = buy_entry(%{isin: nil, wkn: nil, ticker: nil, name: "New AG", currency: "EUR"})

      assert {:error, {:invalid_security_mapping, _key}} =
               Imports.apply(preview([entry]), %{
                 portfolio_id: portfolio.id,
                 security_mappings: %{ref_key(entry) => {:existing, 999_999}}
               })

      assert Ledger.count_transactions() == 0
    end
  end

  # User story:
  # As a local portfolio maintainer whose export lists one paper under both
  # its old and its new ISIN (ADR-0029 §2 N:1 resolution),
  # I want rows collapsing to an identical resolved dedup key within one
  # apply run deduplicated and surfaced, not double-inserted,
  # so that an identity change never doubles a booking.
  #
  # Acceptance criteria:
  # - Both rows resolve to the one security; a single transaction is created.
  # - The collapsed row is surfaced in the result.
  # - Two legitimate same-day bookings distinct only by time still both book.
  describe "apply/2 N:1 within-run dedup" do
    test "old+new ISIN of one paper collapse to one booking, surfaced" do
      portfolio = setup_portfolio()
      security = security!(%{isin: "DE000000000A"})

      {:ok, %{security: security}} =
        Catalog.record_isin_change(Actor.owner_ui(), security, "DE000000000B")

      old_row =
        buy_entry(
          %{isin: "DE000000000A", wkn: nil, ticker: nil, name: "Example AG", currency: "EUR"},
          row: 1
        )

      new_row =
        buy_entry(
          %{isin: "DE000000000B", wkn: nil, ticker: nil, name: "Example AG", currency: "EUR"},
          row: 2
        )

      assert {:ok, %Result{} = result} =
               Imports.apply(preview([old_row, new_row]), %{portfolio_id: portfolio.id})

      assert result.created_transactions == 1
      assert result.skipped_duplicates == 1
      assert [%{row: 2}] = result.collapsed_duplicates
      assert Ledger.count_transactions() == 1
      assert [transaction] = Ledger.list_transactions()
      assert transaction.security_id == security.id
    end

    test "two same-day bookings distinct only by intraday time both import" do
      portfolio = setup_portfolio()
      _security = security!(%{isin: "DE000000000A"})

      first =
        buy_entry(
          %{isin: "DE000000000A", wkn: nil, ticker: nil, name: "Example AG", currency: "EUR"},
          row: 1,
          time: ~T[10:00:00]
        )

      second =
        buy_entry(
          %{isin: "DE000000000A", wkn: nil, ticker: nil, name: "Example AG", currency: "EUR"},
          row: 2,
          time: ~T[10:05:00]
        )

      assert {:ok, %Result{} = result} =
               Imports.apply(preview([first, second]), %{portfolio_id: portfolio.id})

      assert result.created_transactions == 2
      assert result.collapsed_duplicates == []
    end
  end

  # User story:
  # As a local portfolio maintainer whose preview sat open while the data
  # changed (ADR-0029 §2 preview→apply revalidation),
  # I want apply to re-run the ladder inside the import transaction and abort
  # when any entry's resolution differs from what I approved,
  # so that my consent cannot go stale.
  #
  # Acceptance criteria:
  # - A resolution differing from the approved baseline aborts the whole
  #   apply; nothing is committed.
  # - An unchanged baseline applies normally.
  describe "apply/2 preview→apply revalidation" do
    test "aborts when an approved match no longer holds" do
      portfolio = setup_portfolio()
      security = security!(%{isin: "DE0001234567"})

      entry =
        buy_entry(%{
          isin: "DE0001234567",
          wkn: nil,
          ticker: nil,
          name: "Example AG",
          currency: "EUR"
        })

      approved = %{ref_key(entry) => {:matched, security.id}}

      # The data changes between preview and apply: the ISIN moves to a
      # different (new) security, so the ladder now selects another id.
      {:ok, _} =
        Catalog.update_security(Actor.owner_ui(), security, %{isin: "DE0009999999"})

      other = security!(%{name: "Impostor AG", isin: "DE0001234567"})

      assert {:error, {:resolution_diverged, _key}} =
               Imports.apply(preview([entry]), %{
                 portfolio_id: portfolio.id,
                 approved_resolutions: approved
               })

      assert Ledger.count_transactions() == 0
      refute other.id == security.id
    end

    test "applies normally when the approved baseline still holds" do
      portfolio = setup_portfolio()
      security = security!(%{isin: "DE0001234567"})

      entry =
        buy_entry(%{
          isin: "DE0001234567",
          wkn: nil,
          ticker: nil,
          name: "Example AG",
          currency: "EUR"
        })

      assert {:ok, %Result{created_transactions: 1}} =
               Imports.apply(preview([entry]), %{
                 portfolio_id: portfolio.id,
                 approved_resolutions: %{ref_key(entry) => {:matched, security.id}}
               })
    end

    test "aborts when an entry key is missing from the approved baseline" do
      portfolio = setup_portfolio()
      _security = security!(%{isin: "DE0001234567"})

      entry =
        buy_entry(%{
          isin: "DE0001234567",
          wkn: nil,
          ticker: nil,
          name: "Example AG",
          currency: "EUR"
        })

      assert {:error, {:resolution_diverged, _key}} =
               Imports.apply(preview([entry]), %{
                 portfolio_id: portfolio.id,
                 approved_resolutions: %{}
               })

      assert Ledger.count_transactions() == 0
    end
  end
end
