defmodule PortfolixirWeb.TransactionHistoryCashMovedTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo
  alias Portfolixir.WorldFixtures

  # Synthetic figures only: one EUR account "Test-Cash", one EUR security.
  #
  #   deposit   01.10.2026                         +3.000,00
  #   API buy   02.10.2026  20 × 48,20, fee 1,00   −965,00 (no gross amount)
  #   drawer    05.10.2026  10 × 50,00, fee 1,00   −501,00 (no gross amount)
  #   zero buy  06.10.2026   1 ×  0,00               0,00
  #   API sell  07.10.2026   5 × 60,00, fee 1,00, taxes 0,50   +298,50
  #
  # The balance falls from 3.000,00 to 1.832,50, by −1.167,50, which is the
  # sum of the four trade rows' Betrag.
  defp seed do
    world =
      WorldFixtures.base_world(
        name: "Cash Moved",
        cash_name: "Test-Cash",
        depot_name: "Depot Muster"
      )

    share = WorldFixtures.create_security!(name: "Wrenfield Gardens AG", ticker: "WGA")
    deposit = WorldFixtures.deposit!(world, "3000", ~D[2026-10-01])

    book = fn attrs ->
      {:ok, tx} =
        Ledger.create_transaction(
          Actor.owner_ui(),
          Map.merge(
            %{
              portfolio_id: world.portfolio.id,
              securities_account_id: world.depot.id,
              cash_account_id: world.cash.id,
              security_id: share.id,
              currency_code: "EUR"
            },
            attrs
          )
        )

      tx
    end

    # The route `POST /api/v1/transactions` writes through: no gross amount.
    api_buy =
      book.(%{
        type: "buy",
        date: ~D[2026-10-02],
        quantity: "20",
        price: "48.20",
        fees: "1.00",
        taxes: "0"
      })

    zero_buy =
      book.(%{
        type: "buy",
        date: ~D[2026-10-06],
        quantity: "1",
        price: "0",
        fees: "0",
        taxes: "0"
      })

    sell =
      book.(%{
        type: "sell",
        date: ~D[2026-10-07],
        quantity: "5",
        price: "60",
        fees: "1.00",
        taxes: "0.50"
      })

    %{
      world: world,
      share: share,
      deposit: deposit,
      api_buy: api_buy,
      zero_buy: zero_buy,
      sell: sell
    }
  end

  defp book_through_drawer(conn, s) do
    {:ok, view, _html} = live(conn, "/transactions?locale=de")
    view |> element("#open-booking") |> render_click()

    view
    |> element("#transaction-form")
    |> render_submit(%{
      "transaction" => %{
        "type" => "buy",
        "date" => "2026-10-05",
        "securities_account_id" => to_string(s.world.depot.id),
        "security_id" => to_string(s.share.id),
        "quantity" => "10",
        "price" => "50",
        "fees" => "1,00",
        "taxes" => "0",
        "notes" => ""
      }
    })

    [drawer_buy] =
      Transaction
      |> Repo.all()
      |> Enum.filter(&(&1.type == "buy" and Decimal.equal?(&1.price, Decimal.new("50"))))

    drawer_buy
  end

  defp toggle_account(view, account_id) do
    view
    |> element(
      "#transaction-chips [phx-value-family='account'][phx-value-option='#{account_id}']"
    )
    |> render_click()
  end

  defp cell(doc, tx, role) do
    doc
    |> Floki.find("#transaction-list tr[data-transaction='#{tx.id}'] td[data-role='#{role}']")
    |> Floki.text()
    |> String.replace(~r/\s+/u, "")
  end

  # User story (#1209, Sprint 21 α11): As the operator reading one cash
  # account's history, I want each row's Betrag to be the cash that row
  # moved in its account, fees and taxes included, so that the Betrag column
  # adds up to what the balance beside it did, whichever route booked the
  # trade.
  #
  # Acceptance criteria (board 03 `03-history-drawer`, #1209):
  # - A buy booked without a gross amount (the API's route and the drawer's
  #   own same-currency buy) reads its cash: 20 × 48,20 + 1,00 fee reads
  #   −965,00 EUR, not −964,00; the drawer's 10 × 50,00 + 1,00 reads −501,00.
  # - A sell booked without a gross amount reads its proceeds net of fees and
  #   taxes: 5 × 60,00 − 1,00 − 0,50 reads +298,50 (#1147), not 300,00.
  # - A buy at price 0 reads "0,00", never "−0,00".
  # - Σ Betrag of the trade rows equals the balance's change: −1.167,50,
  #   from 3.000,00 to 1.832,50.
  # - The summary's Kauf sum is the same figure: 3 · 1.466,00 EUR; Verkauf
  #   1 · 298,50 EUR; its basis line says it sums the cash moved.
  test "the Betrag is the cash the balance moves, and the summary sums the same figure",
       %{conn: conn} do
    s = seed()
    drawer_buy = book_through_drawer(conn, s)

    assert drawer_buy.gross_amount == nil

    {:ok, view, _html} = live(conn, "/transactions?locale=de")
    toggle_account(view, s.world.cash.id)
    doc = view |> render() |> Floki.parse_document!()

    assert cell(doc, s.api_buy, "amount") == "-965,00EUR"
    assert cell(doc, drawer_buy, "amount") == "-501,00EUR"
    assert cell(doc, s.zero_buy, "amount") == "0,00EUR"
    assert cell(doc, s.sell, "amount") == "+298,50EUR"

    assert cell(doc, s.deposit, "running-balance") == "3.000,00"
    assert cell(doc, s.sell, "running-balance") == "1.832,50"

    summary = fn type ->
      doc
      |> Floki.find("#transaction-summary .summary-type[data-type='#{type}']")
      |> Floki.text()
      |> String.replace(~r/\s+/u, " ")
      |> String.trim()
    end

    assert summary.("buy") =~ "Kauf: 3 · 1.466,00 EUR"
    assert summary.("sell") =~ "Verkauf: 1 · 298,50 EUR"

    assert doc |> Floki.find("[data-role='summary-basis']") |> Floki.text() =~
             "bewegtes Geld je Art"
  end

  # User story (#1209, Sprint 21 α11): As the operator reading the history
  # on a phone, I want the phone row's amount to be the same cash figure as
  # the desktop cell, so that the two widths never disagree.
  #
  # Acceptance criteria:
  # - `phone_amount/2` of the API buy reads "-965,00 EUR" and of the zero buy
  #   "0,00 EUR".
  test "the phone row reads the same cash figure", %{conn: conn} do
    s = seed()
    {:ok, _view, _html} = live(conn, "/transactions?locale=de")

    [api_buy, zero_buy] =
      Enum.map([s.api_buy, s.zero_buy], &Repo.preload(&1, [:cash_account]))

    Gettext.with_locale(PortfolixirWeb.Gettext, "de", fn ->
      assert PortfolixirWeb.TransactionManagementLive.phone_amount(api_buy) == "-965,00 EUR"
      assert PortfolixirWeb.TransactionManagementLive.phone_amount(zero_buy) == "0,00 EUR"
    end)
  end

  # User story (#1209, Sprint 21 α11): As the operator reading one cash
  # account's history, I want a sell whose fees exceed its proceeds to read
  # as the money that left the account, so that the Betrag column still adds
  # up to what the balance beside it did.
  #
  # Acceptance criteria (#1209):
  # - Deposit 100,00, buy 1 × 10,00, sell 1 × 0,00 with a fee of 1,00 (a
  #   worthless write-off): the sell's Betrag reads "-1,00 EUR", the sign
  #   taken from its cash leg, not from its kind, and its Saldo reads 89,00.
  # - Σ Betrag of the three rows is 89,00, the balance's change from 0.
  # - The phone row reads "-1,00 EUR"; the summary's Verkauf sum is the same
  #   figure, "1 · -1,00 EUR", and its basis line says each kind's sum is in
  #   that kind's direction, so such a sell lowers it, never "ohne
  #   Vorzeichen".
  test "a sell whose fees exceed its proceeds reads as money leaving the account",
       %{conn: conn} do
    world =
      WorldFixtures.base_world(
        name: "Write-off",
        cash_name: "Test-Cash",
        depot_name: "Depot Muster"
      )

    share = WorldFixtures.create_security!(name: "Wrenfield Gardens AG", ticker: "WGA")
    deposit = WorldFixtures.deposit!(world, "100", ~D[2026-10-01])

    book = fn attrs ->
      {:ok, tx} =
        Ledger.create_transaction(
          Actor.owner_ui(),
          Map.merge(
            %{
              portfolio_id: world.portfolio.id,
              securities_account_id: world.depot.id,
              cash_account_id: world.cash.id,
              security_id: share.id,
              currency_code: "EUR",
              quantity: "1",
              taxes: "0"
            },
            attrs
          )
        )

      tx
    end

    buy = book.(%{type: "buy", date: ~D[2026-10-02], price: "10", fees: "0"})
    write_off = book.(%{type: "sell", date: ~D[2026-10-03], price: "0", fees: "1.00"})

    {:ok, view, _html} = live(conn, "/transactions?locale=de")
    toggle_account(view, world.cash.id)
    doc = view |> render() |> Floki.parse_document!()

    assert cell(doc, deposit, "amount") == "+100,00EUR"
    assert cell(doc, buy, "amount") == "-10,00EUR"
    assert cell(doc, write_off, "amount") == "-1,00EUR"
    assert cell(doc, write_off, "running-balance") == "89,00"

    sell_summary =
      doc
      |> Floki.find("#transaction-summary .summary-type[data-type='sell']")
      |> Floki.text()
      |> String.replace(~r/\s+/u, " ")
      |> String.trim()

    assert sell_summary =~ "Verkauf: 1 · -1,00 EUR"

    basis = doc |> Floki.find("[data-role='summary-basis']") |> Floki.text()

    # #1435 (4), L5 (board ux-design-2026-11-12-sprint29/06 ⑨): the set and
    # the currency on the line, the direction and the costly sell in its ⓘ.
    assert basis =~ "je Währung summiert und nicht umgerechnet."

    tip =
      doc
      |> Floki.find("[data-role='summary-basis'] details.metric-tooltip [role='tooltip']")
      |> Floki.text()
      |> String.replace(~r/\s+/u, " ")

    assert tip =~
             "Jede Art wird in ihrer eigenen Richtung summiert; ein Verkauf, dessen " <>
               "Gebühren und Steuern seinen Erlös übersteigen, mindert die Summe der Verkäufe."

    refute basis =~ "ohne Vorzeichen"

    write_off = Repo.preload(write_off, [:cash_account])

    Gettext.with_locale(PortfolixirWeb.Gettext, "de", fn ->
      assert PortfolixirWeb.TransactionManagementLive.phone_amount(write_off) == "-1,00 EUR"
    end)
  end
end
