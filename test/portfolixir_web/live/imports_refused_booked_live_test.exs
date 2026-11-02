defmodule PortfolixirWeb.ImportsRefusedBookedLiveTest do
  # Sprint 22 R3, #1219, on the Imports page as board
  # ux-design-2026-11-01-sprint22/03 ③ draws it: a refused row whose
  # booking already exists says "bereits gebucht" in the parser warnings and
  # names that booking, instead of the remedy that would book it twice; a
  # refused row with no match keeps its remedy. Every name and amount is
  # synthetic.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Imports
  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  @arbolia ~s("security": {"name": "Arbolia Inc.", "isin": "DE000ACME016", "currency": "EUR"})

  @history [
    ~s({"type": "DEPOSIT", "account": "Test-Cash", "date": "2026-02-02",
      "currency": "EUR", "amount": "2000.00"}),
    ~s({"type": "PURCHASE", "account": "Test-Cash", "portfolio": "Test-Depot",
      "date": "2026-02-04", "currency": "EUR", "amount": "501.00", "shares": "5",
      #{@arbolia}, "units": [{"type": "FEE", "amount": "1.00"}]})
  ]

  @refused [
    ~s({"type": "PURCHASE", "account": "Test-Cash", "portfolio": "Test-Depot",
      "date": "2026-03-03", "currency": "EUR", "amount": "1003.00", "shares": "10",
      #{@arbolia},
      "units": [{"type": "FEE", "amount": "5.00"}, {"type": "FEE", "amount": "-2.00"}]}),
    ~s({"type": "INBOUND_DELIVERY", "portfolio": "Test-Depot", "date": "2026-03-04",
      "currency": "EUR", "amount": "999.60", "shares": "4", #{@arbolia},
      "units": [{"type": "TAX", "amount": "-0.40"}]})
  ]

  defp body(rows), do: ~s({"version": 1, "transactions": [#{Enum.join(rows, ",")}]})

  defp by_hand!(portfolio) do
    [cash] = Portfolios.list_cash_accounts_for_portfolio(portfolio.id)
    [depot] = Portfolios.list_securities_accounts_for_portfolio(portfolio.id)
    [security] = Catalog.list_securities()

    {:ok, transaction} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        type: "buy",
        date: ~D[2026-03-03],
        security_id: security.id,
        securities_account_id: depot.id,
        cash_account_id: cash.id,
        currency_code: "EUR",
        quantity: Decimal.new("10"),
        price: Decimal.new("100.00"),
        fees: Decimal.new("3.00"),
        taxes: Decimal.new("0")
      })

    transaction
  end

  # User story (#1219; board 03 ③):
  # As the operator dropping an export again after I booked its refused
  # purchase by hand, as its warning told me,
  # I want the warning to say "bereits gebucht" and name that booking,
  # so that I do not book the purchase a second time.
  #
  # Acceptance criteria:
  # - German: "Eintrag 3: Buchung mit einer negativen Gebühr (-2,00): Eine
  #   Gebührenerstattung bucht der Import noch nicht — bereits gebucht: Kauf
  #   vom 03.03.2026, Arbolia Inc., 10 Stück, -1.003,00 EUR auf Test-Cash,
  #   von Hand erfasst. Die Buchung nicht noch einmal erfassen."
  # - Entry 4, the delivery nobody booked, keeps its remedy.
  # - English: "… — already booked: Buy of 2026-03-03, Arbolia Inc., 10
  #   shares, -1,003.00 EUR on Test-Cash, entered by hand. Do not enter the
  #   booking again."
  # - A second equal hand booking: both are named, "2 gespeicherte
  #   Buchungen passen: …", and neither is chosen.
  test "a refused row whose booking exists says bereits gebucht and names it", %{conn: conn} do
    portfolio = Portfolios.default_portfolio(Actor.owner_ui())
    {:ok, history} = PortfolioPerformance.parse(body(@history), filename: "history.json")
    {:ok, _result} = Imports.apply(history, %{portfolio_id: portfolio.id})
    by_hand!(portfolio)

    {:ok, view, _html} = live(german(conn), "/imports")
    upload(view, "history.json", body(@history ++ @refused))

    assert text(view, "#parser-warnings-box pre") ==
             "Eintrag 3: Buchung mit einer negativen Gebühr (-2,00): Eine Gebührenerstattung " <>
               "bucht der Import noch nicht — bereits gebucht: Kauf vom 03.03.2026, Arbolia " <>
               "Inc., 10 Stück, -1.003,00 EUR auf Test-Cash, von Hand erfasst. Die Buchung " <>
               "nicht noch einmal erfassen. Eintrag 4: Einlieferung mit Steuererstattung 0,40: " <>
               "Eine Einlieferung bewegt kein Geld, die Erstattung hätte kein Konto — Eintrag " <>
               "nicht übernommen. Die Einlieferung ohne sie von Hand buchen; ist Geld " <>
               "geflossen, das als eigene Steuererstattung."

    {:ok, view, _html} = live(conn, "/imports")
    upload(view, "history.json", body(@history ++ @refused))

    assert text(view, "#parser-warnings-box pre") =~
             "Entry 3: booking with a negative fee (-2.00): the import does not book a fee " <>
               "refund yet — already booked: Buy of 2026-03-03, Arbolia Inc., 10 shares, " <>
               "-1,003.00 EUR on Test-Cash, entered by hand. Do not enter the booking again. " <>
               "Entry 4:"

    by_hand!(portfolio)
    {:ok, view, _html} = live(german(conn), "/imports")
    upload(view, "history.json", body(@history ++ @refused))

    assert text(view, "#parser-warnings-box pre") =~
             "— 2 gespeicherte Buchungen passen: Kauf vom 03.03.2026, Arbolia Inc., 10 Stück, " <>
               "-1.003,00 EUR auf Test-Cash, von Hand erfasst; Kauf vom 03.03.2026, Arbolia " <>
               "Inc., 10 Stück, -1.003,00 EUR auf Test-Cash, von Hand erfasst. Die Buchung " <>
               "nicht noch einmal erfassen. Eintrag 4:"
  end

  defp upload(view, name, content) do
    view
    |> file_input("#pp-import-form", :pp_file, [
      %{name: name, content: content, type: "application/json", last_modified: 1_700_000_000_000}
    ])
    |> render_upload(name)

    render_async(view)
  end

  defp german(conn), do: put_req_header(conn, "accept-language", "de-DE,de;q=0.9")

  defp text(view, selector) do
    view
    |> element(selector)
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.text(sep: " ")
    |> String.replace(~r/\s+/u, " ")
    |> String.replace(~r/ ([.,:;])/u, "\\1")
    |> String.trim()
  end
end
