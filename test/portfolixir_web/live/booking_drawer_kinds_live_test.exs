defmodule PortfolixirWeb.BookingDrawerKindsLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Ledger

  setup do
    world = base_world(name: "Drawer Kinds World", cash_name: "DK Cash", depot_name: "DK Depot")
    security = create_security!(name: "Synthetic Drawer Kinds", ticker: "SDK")
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-05])
    %{world: world, security: security}
  end

  # User story (security review 2026-10-12, K10):
  # As the operator booking a trade in the drawer,
  # I want the drawer to book only the kinds it offers, buy and sell,
  # so that a split, which re-bases a security's quotes for every portfolio,
  # is never booked past the split flow's checks.
  #
  # Acceptance criteria:
  # - The drawer's kind list offers buy and sell, and nothing else.
  # - A save carrying a split stores nothing and shows a refusal; so does a
  #   save carrying another kind the drawer does not offer.
  test "the drawer books buy and sell only", %{conn: conn, world: world, security: security} do
    {:ok, view, _html} = live(conn, "/transactions")
    render_click(view, "open_booking", %{})

    offered =
      view
      |> element("#transaction-form select[name='transaction[type]']")
      |> render()
      |> then(&Regex.scan(~r/<option[^>]*value="([^"]+)"/, &1, capture: :all_but_first))
      |> List.flatten()

    assert offered == ["buy", "sell"]

    before = length(Ledger.list_transactions())

    html =
      render_submit(view, "save_transaction", %{
        "transaction" => %{
          "type" => "split",
          "portfolio_id" => to_string(world.portfolio.id),
          "security_id" => to_string(security.id),
          "date" => "2026-02-01",
          "currency_code" => "EUR",
          "split_ratio_numerator" => "3",
          "split_ratio_denominator" => "1"
        }
      })

    assert length(Ledger.list_transactions()) == before
    refute Enum.any?(Ledger.list_transactions(), &(&1.type == "split"))
    refute html =~ "Transaction recorded"
    assert has_element?(view, "#booking-drawer")

    render_submit(view, "save_transaction", %{
      "transaction" => %{
        "type" => "deposit",
        "portfolio_id" => to_string(world.portfolio.id),
        "cash_account_id" => to_string(world.cash.id),
        "date" => "2026-02-01",
        "currency_code" => "EUR",
        "gross_amount" => "100"
      }
    })

    assert length(Ledger.list_transactions()) == before
  end
end
