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

  # User story (security review 2026-10-12, K10; widened by Sprint 21 α6,
  # #1052 and #1206, the plan's D-6 and the amendment's D-5):
  # As the operator booking in the drawer,
  # I want the drawer to book only the kinds it offers — buy and sell, and
  # since α6 the seven one-amount cash kinds — and never a split,
  # so that a split, which re-bases a security's quotes for every portfolio,
  # is never booked past the split flow's checks, and a two-legged booking
  # is never booked by a form that carries one amount.
  #
  # Acceptance criteria:
  # - The drawer's kind list offers buy, sell, dividend, interest, deposit,
  #   removal, fee, tax and tax refund, in that order, and nothing else: no
  #   split (D-5 keeps K10's list without one).
  # - A save carrying a split stores nothing and shows a refusal; so does a
  #   save carrying another kind the drawer does not offer (a cash
  #   transfer).
  test "the drawer books the kinds it offers and never a split",
       %{conn: conn, world: world, security: security} do
    {:ok, view, _html} = live(conn, "/transactions")
    render_click(view, "open_booking", %{})

    offered =
      view
      |> element("#transaction-form select[name='transaction[type]']")
      |> render()
      |> then(&Regex.scan(~r/<option[^>]*value="([^"]+)"/, &1, capture: :all_but_first))
      |> List.flatten()

    assert offered == [
             "buy",
             "sell",
             "dividend",
             "interest",
             "deposit",
             "removal",
             "fee",
             "tax",
             "tax_refund"
           ]

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
        "type" => "cash_transfer",
        "portfolio_id" => to_string(world.portfolio.id),
        "cash_account_id" => to_string(world.cash.id),
        "counter_cash_account_id" => to_string(world.cash.id),
        "date" => "2026-02-01",
        "currency_code" => "EUR",
        "gross_amount" => "100"
      }
    })

    assert length(Ledger.list_transactions()) == before
  end
end
