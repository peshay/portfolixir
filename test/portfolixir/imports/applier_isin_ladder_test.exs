defmodule Portfolixir.Imports.ApplierIsinLadderTest do
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Applier.Result
  alias Portfolixir.Imports.Entry
  alias Portfolixir.Imports.Preview
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

  defp create_security!(attrs) do
    {:ok, security} =
      Catalog.create_security(
        Actor.owner_ui(),
        Map.merge(%{name: "Example AG", currency_code: "EUR"}, attrs)
      )

    security
  end

  defp buy_preview(isin, opts \\ []) do
    %Preview{
      format: :json,
      entries: [
        %Entry{
          source_row: 1,
          kind: "buy",
          date: ~D[2024-04-01],
          currency_code: "EUR",
          gross_amount: Keyword.get(opts, :gross, Decimal.new("1500.00")),
          fees: Decimal.new("0"),
          taxes: Decimal.new("0"),
          quantity: Keyword.get(opts, :quantity, Decimal.new("10")),
          price: Keyword.get(opts, :price, Decimal.new("150.00")),
          security: %{
            name: Keyword.get(opts, :name, "Example AG"),
            isin: isin,
            wkn: nil,
            ticker: nil,
            currency: "EUR"
          },
          pp_portfolio_name: "Test-Depot",
          pp_account_name: "Test-Cash"
        }
      ]
    }
  end

  # User story:
  # As a local portfolio maintainer re-importing a PP export,
  # I want the import's ISIN lookup to consult current ISINs first and then
  # the recorded former-ISIN aliases (ADR-0029 §2 tier 1, §3),
  # so that an export still carrying a retired ISIN resolves to the same
  # security instead of creating a duplicate.
  #
  # Acceptance criteria:
  # - An entry whose ISIN matches a recorded alias resolves to the aliased
  #   security; no new security is created.
  # - The alias hit is labeled in the result ("matched via former ISIN").
  # - ISIN comparison uses the catalog normal form (a lowercase ISIN in the
  #   file matches).
  describe "apply/2 ISIN tier with aliases" do
    test "resolves an entry via a former-ISIN alias and labels the match" do
      portfolio = setup_portfolio()
      security = create_security!(%{isin: "DE0001234567"})

      {:ok, %{security: security}} =
        Catalog.record_isin_change(Actor.owner_ui(), security, "DE0007654321")

      assert {:ok, %Result{} = result} =
               Imports.apply(buy_preview("DE0001234567"), %{portfolio_id: portfolio.id})

      assert result.created_securities == 0
      assert result.created_transactions == 1
      assert result.resolved_security_ids == [security.id]

      assert [%{row: 1, former_isin: "DE0001234567", security_id: matched_id}] =
               result.alias_matches

      assert matched_id == security.id

      assert [transaction] = Ledger.list_transactions()
      assert transaction.security_id == security.id
    end

    test "matches a lowercase ISIN in the file against the stored current ISIN" do
      portfolio = setup_portfolio()
      security = create_security!(%{isin: "DE0001234567"})

      assert {:ok, %Result{} = result} =
               Imports.apply(buy_preview("de0001234567"), %{portfolio_id: portfolio.id})

      assert result.created_securities == 0
      assert result.resolved_security_ids == [security.id]
      assert result.alias_matches == []
    end

    test "matches a lowercase ISIN in the file against a former-ISIN alias" do
      portfolio = setup_portfolio()
      security = create_security!(%{isin: "DE0001234567"})

      {:ok, %{security: security}} =
        Catalog.record_isin_change(Actor.owner_ui(), security, "DE0007654321")

      assert {:ok, %Result{} = result} =
               Imports.apply(buy_preview(" de0001234567 "), %{portfolio_id: portfolio.id})

      assert result.created_securities == 0
      assert result.resolved_security_ids == [security.id]
      assert [%{former_isin: "DE0001234567"}] = result.alias_matches
    end
  end

  # User story:
  # As a local portfolio maintainer who recorded an ISIN change,
  # I want re-imports in BOTH directions to stay no-ops (ADR-0029 §5):
  # a new export carrying the new ISIN resolves via the current-ISIN tier,
  # and an old export carrying the former ISIN resolves via the alias tier,
  # with the #533 resolved-identity dedup key absorbing content-hash drift,
  # so that the recorded change never mints duplicate bookings or securities.
  #
  # Acceptance criteria:
  # - Both re-imports report the booking as a skipped duplicate.
  # - Both re-imports create zero securities.
  describe "apply/2 idempotency across a recorded ISIN change (#533, ADR-0029 §5)" do
    setup do
      portfolio = setup_portfolio()

      # Initial import establishes the booking under the old ISIN A.
      {:ok, %Result{created_transactions: 1, created_securities: 1}} =
        Imports.apply(buy_preview("DE000000000A"), %{portfolio_id: portfolio.id})

      security = Enum.find(Catalog.list_securities(), &(&1.isin == "DE000000000A"))

      {:ok, %{security: security}} =
        Catalog.record_isin_change(Actor.owner_ui(), security, "DE000000000B")

      {:ok, portfolio: portfolio, security: security}
    end

    test "a NEW export (new ISIN) resolves via the current-ISIN tier and dedups",
         %{portfolio: portfolio, security: security} do
      # The new export carries the new ISIN and drifted decimal formatting, so
      # the content import_hash differs — the resolved dedup key must hold.
      preview =
        buy_preview("DE000000000B",
          gross: Decimal.new("1500"),
          quantity: Decimal.new("10.0"),
          price: Decimal.new("150.000")
        )

      assert {:ok, %Result{} = result} = Imports.apply(preview, %{portfolio_id: portfolio.id})

      assert result.created_securities == 0
      assert result.created_transactions == 0
      assert result.skipped_duplicates == 1
      assert result.alias_matches == []
      assert Ledger.count_transactions() == 1
      assert Catalog.get_security!(security.id).isin == "DE000000000B"
    end

    test "an OLD export (former ISIN) resolves via the alias tier and dedups",
         %{portfolio: portfolio, security: security} do
      preview =
        buy_preview("DE000000000A",
          gross: Decimal.new("1500"),
          quantity: Decimal.new("10.0"),
          price: Decimal.new("150.000")
        )

      assert {:ok, %Result{} = result} = Imports.apply(preview, %{portfolio_id: portfolio.id})

      assert result.created_securities == 0
      assert result.created_transactions == 0
      assert result.skipped_duplicates == 1
      assert [%{former_isin: "DE000000000A", security_id: matched_id}] = result.alias_matches
      assert matched_id == security.id
      assert Ledger.count_transactions() == 1
    end
  end
end
