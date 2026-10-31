defmodule PortfolixirWeb.TransactionHistorySignPriceTest do
  # Sprint 21 γ3 (board 03 `ux-design-2026-10-09/03-history-drawer`, pick
  # N10 A): the transaction history's Betrag carries its direction as an
  # explicit sign, "+" on every inflow and no colour (#1147) — in the table,
  # the phone row and the delete dialog's box, which repeats the row.
  #
  # Every name, figure and date is synthetic.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Ledger
  alias Portfolixir.WorldFixtures

  defp text(nodes),
    do: nodes |> Floki.text(sep: " ") |> String.replace(~r/\s+/u, " ") |> String.trim()

  defp book!(attrs) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), Map.put_new(attrs, :currency_code, "EUR"))

    tx
  end

  defp cell(view, tx, role) do
    view
    |> element("#transaction-list tr[data-transaction='#{tx.id}'] td[data-role='#{role}']")
    |> render()
    |> Floki.parse_fragment!()
  end

  defp phone(view, tx, role) do
    view
    |> element("#transaction-phone-rows li[data-transaction='#{tx.id}'] [data-role='#{role}']")
    |> render()
    |> Floki.parse_fragment!()
    |> text()
  end

  defp delete_box(view, tx) do
    view |> element("#tx-kebab-#{tx.id}") |> render_click()
    view |> element("#tx-delete-#{tx.id}") |> render_click()

    figures =
      view
      |> element("#booking-delete-subject .phone-row__figures")
      |> render()
      |> Floki.parse_fragment!()

    view |> element("[data-role='booking-delete-cancel']") |> render_click()

    {figures |> Floki.find(".phone-row__figure") |> text(),
     figures |> Floki.find(".phone-row__figure2") |> text()}
  end

  # The board's N10 October: a tax refund, a buy at 0,00, a dividend, a fee,
  # a buy, a sale, a transfer to the savings account and a deposit on
  # Test-Cash, and a set balance on Tagesgeld in September.
  defp october do
    world =
      WorldFixtures.base_world(name: "Muster", cash_name: "Test-Cash", depot_name: "Depot Muster")

    savings =
      WorldFixtures.add_depot(world.portfolio, cash_name: "Tagesgeld", depot_name: "Depot 2")

    wrenfield = WorldFixtures.create_security!(name: "Wrenfield Gardens AG", ticker: "WGA")
    larkspur = WorldFixtures.create_security!(name: "Larkspur Rail AG", ticker: "LRA")

    {:ok, level} =
      Ledger.set_cash_balance(Actor.owner_ui(), savings.cash, %{
        date: ~D[2026-09-30],
        amount: "3250"
      })

    deposit = WorldFixtures.deposit!(world, "1500", ~D[2026-10-01])

    transfer =
      book!(%{
        type: "cash_transfer",
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        counter_cash_account_id: savings.cash.id,
        gross_amount: "200",
        date: ~D[2026-10-01]
      })

    WorldFixtures.buy!(world, larkspur, quantity: "20", price: "40", date: ~D[2026-09-01])

    sale =
      WorldFixtures.sell!(world, larkspur,
        quantity: "10",
        price: "41.25",
        fees: "9.90",
        date: ~D[2026-10-01]
      )

    buy =
      WorldFixtures.buy!(world, wrenfield,
        quantity: "20",
        price: "48.20",
        fees: "0.90",
        date: ~D[2026-10-02]
      )

    fee =
      book!(%{
        type: "fee",
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        gross_amount: "4.90",
        date: ~D[2026-10-05]
      })

    dividend =
      book!(%{
        type: "dividend",
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        security_id: larkspur.id,
        gross_amount: "12.50",
        date: ~D[2026-10-06]
      })

    zero_buy =
      WorldFixtures.buy!(world, larkspur, quantity: "12", price: "0", date: ~D[2026-10-07])

    refund =
      book!(%{
        type: "tax_refund",
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        gross_amount: "12.40",
        date: ~D[2026-10-08]
      })

    delivery =
      book!(%{
        type: "outbound_delivery",
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        security_id: larkspur.id,
        quantity: "2",
        price: "41",
        date: ~D[2026-10-08]
      })

    %{
      world: world,
      savings: savings,
      delivery: delivery,
      level: level,
      deposit: deposit,
      transfer: transfer,
      sale: sale,
      buy: buy,
      fee: fee,
      dividend: dividend,
      zero_buy: zero_buy,
      refund: refund
    }
  end

  # User story (#1147, Sprint 21 γ3; board 03, pick N10 A):
  # As the operator reading my transaction history,
  # I want every inflow to carry an explicit "+" beside the outflows' "-",
  # with no colour,
  # so that a tax refund and a fee do not differ by one hyphen and the
  # direction reads in text, in forced colours and to a screen reader alike,
  # without a buy reading as a loss.
  #
  # Acceptance criteria:
  # - The Betrag cell reads "+12,40 EUR" (tax refund), "+12,50 EUR"
  #   (dividend), "+402,60 EUR" (sale net of its fee), "+1.500,00 EUR"
  #   (deposit), "-4,90 EUR" (fee), "-964,90 EUR" (buy with its fee) and
  #   "-200,00 EUR" (the transfer, from its sender).
  # - A buy at 0,00 reads "0,00 EUR", with no sign; the set balance is a
  #   level and reads "3.250,00 EUR", with no sign; an outbound delivery
  #   moves no cash, so no account sees a direction, and it keeps its bare
  #   figure "82,00 EUR".
  # - No amount cell and no phone amount carries a gain/loss colour class
  #   (`is-positive`, `is-negative`).
  # - The phone row's amount and the delete dialog's box read the same
  #   signed figures.
  # - With the chips selecting the transfer's receiving account alone, the
  #   transfer reads "+200,00 EUR".
  test "the Betrag signs every flow, inflows with a +, and colours none", %{conn: conn} do
    o = october()

    {:ok, view, _html} = live(conn, "/transactions?locale=de")

    expected = [
      {o.refund, "+12,40 EUR"},
      {o.dividend, "+12,50 EUR"},
      {o.sale, "+402,60 EUR"},
      {o.deposit, "+1.500,00 EUR"},
      {o.fee, "-4,90 EUR"},
      {o.buy, "-964,90 EUR"},
      {o.transfer, "-200,00 EUR"},
      {o.zero_buy, "0,00 EUR"},
      {o.level, "3.250,00 EUR"},
      {o.delivery, "82,00 EUR"}
    ]

    for {tx, figure} <- expected do
      amount = cell(view, tx, "amount")
      assert text(amount) == figure, "#{tx.type}: #{text(amount)}"
      assert phone(view, tx, "phone-amount") == figure

      # No gain/loss colour: the cell is a plain figure cell.
      assert Floki.attribute(amount, "class") == ["num"]
      assert Floki.find(amount, ".is-positive, .is-negative, .is-flat") == []
    end

    refute has_element?(view, "#transaction-phone-rows [data-role='phone-amount'].is-positive")
    refute has_element?(view, "#transaction-phone-rows [data-role='phone-amount'].is-negative")

    assert {"+1.500,00 EUR", _size} = delete_box(view, o.deposit)
    assert {"-4,90 EUR", _size} = delete_box(view, o.fee)
    assert {"0,00 EUR", _size} = delete_box(view, o.zero_buy)

    view
    |> element(
      "#transaction-chips [phx-value-family='account'][phx-value-option='#{o.savings.cash.id}']"
    )
    |> render_click()

    assert text(cell(view, o.transfer, "amount")) == "+200,00 EUR"
    assert phone(view, o.transfer, "phone-amount") == "+200,00 EUR"
  end

  # User story (#1147, Sprint 21 γ3; board 03, pick N10 A):
  # As the operator reading the history in English,
  # I want the same explicit sign under the English separators,
  # so that the direction does not depend on the locale.
  #
  # Acceptance criteria:
  # - The deposit reads "+1,500.00 EUR" and the fee "-4.90 EUR".
  test "the sign is the same under the English locale", %{conn: conn} do
    o = october()

    {:ok, view, _html} = live(conn, "/transactions?locale=en")

    assert text(cell(view, o.deposit, "amount")) == "+1,500.00 EUR"
    assert text(cell(view, o.fee, "amount")) == "-4.90 EUR"
  end
end
