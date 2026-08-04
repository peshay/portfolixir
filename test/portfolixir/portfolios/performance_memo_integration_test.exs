defmodule Portfolixir.Portfolios.PerformanceMemoIntegrationTest do
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.Performance.Cache

  # User story (2026-07-29, ADR-0032, issue #562):
  # As a local portfolio maintainer,
  # I want the memoised series to be indistinguishable from a fresh one and to
  # disappear the moment its inputs change,
  # so that the page gets faster without a single number getting less true.
  #
  # Acceptance criteria (ADR-0032 §7):
  # - §7.1 warm and cache-off results are Decimal-exactly equal, point by point.
  # - §7.6 one invalidation test per write kind, including the two historical
  #   cases that are easy to get wrong.
  # - The memo never leaks across portfolios, scopes or end dates.

  setup do
    Cache.reset()
    Application.put_env(:portfolixir, Cache, enabled?: true)
    on_exit(fn -> Application.put_env(:portfolixir, Cache, enabled?: false) end)
    :ok
  end

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
        Map.merge(%{name: "Memo AG", currency_code: "EUR"}, attrs)
      )

    security
  end

  defp buy!(world, security, date, price) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
        security_id: security.id,
        type: "buy",
        date: date,
        quantity: Decimal.new("10"),
        price: Decimal.new(price),
        gross_amount: Decimal.mult(Decimal.new("10"), Decimal.new(price)),
        currency_code: "EUR"
      })

    tx
  end

  defp quote!(security, date, close) do
    {:ok, _count} =
      Quotes.upsert_many(security.id, [%{date: date, close: close, source: "manual"}])
  end

  defp opts(_world), do: [today: ~D[2024-06-30]]

  defp series(world), do: Performance.analysis(world.portfolio.id, opts(world)).daily

  # §7.1 — the whole point: faster, not different.
  test "a memoised series is Decimal-exactly the series computed without the memo" do
    w = world("Identical")
    security = security!(%{isin: "DE000MEMO001"})
    buy!(w, security, ~D[2024-01-02], "100")
    quote!(security, ~D[2024-03-01], "120.50")
    quote!(security, ~D[2024-06-28], "97.25")

    Application.put_env(:portfolixir, Cache, enabled?: false)
    cold = series(w)

    Application.put_env(:portfolixir, Cache, enabled?: true)
    Cache.reset()
    _first = series(w)
    warm = series(w)

    assert length(warm) == length(cold)
    assert warm != []

    for {warm_point, cold_point} <- Enum.zip(warm, cold) do
      assert warm_point.date == cold_point.date
      assert Decimal.equal?(warm_point.value, cold_point.value)
      assert Decimal.equal?(warm_point.flow, cold_point.flow)
    end
  end

  test "the second read does not walk again" do
    w = world("Memoised")
    security = security!(%{isin: "DE000MEMO002"})
    buy!(w, security, ~D[2024-01-02], "100")

    first = Performance.analysis(w.portfolio.id, opts(w))
    version = Cache.version(w.portfolio.id)

    assert Performance.analysis(w.portfolio.id, opts(w)) == first
    # A read never bumps: only a write does. An unchanged version with an equal
    # result is the memo being read, not a walk that happened to agree.
    assert Cache.version(w.portfolio.id) == version
  end

  # §7.6 — one per write kind.
  test "booking a transaction invalidates that portfolio and no other" do
    a = world("Booking A")
    b = world("Booking B")
    security = security!(%{isin: "DE000MEMO003"})
    buy!(a, security, ~D[2024-01-02], "100")
    buy!(b, security, ~D[2024-01-02], "100")

    before_a = Performance.analysis(a.portfolio.id, opts(a))
    before_b = Performance.analysis(b.portfolio.id, opts(b))

    version_b = Cache.version(b.portfolio.id)

    buy!(a, security, ~D[2024-04-02], "110")

    refute Performance.analysis(a.portfolio.id, opts(a)) == before_a
    assert Performance.analysis(b.portfolio.id, opts(b)) == before_b
    assert Cache.version(b.portfolio.id) == version_b
  end

  # The historical case: A sold out, and a quote for the period it DID hold must
  # still invalidate it.
  test "a quote for a security a portfolio no longer holds still invalidates it" do
    a = world("Sold Out")
    security = security!(%{isin: "DE000MEMO004"})
    buy!(a, security, ~D[2024-01-02], "100")

    {:ok, _sell} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: a.portfolio.id,
        securities_account_id: a.depot.id,
        cash_account_id: a.cash.id,
        security_id: security.id,
        type: "sell",
        date: ~D[2024-02-01],
        quantity: Decimal.new("10"),
        price: Decimal.new("105"),
        gross_amount: Decimal.new("1050"),
        currency_code: "EUR"
      })

    _before = Performance.analysis(a.portfolio.id, opts(a))
    version = Cache.version(a.portfolio.id)

    # A quote dated inside the holding window it has since exited.
    quote!(security, ~D[2024-01-15], "108.00")

    assert Cache.version(a.portfolio.id) > version
  end

  # The other historical case: the portfolio's own currency is EUR, but it has a
  # USD cash account, so a rate reaches it through the ACCOUNT, not a holding.
  test "an exchange rate invalidates a portfolio it reaches through an account currency" do
    domestic = world("Rate Domestic")
    foreign = world("Rate Foreign")

    {:ok, _usd_cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: foreign.portfolio.id,
        name: "USD Cash",
        currency_code: "USD"
      })

    security = security!(%{isin: "DE000MEMO005"})
    buy!(domestic, security, ~D[2024-01-02], "100")
    buy!(foreign, security, ~D[2024-01-02], "100")

    _domestic_series = Performance.analysis(domestic.portfolio.id, opts(domestic))
    _foreign_series = Performance.analysis(foreign.portfolio.id, opts(foreign))
    domestic_version = Cache.version(domestic.portfolio.id)
    foreign_version = Cache.version(foreign.portfolio.id)

    {:ok, _count} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2024-03-01],
          rate: Decimal.new("1.08"),
          source: "manual"
        }
      ])

    # The single-currency portfolio is never converted, so a rate cannot move
    # it; the one holding a USD account is reached through that account.
    assert Cache.version(domestic.portfolio.id) == domestic_version
    assert Cache.version(foreign.portfolio.id) > foreign_version
  end

  test "an account write invalidates its portfolio" do
    a = world("Account Write")
    security = security!(%{isin: "DE000MEMO006"})
    buy!(a, security, ~D[2024-01-02], "100")

    _before = Performance.analysis(a.portfolio.id, opts(a))
    version = Cache.version(a.portfolio.id)

    {:ok, _second_cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: a.portfolio.id,
        name: "Second Cash",
        currency_code: "EUR"
      })

    assert Cache.version(a.portfolio.id) > version
  end

  # ADR-0032 §6 needs the superseded series to still be reachable.
  test "the superseded series stays readable while a fresh one would compute" do
    a = world("Superseded")
    security = security!(%{isin: "DE000MEMO007"})
    buy!(a, security, ~D[2024-01-02], "100")

    before = Performance.analysis(a.portfolio.id, opts(a))
    assert Performance.previous_analysis(a.portfolio.id, opts(a)) == nil

    buy!(a, security, ~D[2024-04-02], "110")

    assert Performance.previous_analysis(a.portfolio.id, opts(a)) == before
  end

  # #577: the cross-portfolio view walk is memoised under its own scope
  # dimension, and a write in ANY portfolio invalidates it — a view series
  # depends on every portfolio, so its narrowest blast radius is "any write"
  # (ADR-0032 §3.3: fail toward recomputation).
  test "a booking in any portfolio invalidates the memoised view walk" do
    a = world("View Walk A")
    b = world("View Walk B")
    security = security!(%{isin: "DE000MEMO008"})
    buy!(a, security, ~D[2024-01-02], "100")
    buy!(b, security, ~D[2024-01-02], "100")

    before = Performance.view_analysis(nil, today: ~D[2024-06-30])
    assert Performance.view_analysis(nil, today: ~D[2024-06-30]) == before

    tx = buy!(b, security, ~D[2024-04-02], "110")

    after_write = Performance.view_analysis(nil, today: ~D[2024-06-30])
    refute after_write == before
    assert Enum.any?(after_write.daily, &(&1.date == tx.date))
  end

  # ADR-0032 §6 for the view walk: the superseded cross-portfolio series stays
  # readable (one generation) while the fresh one computes.
  test "the superseded view series stays readable while a fresh one would compute" do
    a = world("View Superseded")
    security = security!(%{isin: "DE000MEMO009"})
    buy!(a, security, ~D[2024-01-02], "100")

    before = Performance.view_analysis(nil, today: ~D[2024-06-30])
    assert Performance.previous_view_analysis(nil, today: ~D[2024-06-30]) == nil

    buy!(a, security, ~D[2024-04-02], "110")

    assert Performance.previous_view_analysis(nil, today: ~D[2024-06-30]) == before
  end
end
