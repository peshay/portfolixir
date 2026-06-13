defmodule Portfolixir.Portfolios.AllocationExcludeTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.AllocationExcludeFixtures

  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias Portfolixir.Portfolios.Allocation
  alias Portfolixir.Portfolios.Valuation

  # User story:
  # As a local portfolio maintainer (and the LLM I connect over MCP),
  # I want to flag a security (e.g. Bitcoin held as a store of value) as
  # excluded from allocation targets,
  # so that it stays in my total value and performance but is left out of the
  # steering basis (the 100%) and the drift table, raising every other
  # category's actual percentage consistently.
  #
  # Acceptance criteria:
  # - Excluding a position removes it from the allocation steering basis: the
  #   other categories' actual percentages rise consistently.
  # - The total portfolio value (valuation) stays the same whether or not a
  #   position is excluded — the flag only affects the allocation view.
  # - The excluded value appears in a separately labeled `excluded` block.

  defp create_security!(name, ticker, asset_class) do
    {:ok, security} =
      Catalog.create_security(%{
        name: name,
        ticker_symbol: ticker,
        currency_code: "EUR",
        asset_class: asset_class
      })

    security
  end

  defp fetch_category(allocation, category_id) do
    Enum.find(allocation.categories, &(&1.category_id == category_id))
  end

  # Seeds the equity + Bitcoin positions (600 EUR equity, 400 EUR Bitcoin) used
  # by every test here and returns the world plus the two securities and the
  # price map keyed by their ids.
  defp seed_positions do
    world = exclude_world()
    %{classification: classification, equities: equities, crypto: crypto} = world

    equity = create_security!("Core Equity", "CORE", "equity")
    bitcoin = create_security!("Bitcoin", "BTC", "crypto")

    {:ok, _} = Classifications.assign_security(equity.id, classification.id, equities.id)
    {:ok, _} = Classifications.assign_security(bitcoin.id, classification.id, crypto.id)

    # Fund the cash account so the buys leave it at zero: counting cash is 0, so
    # the allocation's basis here is the securities value alone (the cash-in-basis
    # behaviour is exercised in AllocationTest). See issue #335.
    deposit!(world, "1000")

    # 600 EUR equity + 400 EUR Bitcoin = 1000 EUR valued positions.
    buy!(world, equity.id, "6", "100")
    buy!(world, bitcoin.id, "4", "100")

    prices = %{equity.id => Decimal.new("100"), bitcoin.id => Decimal.new("100")}

    %{world: world, equity: equity, bitcoin: bitcoin, prices: prices}
  end

  test "excludes a flagged Bitcoin position from the steering basis while keeping the total" do
    %{world: world, bitcoin: bitcoin, prices: prices} = seed_positions()
    %{classification: classification, equities: equities, crypto: crypto} = world
    opts = [prices: prices]

    {:ok, before} = Allocation.for_portfolio(world.portfolio.id, classification.id, opts)

    # Before exclusion: basis is the full 1000, equity is 60%, crypto 40%.
    assert Decimal.equal?(before.total_value, Decimal.new("1000"))
    assert Decimal.equal?(fetch_category(before, equities.id).actual_weight, Decimal.new("0.6"))
    assert Decimal.equal?(fetch_category(before, crypto.id).actual_weight, Decimal.new("0.4"))
    assert before.excluded == nil

    {:ok, _} = Catalog.update_security(bitcoin, %{excluded_from_allocation_targets: true})

    {:ok, after_excl} = Allocation.for_portfolio(world.portfolio.id, classification.id, opts)

    # Steering basis drops to 600 (Bitcoin out); equity now the whole 100%.
    assert Decimal.equal?(after_excl.total_value, Decimal.new("600"))

    equity_row = fetch_category(after_excl, equities.id)
    assert Decimal.equal?(equity_row.actual_weight, Decimal.new("1"))

    # Crypto category no longer carries a steered position (its only holding was
    # the excluded Bitcoin), so it falls out of the basis entirely.
    assert fetch_category(after_excl, crypto.id) == nil

    # The excluded value surfaces in its own labeled block, not dropped.
    assert Decimal.equal?(after_excl.excluded.market_value, Decimal.new("400"))
    [excluded_position] = after_excl.excluded.positions
    assert excluded_position.security_id == bitcoin.id
    assert Decimal.equal?(excluded_position.market_value, Decimal.new("400"))

    # The valuation total is identical whether or not the flag is set.
    valuation = Valuation.for_portfolio(world.portfolio.id, prices: prices)
    assert Decimal.equal?(valuation.total_value, Decimal.new("1000"))
  end

  test "the exclusion flag does not change the valuation total or performance basis" do
    %{world: world, bitcoin: bitcoin, prices: prices} = seed_positions()

    valuation_before = Valuation.for_portfolio(world.portfolio.id, prices: prices)

    {:ok, _} = Catalog.update_security(bitcoin, %{excluded_from_allocation_targets: true})

    valuation_after = Valuation.for_portfolio(world.portfolio.id, prices: prices)

    assert Decimal.equal?(valuation_before.total_value, valuation_after.total_value)
    assert Decimal.equal?(valuation_before.total_with_cash, valuation_after.total_with_cash)
    assert Decimal.equal?(valuation_before.total_cash, valuation_after.total_cash)
  end
end
