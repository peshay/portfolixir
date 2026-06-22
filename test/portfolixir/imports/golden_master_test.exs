defmodule Portfolixir.Imports.GoldenMasterTest do
  @moduledoc """
  Golden-master regression of the Portfolio Performance import.

  Imports the checked-in synthetic PP exports (`sample.json` and `sample.csv`)
  through the real `Portfolixir.Imports` flow and asserts Decimal-exact derived
  outputs — cash balances, positions and the portfolio valuation — against
  values baked into this test. The expected numbers are hand-derived from the
  fixtures (see the per-account/per-position breakdown in comments below). If
  import, projection, holdings or valuation behaviour drifts, the exact
  comparisons here fail, never silently rounding the difference away.
  """
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Imports
  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Valuation

  @fixtures Path.expand("../../support/fixtures/portfolio_performance", __DIR__)

  defp read!(name), do: File.read!(Path.join(@fixtures, name))

  defp import_target do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "Golden target",
        base_currency_code: "EUR"
      })

    portfolio
  end

  defp cash_balance(portfolio_id, name) do
    account =
      portfolio_id
      |> Portfolios.list_cash_accounts_for_portfolio()
      |> Enum.find(&(&1.name == name))

    Ledger.cash_balances(portfolio_id: portfolio_id) |> Map.fetch!(account.id)
  end

  # The JSON corpus carries ISINs; the CSV corpus carries only security names
  # (PP's CSV export omits ISIN). The match function lets each golden master
  # identify the security with the field its source actually provides.
  defp position_quantity(portfolio_id, depot_name, match) do
    depot =
      portfolio_id
      |> Portfolios.list_securities_accounts_for_portfolio()
      |> Enum.find(&(&1.name == depot_name))

    security_id = security_id(portfolio_id, match)

    Ledger.positions_for_portfolio(portfolio_id)
    |> Map.get({depot.id, security_id})
  end

  defp security_id(portfolio_id, match) do
    portfolio_id
    |> Ledger.list_transactions_for_portfolio()
    |> Enum.map(& &1.security)
    |> Enum.reject(&is_nil/1)
    |> Enum.find(match)
    |> Map.fetch!(:id)
  end

  # User story:
  # As a local portfolio maintainer importing my Portfolio Performance history,
  # I want a golden-master test that imports a known synthetic export and pins
  # the exact derived cash balances, positions and valuation,
  # so that any future change which silently alters import maths is caught by an
  # exact Decimal comparison rather than slipping through.
  #
  # Acceptance criteria:
  # - Importing sample.json yields the exact expected per-account cash balances.
  # - Importing sample.json yields the exact expected per-depot positions, with
  #   Apple netted to zero (dropped) and MSCI World ending in Test-Depot-2.
  # - The portfolio valuation (cash + a priced position) is Decimal-exact.
  describe "golden master: sample.json" do
    setup do
      portfolio = import_target()
      {:ok, preview} = PortfolioPerformance.parse(read!("sample.json"), filename: "sample.json")
      {:ok, _result} = Imports.apply(preview, %{portfolio_id: portfolio.id})
      {:ok, portfolio: portfolio}
    end

    test "derives exact cash balances per account", %{portfolio: portfolio} do
      # Test-Cash legs (all EUR, signs from Portfolixir.Ledger.Projection):
      #   buy            -1502.50
      #   sell           +1800.00
      #   dividend          +9.13
      #   interest          +4.55
      #   deposit        +5000.00
      #   removal         -250.00
      #   fee               -8.50
      #   tax              -50.00
      #   tax_refund       +15.00
      #   cash_transfer  -1000.00
      #   => 4017.68
      assert Decimal.equal?(cash_balance(portfolio.id, "Test-Cash"), Decimal.new("4017.68"))

      # Test-Cash-2: only the inbound leg of the cash transfer (+1000.00).
      assert Decimal.equal?(cash_balance(portfolio.id, "Test-Cash-2"), Decimal.new("1000.00"))
    end

    test "derives exact positions per depot", %{portfolio: portfolio} do
      apple = &(&1.isin == "US0378331005")
      msci = &(&1.isin == "IE00B4L5Y983")

      # Apple (US0378331005): buy 10, sell 10 => 0, dropped from positions.
      assert position_quantity(portfolio.id, "Test-Depot", apple) == nil

      # MSCI World (IE00B4L5Y983): inbound 5, outbound 2 => 3 in Test-Depot,
      # then security_transfer 3 to Test-Depot-2 => Test-Depot 0 (dropped),
      # Test-Depot-2 holds 3.
      assert position_quantity(portfolio.id, "Test-Depot", msci) == nil

      assert Decimal.equal?(
               position_quantity(portfolio.id, "Test-Depot-2", msci),
               Decimal.new("3.0")
             )
    end

    test "derives exact valuation with an injected MSCI World price", %{portfolio: portfolio} do
      msci_id = security_id(portfolio.id, &(&1.isin == "IE00B4L5Y983"))

      valuation =
        Valuation.for_portfolio(portfolio.id, prices: %{msci_id => Decimal.new("90.00")})

      # The only currently-held position is MSCI World: 3.0 @ 90.00 = 270.00,
      # already in the EUR base currency (no FX conversion needed).
      assert Decimal.equal?(valuation.total_value, Decimal.new("270.00"))
      assert valuation.unvalued_count == 0

      # Cash: Test-Cash 4017.68 + Test-Cash-2 1000.00 = 5017.68 EUR.
      assert Decimal.equal?(valuation.total_cash, Decimal.new("5017.68"))

      # Net worth = positions + cash.
      assert Decimal.equal?(valuation.total_with_cash, Decimal.new("5287.68"))
    end
  end

  # User story:
  # As a maintainer who exported the same history as CSV instead of JSON,
  # I want the CSV import to produce the identical derived cash balances and
  # positions as the JSON import,
  # so that the chosen export format never changes my books.
  #
  # Acceptance criteria:
  # - Importing sample.csv yields the same exact cash balances as sample.json.
  # - Importing sample.csv yields the same exact MSCI World position.
  describe "golden master: sample.csv matches sample.json" do
    setup do
      portfolio = import_target()
      {:ok, preview} = PortfolioPerformance.parse(read!("sample.csv"), filename: "sample.csv")
      {:ok, _result} = Imports.apply(preview, %{portfolio_id: portfolio.id})
      {:ok, portfolio: portfolio}
    end

    test "derives the same exact cash balances as the JSON corpus", %{portfolio: portfolio} do
      assert Decimal.equal?(cash_balance(portfolio.id, "Test-Cash"), Decimal.new("4017.68"))
      assert Decimal.equal?(cash_balance(portfolio.id, "Test-Cash-2"), Decimal.new("1000.00"))
    end

    test "derives the same exact MSCI World position", %{portfolio: portfolio} do
      msci = &(&1.name == "iShares Core MSCI World UCITS ETF")

      assert Decimal.equal?(
               position_quantity(portfolio.id, "Test-Depot-2", msci),
               Decimal.new("3")
             )
    end
  end
end
