defmodule PortfolixirWeb.SecuritiesTransactionsGrossTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios.Income
  alias Portfolixir.WorldFixtures

  defp book!(world, security, type, cash, tax, date) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        security_id: security.id,
        type: type,
        date: date,
        gross_amount: cash,
        fees: "0",
        taxes: tax,
        currency_code: "EUR"
      })

    tx
  end

  defp gross_cell(view, tx) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find(
      ~s(#detail-tab-panel-transactions tr[data-tx-id="#{tx.id}"] td[data-role="gross"])
    )
    |> Floki.text()
    |> String.trim()
  end

  # User story (#1331; Sprint 22 plan D-6, board 02 ②):
  # As a local portfolio maintainer,
  # I want a dividend's Brutto on the security's Transaktionen tab to be the
  # gross Income reads — the cash credited plus the tax withheld —
  # so that one booking has one gross figure on every screen.
  #
  # Acceptance criteria:
  # - A dividend of 7.50 cash with 1.98 tax withheld reads Brutto 9.48.
  # - An interest booking on the security (a bond's coupon) reads the same
  #   way: 10.00 cash with 2.50 tax reads 12.50 (#1309's rule).
  # - The figure is Income's own: its per-transaction gross for the booking.
  test "a dividend's and a coupon's Brutto are the cash plus the withheld tax",
       %{conn: conn} do
    world = WorldFixtures.base_world(name: "Gross World")
    security = WorldFixtures.create_security!(name: "Wrenfield Example AG", ticker: "WRG")

    dividend = book!(world, security, "dividend", "7.50", "1.98", ~D[2026-03-12])
    coupon = book!(world, security, "interest", "10.00", "2.50", ~D[2026-04-01])

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=transactions")

    assert gross_cell(view, dividend) == "9.48"
    assert gross_cell(view, coupon) == "12.50"

    assert Decimal.equal?(Income.gross_of(dividend), Decimal.new("9.48"))
    assert Decimal.equal?(Income.gross_of(coupon), Decimal.new("12.50"))
  end
end
