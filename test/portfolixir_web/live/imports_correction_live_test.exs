defmodule PortfolixirWeb.ImportsCorrectionLiveTest do
  # ADR-0053 §6 and A6 on the Imports page: Sprint 19's board
  # `ux-design-2026-10-04/09-import-correction` (pick J9 = A) and Sprint 20's
  # board 01 ⑧ (the note's first sentence names the Portfolio Performance
  # file, not its format). A re-dropped file whose bookings were stored under
  # an older reading shows a section of its own, "Already imported, with a
  # different amount", with its own confirm, apart from "Confirm import".
  #
  # The old readings are rebuilt as `cash_correction_test.exs` rebuilds them.
  # Every name and amount is synthetic.
  use PortfolixirWeb.ConnCase

  import Ecto.Query, only: [from: 2]
  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Fx
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Entry
  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Imports.Preview
  alias Portfolixir.Journal
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Repo

  # A Portfolio Performance CSV as PP writes it, the shape of board 09: a
  # purchase, a dividend and a sale on Girokonto, interest on Tagesgeld,
  # each with fees or taxes, so its Gesamtpreis differs from its Betrag.
  @pp_csv """
  Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle
  2024-01-02 00:00:00;Einlage;;;;10.000,00;;;10.000,00;Girokonto;;;
  2024-01-15 10:01:00;Kauf;Nordwind Industrie AG;10;150,00;1.500,00;2,50;;1.502,50;Depot;Girokonto;;
  2024-03-16 00:00:00;Dividende;Nordwind Industrie AG;10;;11,54;;2,41;9,13;Girokonto;;;
  2024-04-28 12:25:00;Verkauf;Nordwind Industrie AG;10;181,45;1.814,50;2,50;12,00;1.800,00;Depot;Girokonto;;
  2024-06-30 00:00:00;Zinsen;;;;5,75;;1,20;4,55;Tagesgeld;;;
  """

  # The sale history as the converter prompt writes it, its refund riding the
  # sale as a negative Steuern and no Gesamtpreis.
  @converter_csv """
  Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle
  2024-03-01;Einlage;;;;1.100,00;;;;Test-Cash;;;
  2024-03-04 10:01:00;Kauf;Arbolia Inc.;10;10,00;100,00;;;;Test-Depot;Test-Cash;;
  2024-06-14 15:30:00;Verkauf;Arbolia Inc.;10;10,00;120,00;5,00;-25,00;;Test-Depot;Test-Cash;;
  """

  # A sale of a USD security through a EUR account, its refund a negative tax
  # unit: the cash, the price and the settlement legs move together.
  @cross_currency_json """
  {
    "version": 1,
    "transactions": [
      {"type": "DEPOSIT", "account": "FX-Cash", "date": "2026-01-02",
       "currency": "EUR", "amount": 1000.0},
      {"type": "PURCHASE", "account": "FX-Cash", "portfolio": "FX-Depot",
       "date": "2026-01-15", "time": "10:00", "currency": "EUR",
       "amount": 100.0, "shares": 10.0,
       "security": {"name": "Harborline Freight Inc", "currency": "USD"}},
      {"type": "SALE", "account": "FX-Cash", "portfolio": "FX-Depot",
       "date": "2026-03-16", "time": "15:30", "currency": "EUR",
       "amount": 120.0, "shares": 10.0,
       "security": {"name": "Harborline Freight Inc", "currency": "USD"},
       "units": [{"type": "FEE", "amount": 5.0}, {"type": "TAX", "amount": -25.0}]}
    ]
  }
  """

  defp pp_csv, do: @pp_csv

  defp portfolio! do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Correction target",
        base_currency_code: "EUR"
      })

    portfolio
  end

  # The file applied the way the importer booked it before ADR-0053 and its
  # amendment: every row's cash cell whole, a JSON trade priced the old way.
  defp apply_old_reading!(portfolio, body, filename) do
    {:ok, %Preview{errors: []} = preview} = PortfolioPerformance.parse(body, filename: filename)

    old =
      Enum.map(preview.entries, fn %Entry{} = entry ->
        %{entry | gross_amount: entry.hash_amount, price: entry.hash_price || entry.price}
      end)

    {:ok, _result} = Imports.apply(%{preview | entries: old}, %{portfolio_id: portfolio.id})
    :ok
  end

  defp apply_as_read_today!(portfolio, body, filename) do
    {:ok, preview} = PortfolioPerformance.parse(body, filename: filename)
    {:ok, _result} = Imports.apply(preview, %{portfolio_id: portfolio.id})
    :ok
  end

  # The preview's counts are refined in the background once the file is
  # parsed; the helper answers the page after that.
  defp upload(view, name, content, type) do
    view
    |> file_input("#pp-import-form", :pp_file, [
      %{name: name, content: content, type: type, last_modified: 1_700_000_000_000}
    ])
    |> render_upload(name)

    render_async(view)
  end

  defp german(conn), do: put_req_header(conn, "accept-language", "de-DE,de;q=0.9")

  # The text a reader sees: the test DOM keeps no whitespace between tags,
  # so the text nodes are joined by a space, and a space a join put before
  # a punctuation mark is taken out again.
  defp text(view, selector) do
    view
    |> element(selector)
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.text(sep: " ")
    |> String.replace(~r/\s+/u, " ")
    |> String.replace(~r/ ([.,:])/u, "\\1")
    |> String.trim()
  end

  defp balance(portfolio, name) do
    %{id: id} = Enum.find(Portfolios.list_cash_accounts(), &(&1.name == name))
    [portfolio_id: portfolio.id] |> Ledger.cash_balances() |> Map.fetch!(id)
  end

  describe "the correction section (board 09, pick J9 = A; board 01 ⑧)" do
    # User story (ADR-0053 §6, A6):
    # As the operator re-dropping a Portfolio Performance export imported
    # before its cash was read as Portfolio Performance writes it,
    # I want the preview to list, in a section of its own, each booking
    # whose stored cash differs from the file, with what is booked, what the
    # file states and the difference,
    # so that I see what is off before I decide anything.
    #
    # Acceptance criteria (board 09 A; board 01 ⑧):
    # - "Already imported, with a different amount", outside the apply form,
    #   after the counts and before the mapping.
    # - One attention note: the format-neutral sentence of ⑧, then the table
    #   Row · Date · Booking · Booked · Per the file · Difference, signed and
    #   in the sign colours; the same rows as two-line phone rows.
    # - The total per account, then "Correct 5 bookings…" beside "a step of
    #   its own, apart from “Confirm import”".
    test "lists each booking with its stored cash, the file's cash and the difference", %{
      conn: conn
    } do
      portfolio = portfolio!()
      apply_old_reading!(portfolio, pp_csv(), "export.csv")

      {:ok, view, _html} = live(conn, "/imports")
      upload(view, "export.csv", pp_csv(), "text/csv")

      assert text(view, "#import-correction-head") == "Already imported, with a different amount"
      refute has_element?(view, "form#pp-import-apply #import-correction")

      assert has_element?(
               view,
               "#import-correction [data-role='import-correction'].data-note--attention"
             )

      assert text(view, "#import-correction [data-role='import-correction-finding']") ==
               "4 bookings already imported differ from this file: they were booked as an earlier version of the import read their rows — a CSV row's gross value, or a cash amount that also held the tax refund booked beside it. The Portfolio Performance file states what the account moved; the difference is the row's fees and taxes, or that refund."

      assert text(view, "#import-correction-table thead") ==
               "Row Date Booking Booked Per the file Difference"

      assert text(view, "#import-correction-table tbody tr:nth-child(1)") ==
               "3 2024-01-15 Buy · Nordwind Industrie AG · Girokonto -1,500.00 -1,502.50 -2.50"

      assert text(view, "#import-correction-table tbody tr:nth-child(2)") ==
               "4 2024-03-16 Dividend · Nordwind Industrie AG · Girokonto +11.54 +9.13 -2.41"

      assert text(view, "#import-correction-table tbody tr:nth-child(3)") ==
               "5 2024-04-28 Sell · Nordwind Industrie AG · Girokonto +1,814.50 +1,800.00 -14.50"

      assert text(view, "#import-correction-table tbody tr:nth-child(4)") ==
               "6 2024-06-30 Interest · Tagesgeld +5.75 +4.55 -1.20"

      assert has_element?(
               view,
               "#import-correction-table tbody tr:nth-child(1) td.num.is-negative",
               "-1,502.50"
             )

      assert has_element?(
               view,
               "#import-correction-table tbody tr:nth-child(2) td.num.is-positive",
               "+9.13"
             )

      assert has_element?(
               view,
               "#import-correction-table tbody tr:nth-child(2) td.num.is-negative",
               "-2.41"
             )

      assert text(view, "#import-correction-phone-rows li:nth-child(1)") ==
               "Nordwind Industrie AG Row 3 · 2024-01-15 · Buy · Girokonto -2.50 -1,500.00 → -1,502.50"

      assert text(view, "#import-correction-phone-rows li:nth-child(4)") ==
               "Tagesgeld Row 6 · 2024-06-30 · Interest -1.20 +5.75 → +4.55"

      assert text(view, "#import-correction .import-correction__total") ==
               "Together -20.61 EUR: Girokonto -19.41 EUR, Tagesgeld -1.20 EUR."

      assert has_element?(
               view,
               "#import-correction .import-correction__total b.is-negative",
               "-20.61 EUR"
             )

      assert text(view, "#import-correction-open") == "Correct 4 bookings…"

      assert text(view, "#import-correction .import-correction__foot .summary-basis") ==
               "a step of its own, apart from “Confirm import”"

      html = render(view)
      [before_mapping, _] = String.split(html, ~s(id="pp-import-apply"), parts: 2)
      assert before_mapping =~ ~s(id="import-correction")
    end

    # User story (board 01 ⑧):
    # As a German-speaking operator,
    # I want the section in German, its finding naming the Portfolio
    # Performance file rather than a column of one format,
    # so that it reads true for a CSV and a JSON export alike.
    #
    # Acceptance criteria:
    # - The heading, the columns, the note's sentence as board 03 ① gives it
    #   (⑧'s file clause, true for a gross value and for a refund counted
    #   twice), the total and the button read in German; a one-booking file
    #   reads in the singular.
    test "reads in German, the finding format-neutral, singular for one booking", %{conn: conn} do
      portfolio = portfolio!()
      apply_old_reading!(portfolio, pp_csv(), "export.csv")

      {:ok, view, _html} = live(german(conn), "/imports")
      upload(view, "export.csv", pp_csv(), "text/csv")

      assert text(view, "#import-correction-head") == "Bereits importiert, mit anderem Betrag"

      assert text(view, "#import-correction [data-role='import-correction-finding']") ==
               "4 bereits importierte Buchungen weichen von dieser Datei ab: Gebucht ist, wie eine frühere Version des Imports ihre Zeilen las — der Bruttowert einer CSV-Zeile oder ein Geldbetrag, der auch die daneben gebuchte Steuererstattung enthielt. Was das Konto bewegt, nennt die Portfolio-Performance-Datei; die Differenz sind die Gebühren und Steuern der Zeile oder diese Erstattung."

      assert text(view, "#import-correction-table thead") ==
               "Zeile Datum Buchung Gebucht Laut Datei Differenz"

      assert text(view, "#import-correction-table tbody tr:nth-child(1)") ==
               "3 15.01.2024 Kauf · Nordwind Industrie AG · Girokonto -1.500,00 -1.502,50 -2,50"

      assert text(view, "#import-correction-phone-rows li:nth-child(4)") ==
               "Tagesgeld Zeile 6 · 30.06.2024 · Zinsen -1,20 +5,75 → +4,55"

      assert text(view, "#import-correction .import-correction__total") ==
               "Zusammen -20,61 EUR: Girokonto -19,41 EUR, Tagesgeld -1,20 EUR."

      assert text(view, "#import-correction-open") == "4 Buchungen korrigieren…"

      assert text(view, "#import-correction .import-correction__foot .summary-basis") ==
               "ein eigener Schritt, unabhängig von „Import bestätigen“"

      {:ok, view, _html} = live(german(conn), "/imports")
      upload(view, "converter.csv", @converter_csv, "text/csv")
      refute has_element?(view, "#import-correction")

      apply_old_reading!(portfolio, @converter_csv, "converter.csv")
      {:ok, view, _html} = live(german(conn), "/imports")
      upload(view, "converter.csv", @converter_csv, "text/csv")

      assert text(view, "#import-correction [data-role='import-correction-finding']") ==
               "Eine bereits importierte Buchung weicht von dieser Datei ab: Gebucht ist, wie eine frühere Version des Imports ihre Zeile las — der Bruttowert einer CSV-Zeile oder ein Geldbetrag, der auch die daneben gebuchte Steuererstattung enthielt. Was das Konto bewegt, nennt die Portfolio-Performance-Datei; die Differenz sind die Gebühren und Steuern der Zeile oder diese Erstattung."

      assert text(view, "#import-correction-open") == "Eine Buchung korrigieren…"
    end

    # User story (ADR-0053 §6, ADR-0015, A2):
    # As the operator correcting a JSON sale of a USD security,
    # I want its line to say that the settlement and the price change with
    # its cash,
    # so that nothing the confirm writes is left unsaid.
    #
    # Acceptance criteria:
    # - Under the booking: "Settlement booked: 125.00 EUR = 156.25 USD",
    #   "Settlement per the file: 100.00 EUR = 125.00 USD", then the price
    #   booked and per the file, 12.50 EUR and 10.00 EUR.
    test "a cross-currency JSON sale names its legs and its price before and after", %{
      conn: conn
    } do
      {:ok, _} =
        Fx.upsert_many([
          %{
            base_currency: "EUR",
            quote_currency: "USD",
            date: ~D[2026-01-01],
            rate: "1.25",
            source: "manual"
          }
        ])

      portfolio = portfolio!()
      apply_old_reading!(portfolio, @cross_currency_json, "fx.json")

      {:ok, view, _html} = live(conn, "/imports")
      upload(view, "fx.json", @cross_currency_json, "application/json")

      assert text(view, "#import-correction-table tbody tr:nth-child(1)") ==
               "3 2026-03-16 Sell · Harborline Freight Inc · FX-Cash " <>
                 "Settlement booked: 125.00 EUR = 156.25 USD " <>
                 "Settlement per the file: 100.00 EUR = 125.00 USD " <>
                 "Price booked: 12.50 EUR Price per the file: 10.00 EUR " <>
                 "+120.00 +95.00 -25.00"
    end

    # User story (ADR-0053 §6, UX-DR2):
    # As the operator re-dropping a file whose bookings all agree with it,
    # I want no correction section and no all-clear,
    # so that the preview shows only what needs me.
    #
    # Acceptance criteria:
    # - No "Already imported, with a different amount", no correction
    #   button, no sentence saying the amounts agree.
    test "nothing differs: no section and no all-clear", %{conn: conn} do
      portfolio = portfolio!()
      apply_as_read_today!(portfolio, pp_csv(), "export.csv")

      {:ok, view, _html} = live(conn, "/imports")
      html = upload(view, "export.csv", pp_csv(), "text/csv")

      refute has_element?(view, "#import-correction")
      refute has_element?(view, "#import-correction-open")
      refute html =~ "different amount"
      refute html =~ "agree"
      assert has_element?(view, "#pp-import-confirm")
    end
  end

  describe "the correction's own confirm (board 09 A)" do
    # User story (ADR-0053 §6):
    # As the operator who wants the listed bookings corrected,
    # I want a confirm that says what changes, how the old amounts are kept,
    # and that a re-import books nothing,
    # so that I can correct them knowing nothing is lost.
    #
    # Acceptance criteria (board 09 A, the booking-delete dialog's anatomy):
    # - "Correct 4 bookings…" opens "Correct booked amounts": the subject
    #   box (4 bookings · Rows 3, 4, 5, 6 · Girokonto, Tagesgeld · -20.61
    #   EUR · Difference, board 03 ②), the consequence per account, the
    #   recalculation, and the journal sentence; in German as on the board.
    # - Cancel is focused first; the confirm is primary, not danger, and
    #   names the act; Cancel closes it and writes nothing.
    test "the dialog says what changes and keeps the old amounts in the journal", %{conn: conn} do
      portfolio = portfolio!()
      apply_old_reading!(portfolio, pp_csv(), "export.csv")

      {:ok, view, _html} = live(conn, "/imports")
      upload(view, "export.csv", pp_csv(), "text/csv")
      refute has_element?(view, "#import-correction-dialog")

      view |> element("#import-correction-open") |> render_click()

      assert has_element?(view, "dialog#import-correction-dialog.modal.import-correction-dialog")
      assert text(view, "#import-correction-dialog-title") == "Correct booked amounts"

      assert text(view, "#import-correction-subject") ==
               "4 bookings Rows 3, 4, 5, 6 · Girokonto, Tagesgeld -20.61 EUR Difference"

      assert text(view, "#import-correction-dialog [data-role='import-correction-consequence']") ==
               "Afterwards Girokonto has 19.41 EUR less and Tagesgeld has 1.20 EUR less. Balances, valuation, return and income are recalculated."

      assert text(view, "#import-correction-dialog [data-role='import-correction-journal']") ==
               "Each change is kept in the journal with the previous amount; the import hashes stay as they are, so importing the same file again books nothing."

      assert has_element?(view, "#import-correction-dialog .button-ghost[autofocus]", "Cancel")
      assert has_element?(view, "#import-correction-confirm.button-primary", "Correct 4 bookings")
      refute has_element?(view, "#import-correction-dialog .button-danger")

      view |> element("#import-correction-dialog .button-ghost") |> render_click()
      refute has_element?(view, "#import-correction-dialog")
      assert Decimal.equal?(balance(portfolio, "Girokonto"), Decimal.new("10326.04"))

      {:ok, view, _html} = live(german(conn), "/imports")
      upload(view, "export.csv", pp_csv(), "text/csv")
      view |> element("#import-correction-open") |> render_click()

      assert text(view, "#import-correction-dialog-title") == "Gebuchte Beträge korrigieren"

      assert text(view, "#import-correction-subject") ==
               "4 Buchungen Zeilen 3, 4, 5, 6 · Girokonto, Tagesgeld -20,61 EUR Differenz"

      assert text(view, "#import-correction-dialog [data-role='import-correction-consequence']") ==
               "Danach hat Girokonto 19,41 EUR weniger und Tagesgeld 1,20 EUR weniger. Kontostände, Bewertung, Rendite und Erträge werden neu berechnet."

      assert text(view, "#import-correction-dialog [data-role='import-correction-journal']") ==
               "Jede Änderung wird mit dem bisherigen Betrag im Journal festgehalten; die Import-Hashes bleiben, wie sie sind, also bucht ein erneuter Import derselben Datei nichts."

      assert text(view, "#import-correction-confirm") == "4 Buchungen korrigieren"
    end

    # User story (ADR-0053 §6, A6):
    # As the operator correcting a JSON sale of a USD security,
    # I want the dialog to name the trade whose settlement and price change,
    # in German as on the board,
    # so that the write is said back before I confirm it.
    #
    # Acceptance criteria:
    # - The consequence reads "Danach hat FX-Cash 25,00 EUR weniger.", then
    #   the sale's new settlement and its new price, then the
    #   recalculation.
    test "the dialog names a trade's new settlement and price", %{conn: conn} do
      {:ok, _} =
        Fx.upsert_many([
          %{
            base_currency: "EUR",
            quote_currency: "USD",
            date: ~D[2026-01-01],
            rate: "1.25",
            source: "manual"
          }
        ])

      portfolio = portfolio!()
      apply_old_reading!(portfolio, @cross_currency_json, "fx.json")

      {:ok, view, _html} = live(german(conn), "/imports")
      upload(view, "fx.json", @cross_currency_json, "application/json")
      view |> element("#import-correction-open") |> render_click()

      assert text(view, "#import-correction-subject") ==
               "1 Buchung Zeile 3 · FX-Cash -25,00 EUR Differenz"

      assert text(view, "#import-correction-dialog [data-role='import-correction-consequence']") ==
               "Danach hat FX-Cash 25,00 EUR weniger. " <>
                 "Beim Verkauf von Harborline Freight Inc am 16.03.2026 ändert sich die Abrechnung mit: 100,00 EUR = 125,00 USD. " <>
                 "Beim Verkauf von Harborline Freight Inc am 16.03.2026 ändert sich der Kurs mit: 10,00 EUR. " <>
                 "Kontostände, Bewertung, Rendite und Erträge werden neu berechnet."

      assert text(view, "#import-correction-confirm") == "Eine Buchung korrigieren"
    end

    # User story (ADR-0053 §6, K7):
    # As the operator who confirmed the correction,
    # I want the section to give way to one line saying what was corrected,
    # so that I see the result where the finding stood, while "Confirm
    # import" still writes nothing.
    #
    # Acceptance criteria (board 09 A, the result line):
    # - "4 bookings corrected: Girokonto -19.41 EUR, Tagesgeld -1.20 EUR.
    #   The journal keeps the previous amounts." in a note where the section
    #   stood; the section is gone, and a second drop of the file shows none.
    # - The stored cash is corrected (Girokonto 10,326.04 -> 10,306.63,
    #   Tagesgeld 5.75 -> 4.55), each change journaled under the operator.
    # - "Confirm import" afterwards still creates nothing.
    test "confirming corrects the bookings and leaves a result line where the section stood", %{
      conn: conn
    } do
      portfolio = portfolio!()
      apply_old_reading!(portfolio, pp_csv(), "export.csv")

      {:ok, view, _html} = live(conn, "/imports")
      upload(view, "export.csv", pp_csv(), "text/csv")
      view |> element("#import-correction-open") |> render_click()
      view |> element("#import-correction-confirm") |> render_click()
      render_async(view)

      refute has_element?(view, "#import-correction-dialog")
      refute has_element?(view, "#import-correction")

      assert text(view, "#import-correction-result [role='status']") ==
               "Note 4 bookings corrected: Girokonto -19.41 EUR, Tagesgeld -1.20 EUR. The journal keeps the previous amounts. ×"

      assert Decimal.equal?(balance(portfolio, "Girokonto"), Decimal.new("10306.63"))
      assert Decimal.equal?(balance(portfolio, "Tagesgeld"), Decimal.new("4.55"))

      journal = Journal.list_entries(resource_type: "transaction", operation: :update)
      assert length(journal) == 4

      assert Enum.all?(
               journal,
               &(&1.actor_type == :owner_ui and &1.actor_label == "import correction")
             )

      before = Ledger.count_transactions()
      view |> element("form#pp-import-apply") |> render_submit()
      assert render_async(view, 1_000) =~ "Created transactions: 0"
      assert Ledger.count_transactions() == before
      refute has_element?(view, "[data-role='correction-not-applied']")

      {:ok, view, _html} = live(conn, "/imports")
      upload(view, "export.csv", pp_csv(), "text/csv")
      refute has_element?(view, "#import-correction")
    end

    # User story (ADR-0053 §6, K8):
    # As the operator who confirms the import without the correction,
    # I want the result to say which bookings stayed uncorrected and how to
    # correct them,
    # so that nothing is dropped silently.
    #
    # Acceptance criteria (board 09 A, the done page):
    # - "Import complete" names the 4 bookings that are not corrected and
    #   tells to drop the same file again; no stored cash changed. A file
    #   whose bookings all agree names nothing (next test).
    test "the done page names the bookings the import left uncorrected", %{conn: conn} do
      portfolio = portfolio!()
      apply_old_reading!(portfolio, pp_csv(), "export.csv")

      {:ok, view, _html} = live(conn, "/imports")
      upload(view, "export.csv", pp_csv(), "text/csv")
      view |> element("form#pp-import-apply") |> render_submit()
      render_async(view, 1_000)

      assert text(view, "[data-role='correction-not-applied']") ==
               "4 bookings already imported with a different amount from the file are not corrected. Drop the same file again to correct them."

      assert Decimal.equal?(balance(portfolio, "Girokonto"), Decimal.new("10326.04"))

      {:ok, view, _html} = live(german(conn), "/imports")
      upload(view, "export.csv", pp_csv(), "text/csv")
      view |> element("form#pp-import-apply") |> render_submit()
      render_async(view, 1_000)

      assert text(view, "[data-role='correction-not-applied']") ==
               "4 bereits importierte Buchungen mit anderem Betrag als in der Datei sind nicht korrigiert. Dieselbe Datei erneut ablegen, um sie zu korrigieren."
    end

    test "the done page names nothing when every booking agrees with the file", %{conn: conn} do
      portfolio = portfolio!()
      apply_as_read_today!(portfolio, pp_csv(), "export.csv")

      {:ok, view, _html} = live(conn, "/imports")
      upload(view, "export.csv", pp_csv(), "text/csv")
      view |> element("form#pp-import-apply") |> render_submit()
      render_async(view, 1_000)
      refute has_element?(view, "[data-role='correction-not-applied']")
    end
  end

  describe "the section's row names and the subject's caption (board 03 ③)" do
    # Two accounts in two currencies, each with a dividend whose negative tax
    # unit was counted twice under the old reading.
    @two_currencies_json """
    {
      "version": 1,
      "transactions": [
        {"type": "DEPOSIT", "account": "EUR-Cash", "date": "2026-01-02",
         "currency": "EUR", "amount": 1000.0},
        {"type": "DIVIDEND", "account": "EUR-Cash", "date": "2026-03-16",
         "currency": "EUR", "amount": 50.0,
         "security": {"name": "Nordwind Industrie AG", "currency": "EUR"},
         "units": [{"type": "TAX", "amount": -5.0}]},
        {"type": "DEPOSIT", "account": "USD-Cash", "date": "2026-01-02",
         "currency": "USD", "amount": 1000.0},
        {"type": "DIVIDEND", "account": "USD-Cash", "date": "2026-03-17",
         "currency": "USD", "amount": 40.0,
         "security": {"name": "Harborline Freight Inc", "currency": "USD"},
         "units": [{"type": "TAX", "amount": -4.0}]}
      ]
    }
    """

    # User story (found by the α closing act, edge-case hunter EC-F7):
    # As the operator who changed a split-off tax refund by hand and drops
    # the file again,
    # I want the correction to name that refund by its row and kind, as the
    # rest of the page does,
    # so that I can find it in the file.
    #
    # Acceptance criteria:
    # - The converter sale's refund (row 4), edited from 25.00 to 26.00, is
    #   listed as "4 (Tax refund)" in the table, "Row 4 (Tax refund)" in its
    #   phone row and in the dialog's subject; never "4.tax_refund.1".
    test "a split-off refund is named by its row and kind", %{conn: conn} do
      portfolio = portfolio!()
      apply_as_read_today!(portfolio, @converter_csv, "converter.csv")

      refund =
        portfolio.id
        |> Ledger.list_transactions_for_portfolio()
        |> Enum.find(&(&1.type == "tax_refund"))

      {:ok, _edited} =
        Ledger.update_transaction(Actor.owner_ui(), refund, %{gross_amount: "26.00"})

      {:ok, view, _html} = live(conn, "/imports")
      upload(view, "converter.csv", @converter_csv, "text/csv")

      assert text(view, "#import-correction-table tbody tr:nth-child(1)") ==
               "4 (Tax refund) 2024-06-14 Tax refund · Arbolia Inc. · Test-Cash +26.00 +25.00 -1.00"

      assert text(view, "#import-correction-phone-rows li:nth-child(1)") ==
               "Arbolia Inc. Row 4 (Tax refund) · 2024-06-14 · Tax refund · Test-Cash -1.00 +26.00 → +25.00"

      view |> element("#import-correction-open") |> render_click()

      assert text(view, "#import-correction-subject") ==
               "1 booking Row 4 (Tax refund) · Test-Cash -1.00 EUR Difference"

      refute render(view) =~ "tax_refund.1"
    end

    # User story (ADR-0053 §6; EC-F7's row name in the refusal):
    # As the operator whose correction the ledger refuses,
    # I want the result to name the row as the page names it, the reason,
    # and that nothing was corrected,
    # so that one refused booking never leaves the others half-corrected.
    #
    # Acceptance criteria:
    # - The refund edited by hand sits on an account whose currency is no
    #   longer the booking's (a stored state the ledger's update refuses
    #   without a settlement rate): the confirm answers "Row 4 (Tax refund):
    #   the correction was refused: … Nothing was corrected.", the refund
    #   keeps its cash, and the journal holds no correction.
    test "a refused write names its row and corrects nothing", %{conn: conn} do
      portfolio = portfolio!()
      apply_as_read_today!(portfolio, @converter_csv, "converter.csv")

      refund =
        portfolio.id
        |> Ledger.list_transactions_for_portfolio()
        |> Enum.find(&(&1.type == "tax_refund"))

      {:ok, _edited} =
        Ledger.update_transaction(Actor.owner_ui(), refund, %{gross_amount: "26.00"})

      # A stored state no public write reaches, set under a system actor
      # the journal trigger admits.
      {:ok, {1, nil}} =
        Repo.transaction(fn ->
          Repo.query!("SELECT set_config('portfolixir.journal_actor', 'system_job:test', true)")

          Repo.update_all(
            from(c in CashAccount, where: c.name == "Test-Cash"),
            set: [currency_code: "USD"]
          )
        end)

      {:ok, view, _html} = live(conn, "/imports")
      upload(view, "converter.csv", @converter_csv, "text/csv")
      view |> element("#import-correction-open") |> render_click()
      view |> element("#import-correction-confirm") |> render_click()
      render_async(view, 1_000)

      assert text(view, "#import-correction-result") =~
               "Row 4 (Tax refund): the correction was refused: Exchange rate is required for a cross-currency settlement. Nothing was corrected."

      assert Decimal.equal?(Repo.get!(Transaction, refund.id).gross_amount, Decimal.new("26"))

      assert Journal.list_entries(resource_type: "transaction", operation: :update) |> length() ==
               1
    end

    # User story (found by the α closing act, edge-case hunter EC-F8;
    # board 03 ③):
    # As the operator correcting bookings on accounts of two currencies,
    # I want the dialog's subject box to caption no figure it does not show,
    # so that "Difference" never stands alone.
    #
    # Acceptance criteria:
    # - Two dividends, one on a EUR and one on a USD account, have no common
    #   total: the subject box shows no figure and no caption; the section's
    #   total line reads "Per account: …".
    test "the subject box shows no caption without a common total", %{conn: conn} do
      portfolio = portfolio!()
      apply_old_reading!(portfolio, @two_currencies_json, "two.json")

      {:ok, view, _html} = live(conn, "/imports")
      upload(view, "two.json", @two_currencies_json, "application/json")

      assert text(view, "#import-correction .import-correction__total") ==
               "Per account: EUR-Cash -5.00 EUR, USD-Cash -4.00 USD."

      view |> element("#import-correction-open") |> render_click()

      assert text(view, "#import-correction-subject") ==
               "2 bookings Rows 2, 4 · EUR-Cash, USD-Cash"

      refute has_element?(view, "#import-correction-subject .phone-row__figure")
      refute has_element?(view, "#import-correction-subject .phone-row__figure2")
    end
  end

  describe "the correction's other outcomes (the α closing act, coverage)" do
    # A purchase of a USD security through a EUR account whose negative tax
    # unit the old reading counted twice: its debit, its price and its
    # settlement legs move together.
    @cross_currency_purchase_json """
    {
      "version": 1,
      "transactions": [
        {"type": "DEPOSIT", "account": "FX-Cash", "date": "2026-01-02",
         "currency": "EUR", "amount": 1000.0},
        {"type": "PURCHASE", "account": "FX-Cash", "portfolio": "FX-Depot",
         "date": "2026-01-15", "time": "10:00", "currency": "EUR",
         "amount": 100.0, "shares": 10.0,
         "security": {"name": "Harborline Freight Inc", "currency": "USD"},
         "units": [{"type": "TAX", "amount": -5.0}]}
      ]
    }
    """

    defp refund_edited!(portfolio, amount) do
      apply_as_read_today!(portfolio, @converter_csv, "converter.csv")

      refund =
        portfolio.id
        |> Ledger.list_transactions_for_portfolio()
        |> Enum.find(&(&1.type == "tax_refund"))

      {:ok, _edited} =
        Ledger.update_transaction(Actor.owner_ui(), refund, %{gross_amount: amount})

      refund
    end

    # User story (ADR-0053 §6, board 09 A):
    # As the operator whose correction gives an account money back,
    # I want the dialog to say the account has more afterwards,
    # so that the direction of the change is never left to the sign.
    #
    # Acceptance criteria:
    # - A refund lowered by hand from 25.00 to 24.00 is corrected back: the
    #   consequence reads "Afterwards Test-Cash has 1.00 EUR more."
    test "a correction that adds money says the account has more", %{conn: conn} do
      refund_edited!(portfolio!(), "24.00")

      {:ok, view, _html} = live(conn, "/imports")
      upload(view, "converter.csv", @converter_csv, "text/csv")
      view |> element("#import-correction-open") |> render_click()

      assert text(view, "#import-correction-dialog [data-role='import-correction-consequence']") ==
               "Afterwards Test-Cash has 1.00 EUR more. Balances, valuation, return and income are recalculated."
    end

    # User story (UX-DR27, sign colours):
    # As the operator reading a difference below a cent,
    # I want a figure that displays as zero in no sign colour,
    # so that the colour never claims a direction the digits do not show.
    #
    # Acceptance criteria:
    # - A refund edited by hand to 25.004 is listed with a difference that
    #   shows "-0.00" in the body's colour, neither positive nor negative.
    test "a difference that displays as zero carries no sign colour", %{conn: conn} do
      refund_edited!(portfolio!(), "25.004")

      {:ok, view, _html} = live(conn, "/imports")
      upload(view, "converter.csv", @converter_csv, "text/csv")

      cell = "#import-correction-table tbody tr:nth-child(1) td:nth-child(6)"
      assert text(view, cell) =~ ~r/^-?0\.00$/
      refute has_element?(view, cell <> ".is-negative")
      refute has_element?(view, cell <> ".is-positive")
    end

    # User story (ADR-0053 A2, A6; ADR-0015):
    # As the operator correcting a purchase of a USD security,
    # I want the dialog to say how its settlement and its price change,
    # so that the write is said back before I confirm it.
    #
    # Acceptance criteria:
    # - The purchase stored under the old reading (debit 100.00, price
    #   10.00) is corrected to 105.00 at 10.50; the dialog names the
    #   purchase's new settlement and its new price.
    test "the dialog names a purchase's new settlement and price", %{conn: conn} do
      {:ok, _} =
        Fx.upsert_many([
          %{
            base_currency: "EUR",
            quote_currency: "USD",
            date: ~D[2026-01-01],
            rate: "1.25",
            source: "manual"
          }
        ])

      portfolio = portfolio!()
      apply_old_reading!(portfolio, @cross_currency_purchase_json, "buy.json")

      {:ok, view, _html} = live(conn, "/imports")
      upload(view, "buy.json", @cross_currency_purchase_json, "application/json")
      view |> element("#import-correction-open") |> render_click()

      assert text(view, "#import-correction-dialog [data-role='import-correction-consequence']") ==
               "Afterwards FX-Cash has 5.00 EUR less. On the purchase of Harborline Freight Inc on 2026-01-15, the settlement changes with it: 105.00 EUR = 131.25 USD. On the purchase of Harborline Freight Inc on 2026-01-15, the price changes with it: 10.50 EUR. Balances, valuation, return and income are recalculated."
    end

    # User story (ADR-0053 §6, idempotent):
    # As the operator who confirms a correction another tab already made,
    # I want the result to say nothing was corrected,
    # so that a second confirm never claims a change.
    #
    # Acceptance criteria:
    # - The dialog is open; the same correction is confirmed elsewhere; the
    #   confirm answers "No booking was corrected: each already agrees with
    #   this file." and the journal holds one correction, not two.
    test "a confirm whose bookings were corrected meanwhile corrects nothing", %{conn: conn} do
      portfolio = portfolio!()
      apply_old_reading!(portfolio, @converter_csv, "converter.csv")

      {:ok, view, _html} = live(conn, "/imports")
      upload(view, "converter.csv", @converter_csv, "text/csv")
      view |> element("#import-correction-open") |> render_click()

      {:ok, preview} = PortfolioPerformance.parse(@converter_csv, filename: "converter.csv")
      assert {:ok, [_one]} = Imports.correct_cash(Imports.correction_actor(), preview)

      view |> element("#import-correction-confirm") |> render_click()
      render_async(view, 1_000)

      assert text(view, "#import-correction-result") =~
               "No booking was corrected: each already agrees with this file."

      assert length(Journal.list_entries(resource_type: "transaction", operation: :update)) == 1
    end

    # User story (ADR-0053 §6):
    # As the operator whose correction fails for a reason no rule names,
    # I want the page to say it failed and that nothing was corrected,
    # so that I never read a half-done write as done.
    #
    # Acceptance criteria:
    # - The database raises on the write (a synthetic trigger): the result
    #   reads "The correction failed unexpectedly. Nothing was corrected.",
    #   the section is read again and still lists the booking.
    test "a correction that fails unexpectedly says nothing was corrected", %{conn: conn} do
      portfolio = portfolio!()
      apply_old_reading!(portfolio, @converter_csv, "converter.csv")

      {:ok, view, _html} = live(conn, "/imports")
      upload(view, "converter.csv", @converter_csv, "text/csv")
      view |> element("#import-correction-open") |> render_click()

      Repo.query!("""
      CREATE FUNCTION synthetic_failing_write() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        RAISE EXCEPTION 'synthetic failure';
      END
      $$
      """)

      Repo.query!("""
      CREATE TRIGGER synthetic_failing_write BEFORE UPDATE ON transactions
      FOR EACH ROW EXECUTE FUNCTION synthetic_failing_write()
      """)

      ExUnit.CaptureLog.capture_log(fn ->
        view |> element("#import-correction-confirm") |> render_click()
        render_async(view, 1_000)
      end)

      assert text(view, "#import-correction-result") =~
               "The correction failed unexpectedly. Nothing was corrected."

      assert has_element?(view, "#import-correction")
    end
  end

  describe "a refused row already imported (#1118, #1193)" do
    # #1118's sale as a Portfolio Performance CSV: Betrag 1,00, Gebühren
    # 5,90, Steuern -25,00, Gesamtpreis 20,10, which A5 refuses.
    @nominal_sale_csv """
    Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle
    2024-01-02 00:00:00;Einlage;;;;1.000,00;;;1.000,00;Girokonto;;;
    2024-01-15 10:01:00;Kauf;Nordwind Industrie AG;100;2,00;200,00;5,90;;205,90;Depot;Girokonto;;
    2024-06-14 15:30:00;Verkauf;Nordwind Industrie AG;100;0,01;1,00;5,90;-25,00;20,10;Depot;Girokonto;;
    """

    # The file applied under the Betrag reading, before A5 refused the sale:
    # the sale booked its Betrag, its refund beside it.
    defp apply_before_the_refusal!(portfolio) do
      {:ok, %Preview{refused_credits: [%{entry: sale}]} = preview} =
        PortfolioPerformance.parse(@nominal_sale_csv, filename: "nominal.csv")

      old = preview.entries ++ [%{sale | gross_amount: sale.hash_amount}]
      {:ok, _result} = Imports.apply(%{preview | entries: old}, %{portfolio_id: portfolio.id})
      :ok
    end

    # User story (#1118, #1193; found by the α closing act):
    # As the operator re-dropping an export whose nominal sale was imported
    # before A5 refused such a row,
    # I want its parser warning to say that it is already imported and
    # cannot be corrected here,
    # so that I do not enter the sale by hand a second time.
    #
    # Acceptance criteria:
    # - The parser warning of row 4 names the figures in the sentence of
    #   board ux-design-2026-10-07/01-import-preview ③, says the row is
    #   already imported, that it cannot be corrected here, not to book the
    #   sale again, and points to the product documentation; it no longer
    #   says "Book the sale by hand".
    # - The copied warnings read the same.
    # - In German, as the board writes it ("Steuererstattung").
    # - A file never imported keeps the remedy.
    test "its parser warning says it is already imported, in English and German", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/imports")
      upload(view, "nominal.csv", @nominal_sale_csv, "text/csv")

      assert text(view, "#parser-warnings-box pre") ==
               "Row 4: sell with Gesamtpreis 20,10 and a tax refund of 25,00: -4,90 would remain for the sale — row not imported. Book the sale by hand, and the refund as a tax refund of its own."

      portfolio = portfolio!()
      apply_before_the_refusal!(portfolio)

      warning =
        "Row 4: sell with Gesamtpreis 20,10 and a tax refund of 25,00: -4,90 would remain for the sale — already imported, and it cannot be corrected here. Do not book the sale again; see “A negative tax inside a row” in the product documentation."

      {:ok, view, _html} = live(conn, "/imports")
      upload(view, "nominal.csv", @nominal_sale_csv, "text/csv")

      assert text(view, "#parser-warnings-box pre") == warning
      refute render(view) =~ "Book the sale by hand"
      refute has_element?(view, "#import-correction")

      view |> element("#copy-parser-warnings") |> render_click()
      assert_push_event(view, "copy-to-clipboard", %{text: ^warning})

      {:ok, view, _html} = live(german(conn), "/imports")
      upload(view, "nominal.csv", @nominal_sale_csv, "text/csv")

      assert text(view, "#parser-warnings-box pre") ==
               "Zeile 4: Verkauf mit Gesamtpreis 20,10 und Steuererstattung 25,00: Dem Verkauf blieben -4,90 — bereits importiert und hier nicht zu korrigieren. Den Verkauf nicht noch einmal buchen; siehe „Eine negative Steuer in einer Zeile“ in der Produktdokumentation."
    end

    # The same sale as a Portfolio Performance JSON export: `amount` 20.10,
    # a fee unit of 5.90 and a tax unit of -25.00.
    @nominal_sale_json """
    {"version": 1, "transactions": [
      {"type": "DEPOSIT", "account": "Girokonto", "date": "2024-01-02",
       "currency": "EUR", "amount": 1000.0},
      {"type": "SALE", "account": "Girokonto", "portfolio": "Depot",
       "date": "2024-06-14", "currency": "EUR", "amount": 20.10, "shares": 100.0,
       "security": {"name": "Nordwind Industrie AG", "currency": "EUR"},
       "units": [{"type": "FEE", "amount": 5.9}, {"type": "TAX", "amount": -25.0}]}
    ]}
    """

    # User story (#1118; found by the α closing act, UAT persona):
    # As the operator dropping a JSON export in the German page,
    # I want the refused row's figures in the page's notation and its cash
    # named as the board names it,
    # so that "amount 20.10 … 25.0 … -4.90" no longer reads as a raw field
    # with dot decimals inside a German sentence.
    #
    # Acceptance criteria:
    # - German: "Zeile 2: Verkauf mit Gesamtpreis 20,10 und Steuererstattung
    #   25,00: Dem Verkauf blieben -4,90 — Zeile nicht übernommen. …".
    # - English: the same figures as "20.10", "25.00", "-4.90".
    test "a JSON file's refused row reads its figures in the page's notation", %{conn: conn} do
      {:ok, view, _html} = live(german(conn), "/imports")
      upload(view, "nominal.json", @nominal_sale_json, "application/json")

      assert text(view, "#parser-warnings-box pre") ==
               "Zeile 2: Verkauf mit Gesamtpreis 20,10 und Steuererstattung 25,00: Dem Verkauf blieben -4,90 — Zeile nicht übernommen. Den Verkauf von Hand buchen, die Erstattung als eigene Steuererstattung."

      {:ok, view, _html} = live(conn, "/imports")
      upload(view, "nominal.json", @nominal_sale_json, "application/json")

      assert text(view, "#parser-warnings-box pre") ==
               "Row 2: sell with Gesamtpreis 20.10 and a tax refund of 25.00: -4.90 would remain for the sale — row not imported. Book the sale by hand, and the refund as a tax refund of its own."
    end
  end

  describe "the correction's layout (board 09 A, rules ② and ③)" do
    # User story (UX-DR27; board 09 A):
    # As the operator on a phone,
    # I want the list as two-line rows and the confirm as the narrow
    # modal's bottom sheet, its primary button first,
    # so that the correction reads and confirms at 390 px as the booking
    # delete does.
    #
    # Acceptance criteria:
    # - Under 560 px the table is hidden (the phone rows show), and the
    #   note's body takes the full width.
    # - The dialog joins the narrow modal's selector lists (460 px; the
    #   bottom sheet under 720 px), its primary confirm on the first line,
    #   Cancel on the next.
    test "the phone rows, the narrow modal and its primary confirm" do
      css = File.read!(Path.expand("../../../priv/static/app.css", __DIR__))

      assert css =~
               ~r/@media \(max-width: 560px\) \{\s*#import-correction-table-wrapper \{\s*display: none;/

      assert css =~
               ~r/\.booking-delete-dialog,\s*\.import-correction-dialog \{\s*max-width: 460px;/

      assert css =~ ~r/dialog\.modal\.import-correction-dialog \{\s*position: fixed;/

      assert css =~
               ~r/\.import-correction-dialog \.modal-footer--band > \.button-primary \{\s*order: 2;/

      assert css =~
               ~r/\.import-correction-dialog \.modal-footer--band > \.button-ghost \{\s*order: 3;/
    end
  end
end
