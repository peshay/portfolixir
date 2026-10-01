defmodule Portfolixir.LaunchTestFixtureTest do
  @moduledoc """
  The launch test's known answers (Sprint 17 plan D-1, #998), proven by the
  code rather than by hand.

  The launch test gives a fresh agent a synthetic bank export in an invented
  format (`test/fixtures/launch_test/beispielbank-umsaetze.csv`) and asks three
  questions whose answers must come back exact. This test books the ledger a
  correct conversion produces (`expected-ledger.json`), straight through the
  contexts, and asserts that the instance answers the three questions with
  the figures the fixture states. If a change to valuation, the realized
  report or the cash projection moves a figure, this test fails before a
  launch-test run reports a "wrong" agent.
  """
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.RealizedGains
  alias Portfolixir.Portfolios.Valuation

  @dir "test/fixtures/launch_test"

  # User story:
  # As the owner deciding whether to announce Portfolixir,
  # I want the launch test's three answers to be fixed by the code,
  # so that a run's result says something about the agent and the docs, not
  # about a figure somebody computed by hand.
  #
  # Acceptance criteria:
  # - Booking the expected ledger into two EUR portfolios gives the stated
  #   total value across both, with no quote stored (every position priced
  #   at its latest trade).
  # - This year's realized result of closed trades is the stated figure.
  # - The named cash account's balance is the stated figure.
  # - The export's own balance per account equals the ledger's cash balance,
  #   so the fixture's two halves describe the same history.
  test "the expected ledger answers the launch test's three questions exactly" do
    ledger = @dir |> Path.join("expected-ledger.json") |> File.read!() |> Jason.decode!()
    answers = ledger["answers"]

    world = book!(ledger)

    totals =
      Enum.map(world.portfolios, fn {_key, %{portfolio: portfolio}} ->
        Valuation.for_portfolio(portfolio.id).total_with_cash
      end)

    assert Decimal.equal?(Enum.reduce(totals, &Decimal.add/2), answers["total_value_eur"])
    assert Decimal.equal?(Valuation.for_view(nil).total_with_cash, answers["total_value_eur"])

    realized_2026 =
      RealizedGains.report(base_currency: "EUR").trades
      |> Enum.filter(&(&1.close_date.year == 2026))
      |> Enum.reduce(Decimal.new(0), &Decimal.add(&2, &1.realized_base))

    assert Decimal.equal?(realized_2026, answers["realized_2026_eur"])

    balances = Ledger.cash_balances()
    named = answers["cash_balance"]
    account = Enum.find(world.cash_accounts, &(&1.name == named["account"]))

    assert Decimal.equal?(Map.fetch!(balances, account.id), named["amount"])

    for {name, amount} <- export_balances() do
      account = Enum.find(world.cash_accounts, &(&1.name == name))
      assert Decimal.equal?(Map.fetch!(balances, account.id), amount), name
    end
  end

  defp book!(ledger) do
    portfolios =
      Map.new(ledger["portfolios"], fn %{"key" => key} = spec ->
        {:ok, portfolio} =
          Portfolios.create_portfolio(Actor.owner_ui(), %{
            name: "Launch test #{key}",
            base_currency_code: "EUR"
          })

        {:ok, cash} =
          Portfolios.create_cash_account(Actor.owner_ui(), %{
            portfolio_id: portfolio.id,
            name: spec["cash_account"],
            currency_code: "EUR",
            liquidity_role: "free_cash"
          })

        {:ok, depot} =
          Portfolios.create_securities_account(Actor.owner_ui(), %{
            portfolio_id: portfolio.id,
            cash_account_id: cash.id,
            name: spec["depot"]
          })

        {key, %{portfolio: portfolio, cash: cash, depot: depot}}
      end)

    securities =
      Map.new(ledger["securities"], fn %{"key" => key} = spec ->
        {:ok, security} =
          Catalog.create_security(Actor.owner_ui(), %{
            name: spec["name"],
            isin: spec["isin"],
            currency_code: "EUR",
            asset_class: "equity"
          })

        {key, security}
      end)

    for tx <- ledger["transactions"] do
      %{portfolio: portfolio, cash: cash, depot: depot} = Map.fetch!(portfolios, tx["portfolio"])

      attrs =
        %{
          portfolio_id: portfolio.id,
          cash_account_id: cash.id,
          type: tx["type"],
          date: Date.from_iso8601!(tx["date"]),
          gross_amount: tx["gross_amount"],
          currency_code: "EUR"
        }
        |> put_security(tx, securities, depot)

      {:ok, _} = Ledger.create_transaction(Actor.owner_ui(), attrs)
    end

    %{
      portfolios: portfolios,
      cash_accounts: Enum.map(portfolios, fn {_key, world} -> world.cash end)
    }
  end

  defp put_security(attrs, %{"security" => key} = tx, securities, depot) do
    attrs
    |> Map.put(:security_id, Map.fetch!(securities, key).id)
    |> Map.put(:quantity, tx["quantity"])
    |> Map.put(:taxes, tx["taxes"])
    |> then(fn attrs ->
      if tx["type"] in ["buy", "sell"] do
        attrs
        |> Map.put(:securities_account_id, depot.id)
        |> Map.put(:price, tx["price"])
        |> Map.put(:fees, tx["fees"])
      else
        attrs
      end
    end)
  end

  defp put_security(attrs, _tx, _securities, _depot), do: attrs

  # The export's running result per account: its signed `Betrag` column.
  defp export_balances do
    @dir
    |> Path.join("beispielbank-umsaetze.csv")
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.drop_while(&(not String.starts_with?(&1, "Buchungstag;")))
    |> Enum.drop(1)
    |> Enum.map(&String.split(&1, ";"))
    |> Enum.reduce(%{}, fn row, acc ->
      amount = row |> Enum.at(8) |> String.replace(".", "") |> String.replace(",", ".")
      Map.update(acc, Enum.at(row, 1), Decimal.new(amount), &Decimal.add(&1, amount))
    end)
  end
end
