defmodule Portfolixir.Portfolios.PerformanceBlastRadiusTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Derived.BlastRadius
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  # User story (2026-07-29, ADR-0032 §3, issue #562):
  # As a local portfolio maintainer,
  # I want a write to invalidate only the portfolios it can actually change,
  # so that one booking does not make every other portfolio recompute.
  #
  # Acceptance criteria:
  # - "Affected" is resolved HISTORICALLY: a portfolio that once held a
  #   security is still affected by a quote for it, even after selling out.
  # - A transfer invalidates both legs.
  # - Anything the resolver cannot prove narrow invalidates everything, so a
  #   forgotten write kind costs a recomputation, never a wrong number.

  defp world(name, currency \\ "EUR") do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{name: name, base_currency_code: currency})

    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: name <> " Cash",
        currency_code: currency
      })

    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: name <> " Depot"
      })

    %{portfolio: portfolio, cash: cash, depot: depot}
  end

  defp security!(attrs) do
    {:ok, security} =
      Catalog.create_security(
        Actor.owner_ui(),
        Map.merge(%{name: "Blast AG", currency_code: "EUR"}, attrs)
      )

    security
  end

  defp buy!(world, security, date) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
        security_id: security.id,
        type: "buy",
        date: date,
        quantity: Decimal.new("1"),
        price: Decimal.new("10"),
        gross_amount: Decimal.new("10"),
        currency_code: "EUR"
      })

    tx
  end

  test "a transaction invalidates its own portfolio only" do
    a = world("Blast A")
    b = world("Blast B")
    security = security!(%{isin: "DE000BLAST01"})
    tx = buy!(a, security, ~D[2024-01-02])

    assert BlastRadius.for_write("transaction", tx) == [a.portfolio.id]
    refute b.portfolio.id in BlastRadius.for_write("transaction", tx)
  end

  # The data model pins both counter legs to the transaction's own portfolio
  # (composite FKs on (counter_account_id, portfolio_id)), so a transfer cannot
  # cross a portfolio boundary and there is no second leg to invalidate.
  test "a transfer stays inside its portfolio, so it has one leg to invalidate" do
    a = world("Transfer A")

    {:ok, second_cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: a.portfolio.id,
        name: "Transfer A Second Cash",
        currency_code: "EUR"
      })

    {:ok, transfer} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: a.portfolio.id,
        cash_account_id: a.cash.id,
        counter_cash_account_id: second_cash.id,
        type: "cash_transfer",
        date: ~D[2024-02-02],
        gross_amount: Decimal.new("100"),
        currency_code: "EUR"
      })

    assert BlastRadius.for_write("transaction", transfer) == [a.portfolio.id]
  end

  # The subtle one: the series is historical, so selling out does not end the
  # relationship between a portfolio and a security's quotes.
  test "a quote invalidates every portfolio that EVER transacted the security" do
    a = world("Quote A")
    b = world("Quote B")
    held = security!(%{isin: "DE000BLAST02"})
    other = security!(%{isin: "DE000BLAST03"})

    buy!(a, held, ~D[2019-05-02])

    {:ok, _sell} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: a.portfolio.id,
        securities_account_id: a.depot.id,
        cash_account_id: a.cash.id,
        security_id: held.id,
        type: "sell",
        date: ~D[2020-05-02],
        quantity: Decimal.new("1"),
        price: Decimal.new("12"),
        gross_amount: Decimal.new("12"),
        currency_code: "EUR"
      })

    buy!(b, other, ~D[2024-01-02])

    # Portfolio A holds nothing of `held` any more, and is still affected.
    assert BlastRadius.for_quote(held.id) == [a.portfolio.id]
    assert BlastRadius.for_quote(other.id) == [b.portfolio.id]
  end

  test "a quote for a security nobody ever transacted affects nothing" do
    _a = world("Untraded A")
    security = security!(%{isin: "DE000BLAST04"})

    assert BlastRadius.for_quote(security.id) == []
  end

  test "an exchange rate invalidates only portfolios with a foreign-currency touch" do
    domestic = world("Domestic", "EUR")
    foreign_account = world("Foreign Account", "EUR")

    {:ok, _usd_cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: foreign_account.portfolio.id,
        name: "USD Cash",
        currency_code: "USD"
      })

    foreign_security = world("Foreign Security", "EUR")
    usd_security = security!(%{isin: "US000BLAST05", currency_code: "USD"})
    buy!(foreign_security, usd_security, ~D[2024-03-02])

    affected = BlastRadius.for_exchange_rate()

    refute domestic.portfolio.id in affected
    assert foreign_account.portfolio.id in affected
    assert foreign_security.portfolio.id in affected
  end

  test "accounts and depots invalidate their owning portfolio" do
    a = world("Account A")

    assert BlastRadius.for_write("cash_account", a.cash) == [a.portfolio.id]
    assert BlastRadius.for_write("securities_account", a.depot) == [a.portfolio.id]
    assert BlastRadius.for_write("portfolio", a.portfolio) == [a.portfolio.id]
  end

  # ADR-0032 §3.3 — the safety net. Widening is the ONLY default.
  test "an unlisted resource type invalidates everything" do
    assert BlastRadius.for_write("something_nobody_wired_up", %{}) == :all
    assert BlastRadius.for_write("bucket", %{id: 1}) == :all
    assert BlastRadius.for_write("view", %{id: 1}) == :all
  end

  test "a listed type whose record lacks the fields to resolve it widens too" do
    # A bulk write journals an aggregate with no resource id — it cannot be
    # narrowed, so it must not be narrowed.
    assert BlastRadius.for_write("transaction", %{}) == :all
    assert BlastRadius.for_write("cash_account", %{}) == :all
  end
end
