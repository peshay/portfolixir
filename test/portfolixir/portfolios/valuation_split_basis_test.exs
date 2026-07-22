defmodule Portfolixir.Portfolios.ValuationSplitBasisTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog.Quote, as: SecurityQuote
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Splits
  alias Portfolixir.Portfolios.Valuation

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

  defp only_position(valuation) do
    assert [position] = valuation.positions
    position
  end

  # User story (ADR-0028 §2/§5 quote-basis matrix, issue #590):
  # As a local portfolio maintainer,
  # I want holdings valuation to use one consistent basis per date,
  # so that a booked split repairs — never distorts — the market value on
  # every storage basis, with exact Decimal expectations.
  describe "valuation across a split (quote-basis matrix)" do
    test "raw basis: a stale pre-split manual close values the post-split quantity correctly" do
      world = base_world(name: "VR World", cash_name: "VR Cash", depot_name: "VR Depot")
      security = create_security!(name: "VR Co", ticker: "VRR")
      buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-05])
      book_split!(security, ~D[2026-02-01], {10, 1})
      insert_quote!(security, ~D[2026-01-31], "110", "manual")

      valuation = Valuation.for_portfolio(world.portfolio.id)
      position = only_position(valuation)

      assert Decimal.equal?(position.quantity, Decimal.new("100"))
      assert Decimal.equal?(position.latest_price, Decimal.new("11"))
      assert Decimal.equal?(position.market_value, Decimal.new("1100"))
      assert position.price_source == :quote
      assert Decimal.equal?(valuation.total_value, Decimal.new("1100"))
    end

    test "provider basis: the back-adjusted mirror close applies without an extra factor" do
      world = base_world(name: "VP World", cash_name: "VP Cash", depot_name: "VP Depot")
      security = create_security!(name: "VP Co", ticker: "VPP")
      buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-05])
      book_split!(security, ~D[2026-02-01], {10, 1})
      insert_quote!(security, ~D[2026-01-31], "11", "coingecko")

      valuation = Valuation.for_portfolio(world.portfolio.id)
      position = only_position(valuation)

      assert Decimal.equal?(position.latest_price, Decimal.new("11"))
      assert Decimal.equal?(position.market_value, Decimal.new("1100"))
    end

    test "sequential splits compound in quantity and price so the value stays consistent" do
      world = base_world(name: "VS World", cash_name: "VS Cash", depot_name: "VS Depot")
      security = create_security!(name: "VS Co", ticker: "VSS")
      buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-05])
      book_split!(security, ~D[2026-02-01], {10, 1})
      book_split!(security, ~D[2026-03-01], {1, 2})
      insert_quote!(security, ~D[2026-01-31], "99", "manual")

      valuation = Valuation.for_portfolio(world.portfolio.id)
      position = only_position(valuation)

      # Quantity 10 x 10 / 2 = 50; price 99 / (10/2) = 19.8; value 990.
      assert Decimal.equal?(position.quantity, Decimal.new("50"))
      assert Decimal.equal?(position.latest_price, Decimal.new("19.8"))
      assert Decimal.equal?(position.market_value, Decimal.new("990"))
    end

    test "reverse split: the raw pre-split close multiplies up for the shrunken quantity" do
      world = base_world(name: "VV World", cash_name: "VV Cash", depot_name: "VV Depot")
      security = create_security!(name: "VV Co", ticker: "VVV")
      buy!(world, security, quantity: "9", price: "90", date: ~D[2026-01-05])
      book_split!(security, ~D[2026-02-01], {1, 3})
      insert_quote!(security, ~D[2026-01-31], "90", "manual")

      valuation = Valuation.for_portfolio(world.portfolio.id)
      position = only_position(valuation)

      assert Decimal.equal?(position.quantity, Decimal.new("3"))
      assert Decimal.equal?(position.latest_price, Decimal.new("270"))
      assert Decimal.equal?(position.market_value, Decimal.new("810"))
    end
  end

  # User story (ADR-0028 §2 trade-price-fallback era, issue #590):
  # As a maintainer holding a quote-less security through a split,
  # I want the latest-own-trade-price fallback divided by the cumulative
  # ratio of splits effective after the trade date,
  # so that the fallback never values the post-split quantity at the
  # pre-split as-traded price.
  test "trade-price fallback era: a pre-split trade price divides by the later ratio" do
    world = base_world(name: "TF World", cash_name: "TF Cash", depot_name: "TF Depot")
    security = create_security!(name: "TF Co", ticker: "TFF")
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-05])
    book_split!(security, ~D[2026-02-01], {10, 1})

    valuation = Valuation.for_portfolio(world.portfolio.id)
    position = only_position(valuation)

    assert position.price_source == :trade
    assert Decimal.equal?(position.quantity, Decimal.new("100"))
    assert Decimal.equal?(position.latest_price, Decimal.new("10"))
    assert Decimal.equal?(position.market_value, Decimal.new("1000"))

    # The global per-security view takes the same adjusted fallback.
    holdings = Valuation.holdings_by_security()
    assert Decimal.equal?(holdings[security.id].market_value, Decimal.new("1000"))
  end

  # User story (ADR-0028 §5 delete-the-event, issue #590):
  # As a maintainer who booked a wrong split across several portfolios,
  # I want deleting the whole fanned-out row group to restore every
  # portfolio's valuation exactly,
  # so that a mistaken booking is fully reversible (nothing was mutated).
  test "deleting the fanned-out group restores both portfolios' valuations exactly" do
    world_a = base_world(name: "VD A", cash_name: "VDA Cash", depot_name: "VDA Depot")
    world_b = base_world(name: "VD B", cash_name: "VDB Cash", depot_name: "VDB Depot")
    security = create_security!(name: "VD Co", ticker: "VDD")
    buy!(world_a, security, quantity: "10", price: "100", date: ~D[2026-01-05])
    buy!(world_b, security, quantity: "4", price: "100", date: ~D[2026-01-05])
    insert_quote!(security, ~D[2026-01-31], "110", "manual")

    baseline_a = Valuation.for_portfolio(world_a.portfolio.id)
    baseline_b = Valuation.for_portfolio(world_b.portfolio.id)
    assert Decimal.equal?(baseline_a.total_value, Decimal.new("1100"))
    assert Decimal.equal?(baseline_b.total_value, Decimal.new("440"))

    split_rows = book_split!(security, ~D[2026-02-01], {10, 1})
    assert length(split_rows) == 2

    # Booked: quantities x10, price /10 — totals unchanged by construction.
    split_a = Valuation.for_portfolio(world_a.portfolio.id)
    assert Decimal.equal?(only_position(split_a).quantity, Decimal.new("100"))
    assert Decimal.equal?(split_a.total_value, Decimal.new("1100"))

    for row <- split_rows do
      {:ok, _} = Ledger.delete_transaction(Actor.owner_ui(), row)
    end

    restored_a = Valuation.for_portfolio(world_a.portfolio.id)
    restored_b = Valuation.for_portfolio(world_b.portfolio.id)

    assert Decimal.equal?(only_position(restored_a).quantity, Decimal.new("10"))
    assert Decimal.equal?(only_position(restored_a).latest_price, Decimal.new("110"))
    assert Decimal.equal?(restored_a.total_value, Decimal.new("1100"))
    assert Decimal.equal?(only_position(restored_b).quantity, Decimal.new("4"))
    assert Decimal.equal?(restored_b.total_value, Decimal.new("440"))
  end
end
