defmodule Portfolixir.Portfolios.ValuationViewHoldingsTest do
  @moduledoc """
  The per-security holdings of a bucket view (#1091's screen half, Sprint 19
  PR γ U7): `Valuation.holdings_by_security_for_view/2` is the view valuation
  (`Valuation.for_view/2`) grouped by security, in the shape
  `Valuation.holdings_by_security/1` gives the classification tree. Exact
  `Decimal` expectations; every name is invented.
  """
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, add_depot: 2, create_security!: 1, buy!: 3, deposit!: 4]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Portfolios.Valuation

  # User story (#1091, the screen half):
  # As a local portfolio maintainer reading the classification screen under
  # a view,
  # I want each security's quantity and value to be what the view holds,
  # so that "Positions" and "Value" agree with the view's category result
  # beside them.
  #
  # Acceptance criteria:
  # - Only the positions the view matches are counted; a security the view
  #   holds none of is absent, as an unheld security is from the global map.
  # - A security held in two depots of the view is one entry: the summed
  #   quantity and the summed EUR value.
  # - A position the view cannot value leaves its security's value nil.
  # - It says, as the view valuation does, when the view matches no accounts
  #   at all (review round: the screen names it as Wealth does).
  # - An unknown view is `{:error, :view_not_found}`.
  test "groups the view's positions by security, in EUR" do
    world = base_world(name: "Holdings #{System.unique_integer([:positive])}")
    second = add_depot(world.portfolio, depot_name: "Second", cash_name: "Second Cash")
    outside = add_depot(world.portfolio, depot_name: "Outside", cash_name: "Outside Cash")

    second = Map.put(second, :portfolio, world.portfolio)
    outside = Map.put(outside, :portfolio, world.portfolio)

    ash = create_security!(name: "Ashgrove Fund", ticker: nil)
    birch = create_security!(name: "Birchline AG", ticker: nil)
    cedar = create_security!(name: "Cedarpoint Ltd", ticker: nil)

    for w <- [world, second, outside], do: deposit!(w, "10000", ~D[2026-01-01], [])

    buy!(world, ash, quantity: "4", price: "10")
    buy!(second, ash, quantity: "6", price: "12")
    buy!(outside, birch, quantity: "3", price: "50")
    buy!(world, cedar, quantity: "2", price: "30")

    {:ok, bucket} =
      Buckets.create_bucket(Actor.owner_ui(), %{name: "In #{System.unique_integer([:positive])}"})

    {:ok, view} =
      Buckets.create_view(Actor.owner_ui(), %{
        name: "Holdings view #{System.unique_integer([:positive])}",
        include_all: false
      })

    :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, [bucket.id], [])
    :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), world.depot, [bucket.id])
    :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), second.depot, [bucket.id])

    prices = %{ash.id => Decimal.new("15"), birch.id => Decimal.new("55")}

    assert {:ok, %{holdings: holdings, matches_no_accounts: false}} =
             Valuation.holdings_by_security_for_view(view.id, prices: prices)

    # Birchline sits in the untagged depot only.
    refute Map.has_key?(holdings, birch.id)

    # Ashgrove: 4 + 6 units at 15 = 150 EUR.
    assert Decimal.equal?(holdings[ash.id].quantity, Decimal.new("10"))
    assert Decimal.equal?(holdings[ash.id].market_value, Decimal.new("150"))
    assert holdings[ash.id].valued

    # Cedarpoint has no quote and no override, but its own buy is a price
    # observation (#406): 2 at 30.
    assert Decimal.equal?(holdings[cedar.id].market_value, Decimal.new("60"))
    assert holdings[cedar.id].price_source == :trade

    # A view over a bucket no account carries matches nothing, and says so.
    {:ok, empty_bucket} =
      Buckets.create_bucket(Actor.owner_ui(), %{
        name: "Empty #{System.unique_integer([:positive])}"
      })

    {:ok, nothing} =
      Buckets.create_view(Actor.owner_ui(), %{
        name: "Nothing view #{System.unique_integer([:positive])}",
        include_all: false
      })

    :ok = Buckets.set_view_buckets(Actor.owner_ui(), nothing, [empty_bucket.id], [])

    assert {:ok, %{holdings: empty, matches_no_accounts: true}} =
             Valuation.holdings_by_security_for_view(nothing.id, prices: prices)

    assert empty == %{}

    assert {:error, :view_not_found} = Valuation.holdings_by_security_for_view(-1)
  end

  # Acceptance criteria (#1091): a security the view cannot value in EUR --
  # here held in a USD portfolio, with no stored rate -- keeps a nil value,
  # so the screen's category total is a dash rather than a smaller number.
  test "a position the view cannot value leaves its security unvalued" do
    world =
      base_world(
        name: "Unvalued #{System.unique_integer([:positive])}",
        currency: "USD",
        cash_name: "Dollar Cash",
        depot_name: "Dollar Depot"
      )

    dollar = create_security!(name: "Dunmore Inc", ticker: nil, currency: "USD")

    deposit!(world, "10000", ~D[2026-01-01], currency: "USD")
    buy!(world, dollar, quantity: "5", price: "20", currency: "USD")

    {:ok, view} =
      Buckets.create_view(Actor.owner_ui(), %{
        name: "Unvalued view #{System.unique_integer([:positive])}"
      })

    prices = %{dollar.id => Decimal.new("25")}

    assert {:ok, %{holdings: holdings}} =
             Valuation.holdings_by_security_for_view(view.id, prices: prices)

    assert %{market_value: nil, valued: false, unvalued_reason: :missing_fx} =
             holdings[dollar.id]

    assert Decimal.equal?(holdings[dollar.id].quantity, Decimal.new("5"))
  end
end
