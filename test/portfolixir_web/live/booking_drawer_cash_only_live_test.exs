defmodule PortfolixirWeb.BookingDrawerCashOnlyLiveTest do
  # Sprint 22 U1 (#1299; board 03 of 2026-11-01, section 4). Every name,
  # figure and date is synthetic.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  # User story (#1299, Sprint 22 U1; board 03, section 4):
  # As the operator of an instance that holds cash accounts and no depot,
  # I want "Record transaction" in the history's head to open the drawer on
  # the cash form,
  # so that a deposit, a removal, interest, a fee, a tax or a tax refund is
  # booked on a screen, not over the API.
  #
  # Acceptance criteria:
  # - With one cash account and no depot, the control shows and opens the
  #   drawer on the cash form, its kind "Deposit".
  # - The kind list holds the cash kinds a cash account books alone, in the
  #   drawer's order: interest, deposit, removal, fee, tax, tax refund. Buy,
  #   sell and dividend need a depot and are absent.
  # - The setup line says what needs a depot instead of claiming every
  #   booking does, keeps its link, and is German where the page is.
  # - Saving books the deposit on the cash account in its currency:
  #   0.00 → 250.00.
  # - With no cash account and no depot, the control stays absent.

  setup do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Cash Only",
        base_currency_code: "EUR"
      })

    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Rücklage",
        currency_code: "EUR",
        liquidity_role: "free_cash"
      })

    %{portfolio: portfolio, cash: cash}
  end

  defp kinds(view) do
    view
    |> element("#booking-drawer select[name='transaction[type]']")
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.attribute("option", "value")
  end

  test "the control opens the drawer on the cash form with the cash kinds only", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/transactions")

    assert has_element?(view, "#transaction-list-panel .section-head #open-booking")
    view |> element("#open-booking") |> render_click()

    assert has_element?(view, "#booking-drawer select[name='transaction[cash_account_id]']")
    refute has_element?(view, "#booking-drawer select[name='transaction[securities_account_id]']")
    assert has_element?(view, "#booking-drawer option[value='deposit'][selected]")
    assert kinds(view) == ~w(interest deposit removal fee tax tax_refund)
  end

  test "the setup line says what needs a depot, in English and German", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/transactions")

    assert has_element?(
             view,
             "#transaction-setup-empty p",
             "Buys and sells need a depot. Deposits, removals, interest, fees, taxes and tax refunds book on a cash account alone."
           )

    assert has_element?(view, "#transaction-setup-empty a[href='/portfolios']")

    {:ok, de, _html} = live(conn, "/transactions?locale=de")

    assert has_element?(
             de,
             "#transaction-setup-empty p",
             "Käufe und Verkäufe brauchen ein Depot. Einlagen, Entnahmen, Zinsen, Gebühren, Steuern und Steuererstattungen bucht ein Verrechnungskonto allein."
           )

    assert has_element?(de, "#open-booking", "Transaktion erfassen")
  end

  test "a deposit books on the cash account in its currency", %{
    conn: conn,
    portfolio: portfolio,
    cash: cash
  } do
    {:ok, view, _html} = live(conn, "/transactions")
    view |> element("#open-booking") |> render_click()

    view
    |> element("#transaction-form")
    |> render_submit(%{
      "transaction" => %{
        "type" => "deposit",
        "date" => "2026-10-15",
        "cash_account_id" => to_string(cash.id),
        "gross_amount" => "250.00"
      }
    })

    refute has_element?(view, "#booking-drawer")

    assert [deposit] = Ledger.list_transactions()
    assert deposit.type == "deposit"
    assert deposit.cash_account_id == cash.id
    assert deposit.currency_code == "EUR"
    assert Decimal.equal?(deposit.gross_amount, Decimal.new("250.00"))

    balance = Ledger.cash_balances(portfolio_id: portfolio.id) |> Map.fetch!(cash.id)
    assert Decimal.equal?(balance, Decimal.new("250.00"))
  end

  test "with no cash account and no depot the control stays absent", %{conn: conn, cash: cash} do
    {:ok, _} = Portfolios.delete_cash_account(Actor.owner_ui(), cash)
    {:ok, view, _html} = live(conn, "/transactions")

    refute has_element?(view, "#open-booking")
    assert has_element?(view, "#transaction-setup-empty a[href='/portfolios']")
  end
end
