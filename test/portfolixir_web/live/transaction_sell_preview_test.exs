defmodule PortfolixirWeb.TransactionSellPreviewTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Ledger

  # Synthetic figures only.

  defp world do
    world = base_world(name: "Sell Form", cash_name: "SF Cash", depot_name: "SF Depot")
    security = create_security!(name: "SF Equity", ticker: "SFE", asset_class: "equity")
    Map.put(world, :security, security)
  end

  defp change_form(view, params) do
    base = %{
      "type" => "sell",
      "date" => "2026-06-01",
      "securities_account_id" => "",
      "security_id" => "",
      "quantity" => "",
      "price" => "",
      "fees" => "0",
      "taxes" => "0",
      "notes" => ""
    }

    view
    |> element("#transaction-form")
    |> render_change(%{"transaction" => Map.merge(base, params)})
  end

  # User story (issue #620):
  # As a local portfolio maintainer entering a sell on the transaction form,
  # I want to see which FIFO purchase tranches the sale would consume and
  # the resulting gross gain, right where the sale is decided,
  # so that I can judge the sale before booking it.
  #
  # Acceptance criteria:
  # - With two buys (10 @ 100, 10 @ 120) and a sell of 15 @ 150, the panel
  #   lists both tranches (10 and 5 consumed) with per-tranche gross gains
  #   +500.00 and +150.00 and the total +650.00.
  # - The figure is labelled a gross gain with an explanatory tooltip and
  #   carries no tax wording.
  test "entering a sell shows the consumed FIFO tranches and the gross gain", %{conn: conn} do
    w = world()
    buy!(w, w.security, quantity: "10", price: "100", date: ~D[2026-01-02])
    buy!(w, w.security, quantity: "10", price: "120", date: ~D[2026-02-02])

    {:ok, view, _html} = live(conn, "/transactions")

    html =
      change_form(view, %{
        "securities_account_id" => to_string(w.depot.id),
        "security_id" => to_string(w.security.id),
        "quantity" => "15",
        "price" => "150"
      })

    assert html =~ "sell-lot-preview"
    assert html =~ "2026-01-02"
    assert html =~ "2026-02-02"
    assert html =~ "+500.00"
    assert html =~ "+150.00"
    assert html =~ "+650.00"
    assert html =~ "Gross gain"

    # The tooltip explains what the figure is and is not — and never as a
    # tax figure (ADR-0031 correction 1).
    assert html =~ "before fees"

    preview_html =
      case Regex.run(~r/<section id="sell-lot-preview".*?<\/section>/s, html) do
        [section] -> section
        _ -> html
      end

    refute preview_html =~ ~r/tax/i
    refute preview_html =~ ~r/steuer/i
  end

  # User story (no preview outside a sell):
  # As a maintainer entering a buy,
  # I want no lot-consumption panel,
  # so that the preview appears only where a sale is decided.
  test "a buy shows no lot-consumption preview", %{conn: conn} do
    w = world()
    buy!(w, w.security, quantity: "10", price: "100", date: ~D[2026-01-02])

    {:ok, view, _html} = live(conn, "/transactions")

    html =
      change_form(view, %{
        "type" => "buy",
        "securities_account_id" => to_string(w.depot.id),
        "security_id" => to_string(w.security.id),
        "quantity" => "5",
        "price" => "110"
      })

    refute html =~ "sell-lot-preview"
  end

  # User story (price fallback + comma input):
  # As a German-locale maintainer typing "7,5" without a price yet,
  # I want the preview priced at the latest stored close,
  # so that the tranche view appears as soon as security and quantity exist.
  test "the preview prices at the latest close and accepts a comma quantity", %{conn: conn} do
    w = world()
    buy!(w, w.security, quantity: "10", price: "100", date: ~D[2026-01-02])
    put_quote!(w.security, ~D[2026-05-01], "130")

    {:ok, view, _html} = live(conn, "/transactions")

    html =
      change_form(view, %{
        "securities_account_id" => to_string(w.depot.id),
        "security_id" => to_string(w.security.id),
        "quantity" => "7,5"
      })

    assert html =~ "sell-lot-preview"
    # 7.5 x (130 - 100) = 225.00, at the latest stored price.
    assert html =~ "+225.00"
    assert html =~ "latest stored price"
  end

  # User story (over-sell warning):
  # As a maintainer entering more quantity than the open lots cover,
  # I want the shortfall named in the preview,
  # so that an over-sell is visible before booking.
  test "an over-sell names the uncovered shortfall", %{conn: conn} do
    w = world()
    buy!(w, w.security, quantity: "10", price: "100", date: ~D[2026-01-02])

    {:ok, view, _html} = live(conn, "/transactions")

    html =
      change_form(view, %{
        "securities_account_id" => to_string(w.depot.id),
        "security_id" => to_string(w.security.id),
        "quantity" => "12",
        "price" => "150"
      })

    assert html =~ "not covered by open lots"
  end

  # User story (#569/#620 agreement):
  # As a maintainer selling an imported cross-currency position,
  # I want the preview to show the same price/currency decomposition as the
  # holdings and lot surfaces — or an honest dash,
  # so that the two surfaces cannot disagree.
  test "a cross-currency tranche shows the ADR-0033 decomposition", %{conn: conn} do
    w = base_world(name: "SF FX", cash_name: "SFF Cash", depot_name: "SFF Depot")
    security = create_security!(name: "SF US Equity", ticker: "SFU", currency: "USD")

    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: w.portfolio.id,
        securities_account_id: w.depot.id,
        cash_account_id: w.cash.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-01-15],
        quantity: "10",
        price: "80.00",
        currency_code: "EUR",
        security_amount: "1000.00",
        settlement_amount: "800.00",
        settlement_fx_rate: "0.80"
      })

    # Current hub rate 1 EUR = 1.25 USD (0.80 EUR/USD).
    {:ok, _} =
      Portfolixir.Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2026-06-01],
          rate: "1.25",
          source: "manual"
        }
      ])

    {:ok, view, _html} = live(conn, "/transactions")

    html =
      change_form(view, %{
        "securities_account_id" => to_string(w.depot.id),
        "security_id" => to_string(security.id),
        "quantity" => "10",
        "price" => "110"
      })

    assert html =~ "sell-lot-preview"
    # Native gross gain 10 x (110 - 100) = +100.00 USD; decomposition at
    # 0.80: price (1100-1000) x 0.8 = +80.00, currency 1000 x 0.8 - 800 = 0.
    assert html =~ "+100.00"
    assert html =~ "Price return"
    assert html =~ "Currency return"
    assert html =~ "+80.00"
  end
end
