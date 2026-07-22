defmodule Portfolixir.Portfolios.Performance.SplitBasisTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, sell!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog.Quote, as: SecurityQuote
  alias Portfolixir.Ledger.Splits
  alias Portfolixir.Portfolios.Performance

  defp insert_quote!(security, date, close, source) do
    {:ok, _} =
      %SecurityQuote{}
      |> SecurityQuote.changeset(%{
        security_id: security.id,
        date: date,
        close: Decimal.new(close),
        source: source
      })
      |> Repo.insert()
  end

  defp book_split!(security, date, {p, q}) do
    {:ok, txs} =
      Splits.book_split(Actor.owner_ui(), %{
        security_id: security.id,
        date: date,
        ratio_numerator: p,
        ratio_denominator: q
      })

    txs
  end

  defp series_values(result), do: Enum.map(result.series, & &1.value)

  # User story (ADR-0028 §2/§5 TTWROR continuity on the provider basis,
  # issue #590):
  # As a maintainer of a synced security that split in the real world,
  # I want the daily valuation walk to value pre-split days as
  # (quantity x cumulative later split ratio) x adjusted quote,
  # so that booking the split event REPAIRS the historical series the
  # provider's back-adjustment had silently skewed — no jump, exact Decimals.
  test "provider-adjusted series: booking the split repairs pre-split days and keeps TTWROR continuous" do
    world = base_world(name: "PB World", cash_name: "PB Cash", depot_name: "PB Depot")
    security = create_security!(name: "PB Co", ticker: "PBB")
    deposit!(world, "1000", ~D[2026-01-05])
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-05])

    # The provider's current, back-adjusted history after the 10:1 split:
    # every pre-split close is already divided by 10.
    insert_quote!(security, ~D[2026-01-05], "10", "coingecko")
    insert_quote!(security, ~D[2026-01-06], "10", "coingecko")
    insert_quote!(security, ~D[2026-01-07], "10", "coingecko")
    insert_quote!(security, ~D[2026-01-08], "10.5", "coingecko")

    book_split!(security, ~D[2026-01-07], {10, 1})

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-08])

    expected = ~w(1000 1000 1000 1050)

    for {value, expected_value} <- Enum.zip(series_values(result), expected) do
      assert Decimal.equal?(value, Decimal.new(expected_value))
    end

    [_d5, d6, d7, _d8] = result.series
    assert Decimal.equal?(d6.cumulative_ttwror, d7.cumulative_ttwror)
    assert Decimal.equal?(result.ttwror, Decimal.new("0.05"))
  end

  # User story (ADR-0028 §2 mixed series, issue #590):
  # As a maintainer whose history mixes manual raw rows with provider rows,
  # I want each priced day valued in that day's own as-traded basis per the
  # pricing row's source,
  # so that a raw row inside a back-adjusted mirror never dents the series.
  test "mixed series: a manual raw row among provider rows values its day consistently" do
    world = base_world(name: "MX World", cash_name: "MX Cash", depot_name: "MX Depot")
    security = create_security!(name: "MX Co", ticker: "MXX")
    deposit!(world, "1000", ~D[2026-01-05])
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-05])

    insert_quote!(security, ~D[2026-01-05], "10", "coingecko")
    # Manual raw close inside the provider range: as traded, pre-split.
    insert_quote!(security, ~D[2026-01-06], "100", "manual")
    insert_quote!(security, ~D[2026-01-07], "10", "coingecko")
    insert_quote!(security, ~D[2026-01-08], "10.5", "coingecko")

    book_split!(security, ~D[2026-01-07], {10, 1})

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-08])

    expected = ~w(1000 1000 1000 1050)

    for {value, expected_value} <- Enum.zip(series_values(result), expected) do
      assert Decimal.equal?(value, Decimal.new(expected_value))
    end
  end

  # User story (ADR-0028 §2 carried price across the boundary, issue #590):
  # As a maintainer whose last stored close predates the effective date,
  # I want the carried price rebased when the walk crosses the boundary,
  # so that the day the quantities scale never multiplies the value tenfold.
  test "a carried raw price rebases on the effective date instead of jumping" do
    world = base_world(name: "CR World", cash_name: "CR Cash", depot_name: "CR Depot")
    security = create_security!(name: "CR Co", ticker: "CRR")
    deposit!(world, "1000", ~D[2026-01-05])
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-05])
    insert_quote!(security, ~D[2026-01-05], "100", "manual")

    book_split!(security, ~D[2026-01-07], {10, 1})

    {:ok, result} = Performance.for_portfolio(world.portfolio.id, today: ~D[2026-01-08])

    for value <- series_values(result) do
      assert Decimal.equal?(value, Decimal.new("1000"))
    end

    assert Decimal.equal?(result.ttwror, Decimal.new("0"))
  end

  # User story (ADR-0028 §2, issue #590):
  # As a maintainer whose portfolio sold out of a security before another
  # portfolio's split was booked,
  # I want the security-level split events to drive the pricing basis even
  # without a split row in this portfolio's own ledger,
  # so that the held era's valuation is not halved by the provider's later
  # back-adjustment.
  test "a portfolio without its own split row still prices its held era in the as-traded basis" do
    world_a = base_world(name: "SE A", cash_name: "SEA Cash", depot_name: "SEA Depot")
    world_b = base_world(name: "SE B", cash_name: "SEB Cash", depot_name: "SEB Depot")
    security = create_security!(name: "SE Co", ticker: "SEE")

    # A holds through the split (gets the fan-out row); B sold out before it.
    buy!(world_a, security, quantity: "10", price: "100", date: ~D[2026-01-05])
    deposit!(world_b, "1000", ~D[2026-01-05])
    buy!(world_b, security, quantity: "10", price: "100", date: ~D[2026-01-05])
    sell!(world_b, security, quantity: "10", price: "110", date: ~D[2026-01-07])

    # Provider back-adjusted history for the 2:1 split on 2026-01-09.
    insert_quote!(security, ~D[2026-01-05], "50", "coingecko")
    insert_quote!(security, ~D[2026-01-06], "50", "coingecko")
    insert_quote!(security, ~D[2026-01-07], "55", "coingecko")

    split_rows = book_split!(security, ~D[2026-01-09], {2, 1})
    assert Enum.map(split_rows, & &1.portfolio_id) == [world_a.portfolio.id]

    {:ok, result} = Performance.for_portfolio(world_b.portfolio.id, today: ~D[2026-01-07])

    # Held era valued as traded: 10 x 100 = 1000, then 10 x 110 -> sold, cash 1100.
    expected = ~w(1000 1000 1100)

    for {value, expected_value} <- Enum.zip(series_values(result), expected) do
      assert Decimal.equal?(value, Decimal.new(expected_value))
    end
  end
end
