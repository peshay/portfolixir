defmodule Portfolixir.Imports.ApplierSettlementTest do
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Fx
  alias Portfolixir.Imports.Applier
  alias Portfolixir.Imports.Entry
  alias Portfolixir.Imports.Preview
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios
  alias Portfolixir.Repo

  # All figures are synthetic (the ADR-0033 fixture family).

  defp portfolio! do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Import FX Portfolio",
        base_currency_code: "EUR"
      })

    portfolio
  end

  defp usd_security! do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Imported US Equity",
        ticker_symbol: "IUS",
        isin: "US0000000001",
        currency_code: "USD",
        asset_class: "equity"
      })

    security
  end

  defp buy_entry(overrides) do
    struct!(
      %Entry{
        source_row: 1,
        kind: "buy",
        date: ~D[2026-01-15],
        currency_code: "EUR",
        gross_amount: Decimal.new("800.00"),
        quantity: Decimal.new("10"),
        price: Decimal.new("80.00"),
        security: %{isin: "US0000000001", name: "Imported US Equity", currency: "USD"},
        pp_portfolio_name: "PP Depot",
        pp_account_name: "PP Cash"
      },
      overrides
    )
  end

  defp apply!(entry, portfolio) do
    {:ok, _result} =
      Applier.apply(%Preview{entries: [entry]}, %{
        portfolio_id: portfolio.id,
        default_currency_code: "EUR"
      })

    Repo.one!(from(t in Transaction, where: t.type == ^entry.kind))
  end

  # User story (ADR-0033 / issue #569):
  # As a maintainer importing a Portfolio Performance export that books a
  # USD security's buy in EUR (the account currency),
  # I want the applier to persist the ADR-0015 settlement fields with the
  # security-currency leg derived from the stored hub rate at the booking
  # date,
  # so that the cost fold can carry an honest cost pair without ever looking
  # a rate up at read time.
  #
  # Acceptance criteria:
  # - With a stored EUR-hub rate at the booking date (1 EUR = 1.25 USD):
  #   settlement_amount = 800.00 EUR, security_amount = 1000.00 USD,
  #   settlement_fx_rate = 0.80 (settlement per 1 security unit).
  # - All three are Decimal columns, derived at WRITE time.
  test "a cross-currency PP buy persists the derived settlement legs" do
    portfolio = portfolio!()
    usd_security!()

    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2026-01-15],
          rate: "1.25",
          source: "manual"
        }
      ])

    tx = apply!(buy_entry(%{}), portfolio)

    assert tx.currency_code == "EUR"
    assert Decimal.equal?(tx.settlement_amount, Decimal.new("800.00"))
    assert Decimal.equal?(tx.security_amount, Decimal.new("1000.00"))
    assert Decimal.equal?(tx.settlement_fx_rate, Decimal.new("0.80"))
  end

  # User story (ADR-0033 requirement 4 — honesty over availability):
  # As a maintainer importing the same buy without any stored rate for the
  # booking date,
  # I want the settlement fields left empty instead of guessed,
  # so that the position's decomposition reads honestly unavailable.
  test "a cross-currency PP buy with no stored rate keeps the fields nil" do
    portfolio = portfolio!()
    usd_security!()

    tx = apply!(buy_entry(%{}), portfolio)

    assert is_nil(tx.security_amount)
    assert is_nil(tx.settlement_amount)
    assert is_nil(tx.settlement_fx_rate)
  end

  # User story (counter-metric):
  # As a maintainer importing an ordinary same-currency buy,
  # I want no settlement fields stored,
  # so that the same-currency majority keeps behaving exactly as before.
  test "a same-currency PP buy stores no settlement fields" do
    portfolio = portfolio!()

    entry =
      buy_entry(%{
        security: %{isin: "DE0000000001", name: "Imported EU Equity", currency: "EUR"},
        currency_code: "EUR"
      })

    tx = apply!(entry, portfolio)

    assert is_nil(tx.security_amount)
    assert is_nil(tx.settlement_amount)
    assert is_nil(tx.settlement_fx_rate)
  end

  # User story (sells too):
  # As a maintainer importing a cross-currency sell,
  # I want the same derived settlement legs on the sell row,
  # so that removals slice the cost pair with the same honesty as buys.
  test "a cross-currency PP sell persists the derived settlement legs" do
    portfolio = portfolio!()
    usd_security!()

    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2026-03-01],
          rate: "1.25",
          source: "manual"
        }
      ])

    entry =
      buy_entry(%{
        kind: "sell",
        date: ~D[2026-03-01],
        gross_amount: Decimal.new("400.00"),
        quantity: Decimal.new("5"),
        price: Decimal.new("80.00")
      })

    tx = apply!(entry, portfolio)

    assert Decimal.equal?(tx.settlement_amount, Decimal.new("400.00"))
    assert Decimal.equal?(tx.security_amount, Decimal.new("500.00"))
    assert Decimal.equal?(tx.settlement_fx_rate, Decimal.new("0.80"))
  end
end
