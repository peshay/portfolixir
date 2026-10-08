defmodule PortfolixirWeb.CrossCurrencyRoundTripLiveTest do
  # Sprint 20's D-1 criterion 2, round trip 4 (#1108; the ADR-0015 amendment
  # of 2026-10-07, identity 1): the cross-currency trade reads identity 1's
  # figures on the security's Trades tab and on the Trades facet, in the
  # German interface. Synthetic figures only.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, create_security!: 1, cross_trade!: 3, deposit!: 3]

  alias Portfolixir.Fx

  defp de_conn(conn), do: Plug.Test.put_req_cookie(conn, "portfolixir_locale", "de")

  defp text(nodes),
    do: nodes |> Floki.text(sep: " ") |> String.replace(~r/\s+/, " ") |> String.trim()

  # Buy 10 at 100 USD settled 800,00 EUR, fees 5,00 and taxes 1,00 EUR (cash
  # 806,00); sell 10 at 120 USD settled 960,00 EUR, fees 3,00 EUR (cash
  # 957,00). 1 EUR = 1,25 USD on both dates.
  defp seed! do
    world = base_world(name: "Runde Vier", cash_name: "Girokonto", depot_name: "Depot")
    deposit!(world, "2000", ~D[2025-03-03])
    fund = create_security!(name: "Dollar Rundfonds", ticker: "DRF", currency: "USD")

    {:ok, _} =
      [~D[2025-04-01], ~D[2025-05-02]]
      |> Enum.map(fn date ->
        %{base_currency: "EUR", quote_currency: "USD", date: date, rate: "1.25", source: "manual"}
      end)
      |> Fx.upsert_many()

    cross_trade!(world, fund,
      quantity: "10",
      price: "100",
      settled: "800.00",
      fees: "5.00",
      taxes: "1.00",
      gross: "806.00",
      date: ~D[2025-04-01]
    )

    cross_trade!(world, fund,
      type: "sell",
      quantity: "10",
      price: "120",
      settled: "960.00",
      fees: "3.00",
      gross: "957.00",
      date: ~D[2025-05-02]
    )

    fund
  end

  # User story (#1108; D-1 criterion 2, round trip 4):
  # As a switcher who bought and sold a USD security through my EUR account,
  # I want the security's Trades tab and the Trades facet to read the round
  # trip in one currency each,
  # so that the facet's result is the 151,00 EUR the round trip moved.
  #
  # Acceptance criteria:
  # - The Trades tab's closed trade reads its realised P&L as +188,75 (USD).
  # - The Trades facet's realised total reads +151,00 EUR.
  test "round trip 4: the cross-currency trade reads 151,00 EUR", %{conn: conn} do
    fund = seed!()

    {:ok, tab, _html} = live(de_conn(conn), "/securities/#{fund.id}?tab=trades")

    [row] =
      tab
      |> render()
      |> Floki.parse_document!()
      |> Floki.find("#detail-closed-trades-table tbody tr")

    assert text(Floki.find(row, "td:nth-child(8)")) == "+188,75"

    {:ok, facet, _html} = live(de_conn(conn), "/cashflow?tab=realized")

    total =
      facet
      |> render()
      |> Floki.parse_document!()
      |> Floki.find("#realized-figures [data-role='realized-total']")
      |> text()

    assert total =~ "+151,00"
    assert total =~ "EUR"
  end
end
