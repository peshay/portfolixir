defmodule PortfolixirWeb.TransactionHistoryFormatLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Ledger
  alias Portfolixir.WorldFixtures

  # User story (#786, the review's D3 and D4; DESIGN.md → Data tables,
  # EXPERIENCE.md → Amendment 2026-09-12 → Value slot):
  # As a local portfolio maintainer reading the transactions history,
  # I want every number in my locale's spelling, right-aligned in tabular
  # numerals, and the money of each booking in the default columns,
  # so that a dividend row shows what was paid and not only the quantity.
  #
  # Acceptance criteria:
  # - Price 42,10 · quantity 0,05 · amount -1.263,00 EUR in DE; 42.10 / 0.05
  #   / -1,263.00 EUR in EN; the numeric cells carry the `num` class.
  # - "Betrag" / "Amount" is in the default columns, the currency as a
  #   suffix of the amount; `fields=` on the API is unchanged (API tests).
  defp seed do
    world = WorldFixtures.base_world()
    share = WorldFixtures.create_security!(name: "Share Co", ticker: "SHR")
    coin = WorldFixtures.create_security!(name: "Coin", ticker: "CN")
    WorldFixtures.deposit!(world, "10000", ~D[2026-02-01])
    WorldFixtures.buy!(world, share, quantity: "30", price: "42.1", date: ~D[2026-02-10])
    WorldFixtures.buy!(world, coin, quantity: "0.05", price: "60000", date: ~D[2026-02-11])

    {:ok, _dividend} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
        security_id: share.id,
        type: "dividend",
        date: ~D[2026-02-20],
        gross_amount: "50",
        currency_code: "EUR"
      })

    world
  end

  test "the history formats every number under the German locale and shows the signed amount",
       %{conn: conn} do
    seed()
    {:ok, view, _html} = live(conn, "/transactions?locale=de")
    rows = view |> element("#transaction-list tbody") |> render()

    assert rows =~ "42,10"
    assert rows =~ "0,05"
    assert rows =~ "60.000,00"
    assert rows =~ "-1.263,00"
    assert rows =~ "-3.000,00"
    assert rows =~ "50,00"
    refute rows =~ ">42.1<"
    refute rows =~ ">60000<"

    assert has_element?(view, "#transaction-list thead th", "Betrag")
    assert has_element?(view, "#transaction-list tbody td.num")
  end

  test "the history formats under the English locale, with the currency as a suffix",
       %{conn: conn} do
    seed()
    {:ok, view, _html} = live(conn, "/transactions")
    rows = view |> element("#transaction-list tbody") |> render()

    assert rows =~ "42.10"
    assert rows =~ "0.05"
    assert rows =~ "60,000.00"
    assert rows =~ "-1,263.00"
    assert rows =~ "50.00"

    assert has_element?(view, "#transaction-list thead th", "Amount")
    assert has_element?(view, "#transaction-list tbody td.num small", "EUR")
  end
end
