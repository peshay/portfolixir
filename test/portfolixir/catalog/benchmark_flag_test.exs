defmodule Portfolixir.Catalog.BenchmarkFlagTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [create_security!: 1, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.DataQuality

  # User story (#572, ADR-0046 §1 — Sprint 11 Lane B step 1):
  # As a local portfolio maintainer who wants to compare the portfolio with an
  # index,
  # I want to flag a catalog security as a benchmark — an ETF standing in for
  # the index, fed by the existing quote sync,
  # so that the comparison has a price series without a new quote source, and
  # the flagged security is discoverable by its flag.
  #
  # Acceptance criteria:
  # - The flag is stored, castable from string keys (the API and MCP path) and
  #   atom keys alike, and off by default.
  # - The securities read lists by the flag in both directions and, without
  #   the option, lists every security.
  test "a benchmark security is flagged, listable by the flag, and excludable" do
    {:ok, bench} =
      Catalog.create_security(Actor.owner_ui(), %{
        "name" => "World Index ETF",
        "ticker_symbol" => "WRLD",
        "currency_code" => "EUR",
        "asset_class" => "etf",
        "is_benchmark" => true
      })

    held = create_security!(name: "Held Co", ticker: "HLD")

    assert bench.is_benchmark
    refute held.is_benchmark

    assert Enum.map(Catalog.list_securities(is_benchmark: true), & &1.id) == [bench.id]

    excluded = Catalog.list_securities(is_benchmark: false) |> Enum.map(& &1.id)
    assert held.id in excluded
    refute bench.id in excluded

    all = Catalog.list_securities() |> Enum.map(& &1.id)
    assert bench.id in all
    assert held.id in all

    {:ok, unflagged} = Catalog.update_security(Actor.owner_ui(), bench, %{is_benchmark: false})
    refute unflagged.is_benchmark
  end

  # User story (ADR-0046 §1):
  # As the operator,
  # I want the catalog-hygiene reminders to leave a benchmark alone — it is a
  # reference, not a holding — while the exchange-rate check still names it,
  # so that flagging an index ETF does not add a logo or quote nag, and a
  # missing rate path (which would break the comparison itself) still shows.
  test "the catalog-hygiene checks skip a benchmark; the FX check keeps it" do
    {:ok, bench} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Gold ETC",
        ticker_symbol: "GOLD",
        currency_code: "USD",
        asset_class: "etf",
        is_benchmark: true
      })

    plain = create_security!(name: "Plain Co", ticker: "PLN", currency: "USD")

    for id <- ["stale_quote", "missing_quote", "missing_logo"] do
      names = id |> DataQuality.list() |> Enum.map(& &1.security.name)
      assert "Plain Co" in names, id
      refute "Gold ETC" in names, id
      assert DataQuality.count(id) == length(names)
    end

    # Both priced in a currency with no stored hub rate: both are named.
    put_quote!(bench, Date.utc_today(), "180")
    put_quote!(plain, Date.utc_today(), "12")
    fx_names = "missing_fx" |> DataQuality.list() |> Enum.map(& &1.security.name)
    assert "Gold ETC" in fx_names
    assert "Plain Co" in fx_names
  end
end
