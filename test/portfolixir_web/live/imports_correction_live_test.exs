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
    #   Row · Date · Booking · Booked · Corrected · Difference (board 03 ④:
    #   the middle column shows what the correction writes, which for a
    #   refund counted twice is not what the file states; the α closing
    #   act's UAT-4), signed and in the sign colours; the same rows as
    #   two-line phone rows.
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
               "Row Date Booking Booked Corrected Difference"

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
    # - The heading, the columns (board 03 ④: Gebucht · Korrigiert ·
    #   Differenz), the note's sentence as board 03 ① gives it
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
               "Zeile Datum Buchung Gebucht Korrigiert Differenz"

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
               "1 Buchung Eintrag 3 · FX-Cash -25,00 EUR Differenz"

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

      # Under the importer's actor, so the line keeps its confirm (a hand
      # edit is named and kept since ADR-0053 A11, Sprint 21 α7).
      {:ok, _edited} =
        Ledger.update_transaction(Actor.import_session(), refund, %{gross_amount: "26.00"})

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

      # Not a hand edit (ADR-0053 A11, Sprint 21 α7: one is named and kept,
      # never written): the refund's cash differs from the file under the
      # importer's own actor, so the confirm still tries to write it.
      {:ok, _edited} =
        Ledger.update_transaction(Actor.import_session(), refund, %{gross_amount: "26.00"})

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
               "2 bookings Entries 2, 4 · EUR-Cash, USD-Cash"

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

      # Under the importer's actor, so the line keeps its confirm (a hand
      # edit is named and kept since ADR-0053 A11, Sprint 21 α7).
      {:ok, _edited} =
        Ledger.update_transaction(Actor.import_session(), refund, %{gross_amount: amount})

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
    # where the page lists it,
    # so that I do not enter the sale by hand a second time.
    #
    # Acceptance criteria:
    # - The parser warning of row 4 names the figures in the sentence of
    #   board ux-design-2026-10-07/01-import-preview ③, says the row is
    #   already imported, and points to the line under "Already imported,
    #   with a different amount" (board ux-design-2026-10-09/07-imports ①,
    #   the stored sale being listed there); it no longer says "Book the
    #   sale by hand".
    # - The correction section lists the stored sale, kept, without a
    #   confirm (ADR-0053 A10, Sprint 21 α7).
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
        "Row 4: sell with Gesamtpreis 20,10 and a tax refund of 25,00: -4,90 would remain for the sale — already imported; listed under “Already imported, with a different amount”."

      {:ok, view, _html} = live(conn, "/imports")
      upload(view, "nominal.csv", @nominal_sale_csv, "text/csv")

      assert text(view, "#parser-warnings-box pre") == warning
      refute render(view) =~ "Book the sale by hand"

      # Since ADR-0053 A10 (#1193, Sprint 21 α7) the stored sale is listed in
      # the correction section, kept, with no confirm.
      assert has_element?(view, "#import-correction-table tbody tr[data-state='kept']")
      refute has_element?(view, "#import-correction-open")

      view |> element("#copy-parser-warnings") |> render_click()
      assert_push_event(view, "copy-to-clipboard", %{text: ^warning})

      {:ok, view, _html} = live(german(conn), "/imports")
      upload(view, "nominal.csv", @nominal_sale_csv, "text/csv")

      assert text(view, "#parser-warnings-box pre") ==
               "Zeile 4: Verkauf mit Gesamtpreis 20,10 und Steuererstattung 25,00: Dem Verkauf blieben -4,90 — bereits importiert; aufgeführt unter „Bereits importiert, mit anderem Betrag“."
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
               "Eintrag 2: Verkauf mit Gesamtpreis 20,10 und Steuererstattung 25,00: Dem Verkauf blieben -4,90 — Eintrag nicht übernommen. Den Verkauf von Hand buchen, die Erstattung als eigene Steuererstattung."

      {:ok, view, _html} = live(conn, "/imports")
      upload(view, "nominal.json", @nominal_sale_json, "application/json")

      assert text(view, "#parser-warnings-box pre") ==
               "Entry 2: sell with Gesamtpreis 20.10 and a tax refund of 25.00: -4.90 would remain for the sale — entry not imported. Book the sale by hand, and the refund as a tax refund of its own."
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

  # Sprint 21 α7 (#1193, #1194, #1205, #1197; ADR-0053's amendment of
  # 2026-10-09, A10 to A12; board 07 `ux-design-2026-10-09/07-imports`, pick
  # N21 = A): every listed booking is a line of the one table, in file
  # order; a line the confirm leaves reads "kept" in its Corrected cell and
  # says why under its booking; the sentence, the total, the button and the
  # dialog count only the lines the confirm writes.
  describe "the correction's line states (board 07, pick N21 = A)" do
    @arbolia ~s("security": {"name": "Arbolia Inc.", "isin": "USEXMPL10014", "currency": "EUR"})

    # The plan's round trip 3: PP shows Test-Cash at 1,049.23.
    defp round_trip_json(time) do
      """
      {"version": 1, "transactions": [
        {"type": "DEPOSIT", "account": "Test-Cash", "date": "2026-03-02", "currency": "EUR", "amount": 1100.0},
        {"type": "PURCHASE", "account": "Test-Cash", "portfolio": "Test-Depot", "date": "2026-03-03", "time": "10:00", "currency": "EUR", "amount": 100.0, "shares": 10.0, #{@arbolia}},
        {"type": "PURCHASE", "account": "Test-Cash", "portfolio": "Test-Depot", "date": "2026-04-02", "time": "10:00", "currency": "EUR", "amount": 100.0, "shares": 10.0, #{@arbolia}},
        {"type": "SALE", "account": "Test-Cash", "portfolio": "Test-Depot", "date": "2026-04-15", "time": "11:00", "currency": "EUR", "amount": 20.10, "shares": 10.0, #{@arbolia},
         "units": [{"type": "FEE", "amount": 5.0}, {"type": "TAX", "amount": -25.0}]},
        {"type": "DIVIDEND", "account": "Test-Cash", "date": "2026-05-15", "currency": "EUR", "amount": 9.13, #{@arbolia}},
        {"type": "SALE", "account": "Test-Cash", "portfolio": "Test-Depot", "date": "2026-06-15", "time": "#{time}", "currency": "EUR", "amount": 120.0, "shares": 10.0, #{@arbolia},
         "units": [{"type": "FEE", "amount": 5.0}, {"type": "TAX", "amount": -25.0}]}
      ]}
      """
    end

    # A sale of K21's shape on `date` at `time`, after a deposit and a
    # purchase of 20 shares (or `purchased`) at 10.00.
    defp sales_json(sales, purchased \\ 20) do
      rows =
        Enum.map_join(sales, ",\n", fn {date, time} ->
          ~s({"type": "SALE", "account": "Test-Cash", "portfolio": "Test-Depot", "date": "#{date}", "time": "#{time}", "currency": "EUR", "amount": 120.0, "shares": 10.0, #{@arbolia}, "units": [{"type": "FEE", "amount": 5.0}, {"type": "TAX", "amount": -25.0}]})
        end)

      """
      {"version": 1, "transactions": [
        {"type": "DEPOSIT", "account": "Test-Cash", "date": "2026-03-02", "currency": "EUR", "amount": 1100.0},
        {"type": "PURCHASE", "account": "Test-Cash", "portfolio": "Test-Depot", "date": "2026-03-03", "time": "10:00", "currency": "EUR", "amount": #{purchased * 10}.0, "shares": #{purchased}.0, #{@arbolia}},
        #{rows}
      ]}
      """
    end

    # The history as an importer before A1 and A5 stored it: every row's
    # cash cell whole, a JSON trade priced the old way, a refund beside its
    # row, and the row A5 now refuses booked with them.
    defp apply_before_the_amendment!(portfolio, body) do
      {:ok, %Preview{} = preview} = PortfolioPerformance.parse(body, filename: "history.json")

      old =
        (preview.entries ++ Enum.map(preview.refused_credits, & &1.entry))
        |> Enum.sort_by(& &1.source_row)
        |> Enum.map(fn %Entry{} = entry ->
          %{entry | gross_amount: entry.hash_amount, price: entry.hash_price || entry.price}
        end)

      {:ok, _result} =
        Imports.apply(%{preview | entries: old, errors: [], refused_credits: []}, %{
          portfolio_id: portfolio.id
        })

      :ok
    end

    defp hand_edit_dividend!(portfolio, amount) do
      dividend =
        portfolio.id
        |> Ledger.list_transactions_for_portfolio()
        |> Enum.find(&(&1.type == "dividend"))

      {:ok, _} = Ledger.update_transaction(Actor.owner_ui(), dividend, %{gross_amount: amount})
      :ok
    end

    defp today, do: PortfolixirWeb.Format.date(Date.utc_today())

    # User story (#1193, #1194, #1205, Sprint 21 α7; the plan's round trip
    # 3; board 07, N21 A):
    # As the operator re-dropping a JSON history imported under the old
    # reading, with a stored sale the preview now refuses, a dividend I
    # changed by hand, and a sale whose time drifted,
    # I want all three in the one table, each kept line saying why and
    # reading "kept", and a confirm that counts the one it corrects,
    # so that I see what the step writes and what I put right myself.
    #
    # Acceptance criteria:
    # - The sentence: "3 bookings already imported differ from this file.
    #   The step below corrects one of them: It was booked as an earlier
    #   version … 2 stay as they are; each line says why."
    # - The refused sale reads "kept", +45.10 stored, -25.00, and its
    #   state names the refund, what would remain, and the remedy (0.10
    #   without fees, the fees 5.00 of their own); the dividend reads
    #   "kept" with "Changed by hand since its import (date) — stays as it
    #   is. Per the file: +9.13."; the drifted sale reads +95.00 and says it
    #   was found by its date and figures.
    # - The total and the button count the one line: "The one booking the
    #   step corrects, together -25.00 EUR: Test-Cash -25.00 EUR." and
    #   "Correct one booking…"; the dialog adds "The other 2 lines of the
    #   list stay as they are."
    # - The confirm brings Test-Cash from 1,099.30 to 1,074.30; the section
    #   then lists the two kept lines without a total and without a button:
    #   "2 bookings already imported differ from this file and stay as they
    #   are; each line says why."
    test "round trip 3: three lines, two kept, a confirm for one", %{conn: conn} do
      portfolio = portfolio!()
      apply_before_the_amendment!(portfolio, round_trip_json("15:30"))
      hand_edit_dividend!(portfolio, "9.20")
      assert Decimal.equal?(balance(portfolio, "Test-Cash"), Decimal.new("1099.30"))

      {:ok, view, _html} = live(conn, "/imports")
      upload(view, "history.json", round_trip_json("15:31"), "application/json")

      assert text(view, "[data-role='import-correction-finding']") ==
               "3 bookings already imported differ from this file. The step below corrects one of them: It was booked as an earlier version of the import read its row — a CSV row's gross value, or a cash amount that also held the tax refund booked beside it. The Portfolio Performance file states what the account moved; the difference is the row's fees and taxes, or that refund. 2 stay as they are; each line says why."

      refused = text(view, "#import-correction-table tbody tr:nth-child(1)")
      assert refused =~ "+45.10 kept -25.00"

      assert refused =~
               "Not corrected automatically — stays as it is: once the tax refund of 25.00 is split off, -4.90 would remain for the sale per the file, and a sale books more than zero. Put it right by hand in the history: change the sale to 0.10 without fees, enter the fees of 5.00 as a booking of their own; the tax refund is already booked."

      assert has_element?(
               view,
               "#import-correction-table tbody tr:nth-child(1) .import-correction__state a[href='/transactions']"
             )

      edited = text(view, "#import-correction-table tbody tr:nth-child(2)")
      assert edited =~ "+9.20 kept -0.07"

      assert edited =~
               "Changed by hand since its import (#{today()}) — stays as it is. Per the file: +9.13."

      drifted = text(view, "#import-correction-table tbody tr:nth-child(3)")
      assert drifted =~ "+120.00 +95.00 -25.00"

      assert drifted =~
               "Found by its date and figures: Portfolio Performance has written this entry differently since the import."

      assert has_element?(view, "#import-correction-table tbody tr[data-state='kept']", "kept")

      assert has_element?(
               view,
               "#import-correction-phone-rows li:nth-child(2) > .import-correction__state"
             )

      assert text(view, ".import-correction__total") ==
               "The one booking the step corrects, together -25.00 EUR: Test-Cash -25.00 EUR."

      assert text(view, "#import-correction-open") == "Correct one booking…"

      view |> element("#import-correction-open") |> render_click()
      assert text(view, "#import-correction-subject") =~ "1 booking"

      assert text(view, "[data-role='import-correction-kept']") ==
               "The other 2 lines of the list stay as they are."

      view |> element("#import-correction-confirm") |> render_click()
      render_async(view, 1_000)

      assert Decimal.equal?(balance(portfolio, "Test-Cash"), Decimal.new("1074.30"))

      assert text(view, "[data-role='import-correction-finding']") ==
               "2 bookings already imported differ from this file and stay as they are; each line says why."

      refute has_element?(view, "#import-correction-open")
      refute has_element?(view, ".import-correction__total")
    end

    # User story (#1193, #1177, Sprint 21 α7; ADR-0053 A9, A10):
    # As the operator re-dropping a JSON sale with a refunded fee and a tax
    # refund, imported under the old reading before A9 refused it,
    # I want its line to give A9's remedy, not A5's,
    # so that I set the sale's cash and leave its fees as stored, and am
    # never told to book its fees on their own.
    #
    # Acceptance criteria:
    # - The sale (FEE 5.00, FEE -2.00, TAX -25.00, amount 120.00) reads
    #   "kept", +145.00 as stored, -25.00, and its state reads "Not
    #   corrected automatically — stays as it is: the import does not book
    #   a fee refund yet, so the sale's fees stay as stored, 7.00. Put it
    #   right by hand in the history: change the sale to 95.00; the tax
    #   refund is already booked."
    test "a stored A9 sale gives A9's remedy", %{conn: conn} do
      portfolio = portfolio!()

      body = """
      {"version": 1, "transactions": [
        {"type": "DEPOSIT", "account": "Test-Cash", "date": "2026-04-01", "currency": "EUR", "amount": 1000.0},
        {"type": "PURCHASE", "account": "Test-Cash", "portfolio": "Test-Depot", "date": "2026-04-02", "time": "10:00", "currency": "EUR", "amount": 100.0, "shares": 10.0, #{@arbolia}},
        {"type": "SALE", "account": "Test-Cash", "portfolio": "Test-Depot", "date": "2026-04-15", "time": "15:30", "currency": "EUR", "amount": 120.0, "shares": 10.0, #{@arbolia},
         "units": [{"type": "FEE", "amount": 5.0}, {"type": "FEE", "amount": -2.0}, {"type": "TAX", "amount": -25.0}]}
      ]}
      """

      apply_before_the_amendment!(portfolio, body)
      assert Decimal.equal?(balance(portfolio, "Test-Cash"), Decimal.new("1045"))

      {:ok, view, _html} = live(conn, "/imports")
      upload(view, "history.json", body, "application/json")

      line = text(view, "#import-correction-table tbody tr:nth-child(1)")
      assert line =~ "+145.00 kept -25.00"

      assert line =~
               "Not corrected automatically — stays as it is: the import does not book a fee refund yet, so the sale's fees stay as stored, 7.00. Put it right by hand in the history: change the sale to 95.00; the tax refund is already booked."
    end

    # ADR-0050's P10 seam: the page's dry run, once started on this test's
    # behalf, waits until `release_refine!/0`.
    defp hold_refine! do
      Application.put_env(:portfolixir, :imports_refine_gate, self())
      on_exit(fn -> Application.delete_env(:portfolixir, :imports_refine_gate) end)
    end

    defp release_refine! do
      assert_receive {:imports_refine_gate, task}, 5_000
      Application.delete_env(:portfolixir, :imports_refine_gate)
      send(task, {:imports_refine_gate, :release})
    end

    defp upload_unanswered!(view, name, content) do
      view
      |> file_input("#pp-import-form", :pp_file, [
        %{
          name: name,
          content: content,
          type: "application/json",
          last_modified: 1_700_000_000_000
        }
      ])
      |> render_upload(name)
    end

    # User story (#1205, Sprint 21 α7; ADR-0053 A12 and its consequences,
    # "its state while the dry run that A12 reads has not answered"):
    # As the operator dropping a drifted re-export of a large history,
    # I want the page to answer at once and the correction section to say
    # that it is still comparing by date and figures, without a confirm,
    # until the background dry run answers,
    # so that the page never freezes on the upload and I never confirm a
    # list that is still growing.
    #
    # Acceptance criteria:
    # - K23's sale stored under the old reading, its re-export drifted by a
    #   minute: before the dry run answers, the section shows "comparing by
    #   date and figures" (aria-busy), no line and no confirm.
    # - A re-drop whose sale is a hash hit and whose second sale drifted
    #   lists the hash hit at once, with "found by import hash · comparing
    #   by date and figures", and no confirm.
    # - Once the dry run answers, the drifted sale is listed by its date and
    #   figures (+120.00 +95.00 -25.00) with a confirm, and the cue is gone.
    test "the section says it is still comparing until the dry run answers", %{conn: conn} do
      portfolio = portfolio!()

      apply_before_the_amendment!(
        portfolio,
        sales_json([{"2026-06-15", "15:30"}, {"2026-08-17", "15:30"}])
      )

      hold_refine!()
      {:ok, view, _html} = live(conn, "/imports")

      upload_unanswered!(
        view,
        "history.json",
        sales_json([{"2026-06-15", "15:31"}, {"2026-08-17", "15:31"}])
      )

      assert text(view, "#import-correction [data-role='import-correction-pending']") ==
               "comparing by date and figures"

      assert has_element?(view, "#import-correction [aria-busy='true']")
      refute has_element?(view, "#import-correction-table")
      refute has_element?(view, "#import-correction-open")

      release_refine!()
      render_async(view)

      refute has_element?(view, "[data-role='import-correction-pending']")

      assert text(view, "#import-correction-table tbody tr:nth-child(1)") =~
               "+120.00 +95.00 -25.00"

      assert text(view, "#import-correction-table tbody tr:nth-child(1)") =~
               "Found by its date and figures"

      assert text(view, "#import-correction-open") == "Correct 2 bookings…"

      hold_refine!()
      {:ok, view, _html} = live(conn, "/imports")

      upload_unanswered!(
        view,
        "history.json",
        sales_json([{"2026-06-15", "15:30"}, {"2026-08-17", "15:31"}])
      )

      assert text(view, "#import-correction [data-role='import-correction-pending']") ==
               "found by import hash · comparing by date and figures"

      assert [_hash_hit] = view |> element("#import-correction-table tbody") |> render() |> rows()
      refute has_element?(view, "#import-correction-open")

      release_refine!()
      render_async(view)

      refute has_element?(view, "[data-role='import-correction-pending']")
      assert text(view, "#import-correction-open") == "Correct 2 bookings…"
    end

    defp rows(html), do: html |> Floki.parse_fragment!() |> Floki.find("tr")

    # User story (#1205, Sprint 21 α7; ADR-0053 A12's twin rule; board 07):
    # As the operator whose two equal sales both drifted,
    # I want each listed with the count of the bookings that match it, and
    # no confirm in the section,
    # so that the page never offers to correct one of two twins.
    #
    # Acceptance criteria:
    # - Both lines read "kept" and "2 stored bookings match its date and
    #   figures — stays as it is. Correct the right one by hand in the
    #   history."; the section has no button and no total.
    test "twins are listed without a confirm", %{conn: conn} do
      portfolio = portfolio!()

      apply_before_the_amendment!(
        portfolio,
        sales_json([{"2026-06-15", "15:30"}, {"2026-06-15", "16:10"}])
      )

      {:ok, view, _html} = live(conn, "/imports")

      upload(
        view,
        "history.json",
        sales_json([{"2026-06-15", "15:31"}, {"2026-06-15", "16:11"}]),
        "application/json"
      )

      for n <- [1, 2] do
        assert text(view, "#import-correction-table tbody tr:nth-child(#{n})") =~
                 "2 stored bookings match its date and figures — stays as it is. Correct the right one by hand in the history."
      end

      refute has_element?(view, "#import-correction-open")
    end

    defp sale_cash(portfolio, date) do
      portfolio.id
      |> Ledger.list_transactions_for_portfolio()
      |> Enum.filter(&(&1.type == "sell" and &1.date == date))
      |> Enum.map(&Decimal.to_string(&1.gross_amount))
    end

    # User story (#1205, Sprint 21 α7; ADR-0053 A12 and its note of
    # 2026-10-31 "the confirm writes what its dialog offered"):
    # As the operator whose page could not compare by date and figures (its
    # dry run stopped), who confirms the one booking the section lists,
    # I want the confirm to write that booking alone, and to name one it
    # finds under its lock that the list did not show,
    # so that a confirm never writes a booking its dialog did not offer.
    #
    # Acceptance criteria:
    # - Two sales stored under the old reading (Test-Cash 1,190.00), the
    #   re-drop's first a hash hit, its second drifted by a minute; the dry
    #   run stops: the section lists the hash hit alone, "Correct one
    #   booking…".
    # - The confirm corrects it alone: Test-Cash 1,165.00, the drifted sale
    #   still 120.00; the result reads "One booking corrected: Test-Cash
    #   -25.00 EUR. The journal keeps the previous amount. One more booking
    #   with a different amount was found since the list was shown and is
    #   not corrected. Drop the same file again to correct it."
    test "a stopped dry run's confirm writes only the line it listed", %{conn: conn} do
      portfolio = portfolio!()

      apply_before_the_amendment!(
        portfolio,
        sales_json([{"2026-06-15", "15:30"}, {"2026-08-17", "15:30"}])
      )

      assert Decimal.equal?(balance(portfolio, "Test-Cash"), Decimal.new("1190.00"))

      hold_refine!()
      {:ok, view, _html} = live(conn, "/imports")

      upload_unanswered!(
        view,
        "history.json",
        sales_json([{"2026-06-15", "15:30"}, {"2026-08-17", "15:31"}])
      )

      assert_receive {:imports_refine_gate, held}, 5_000
      Application.delete_env(:portfolixir, :imports_refine_gate)

      ExUnit.CaptureLog.capture_log(fn ->
        Process.exit(held, :kill)
        render_async(view)
      end)

      refute has_element?(view, "[data-role='import-correction-pending']")
      assert text(view, "#import-correction-open") == "Correct one booking…"

      view |> element("#import-correction-open") |> render_click()
      view |> element("#import-correction-confirm") |> render_click()
      render_async(view)

      assert text(view, "#import-correction-result [role='status']") ==
               "Note One booking corrected: Test-Cash -25.00 EUR. The journal keeps the previous amount. One more booking with a different amount from the file was found since the list was shown and is not corrected. Drop the same file again to correct it. ×"

      assert Decimal.equal?(balance(portfolio, "Test-Cash"), Decimal.new("1165.00"))
      assert sale_cash(portfolio, ~D[2026-08-17]) == ["120.000000"]
    end

    # User story (#1205, Sprint 21 α7; ADR-0053 A12's twin rule and its
    # note of 2026-10-31 "the confirm writes what its dialog offered"):
    # As the operator whose dialog says a twin stays as it is,
    # I want the confirm to leave it as it is when the other twin is
    # deleted before I confirm,
    # so that the confirm writes exactly the lines the dialog offered.
    #
    # Acceptance criteria:
    # - Three sales stored under the old reading, two of them equal on
    #   2026-06-15 (Test-Cash 1,235.00); the re-drop drifts the first: it
    #   reads "2 stored bookings match …", the third sale carries the one
    #   confirm.
    # - With the dialog open, the second sale of 2026-06-15 is deleted
    #   (Test-Cash 1,115.00); the confirm corrects the third sale alone:
    #   Test-Cash 1,090.00, the remaining 2026-06-15 sale still 120.00, and
    #   the result names one more booking found since.
    test "a twin deleted before the confirm stays as the dialog said", %{conn: conn} do
      portfolio = portfolio!()

      apply_before_the_amendment!(
        portfolio,
        sales_json(
          [{"2026-06-15", "15:30"}, {"2026-06-15", "16:10"}, {"2026-08-17", "15:30"}],
          30
        )
      )

      assert Decimal.equal?(balance(portfolio, "Test-Cash"), Decimal.new("1235.00"))

      {:ok, view, _html} = live(conn, "/imports")

      upload(
        view,
        "history.json",
        sales_json([{"2026-06-15", "15:31"}, {"2026-08-17", "15:30"}], 30),
        "application/json"
      )

      assert text(view, "#import-correction-table tbody tr:nth-child(1)") =~
               "2 stored bookings match its date and figures — stays as it is."

      assert text(view, "#import-correction-open") == "Correct one booking…"
      view |> element("#import-correction-open") |> render_click()

      twin =
        portfolio.id
        |> Ledger.list_transactions_for_portfolio()
        |> Enum.filter(&(&1.type == "sell" and &1.date == ~D[2026-06-15]))
        |> Enum.max_by(& &1.id)

      {:ok, _} = Ledger.delete_transaction(Actor.owner_ui(), twin)
      assert Decimal.equal?(balance(portfolio, "Test-Cash"), Decimal.new("1115.00"))

      view |> element("#import-correction-confirm") |> render_click()
      render_async(view)

      assert text(view, "#import-correction-result [role='status']") =~
               "One more booking with a different amount from the file was found since the list was shown and is not corrected."

      assert Decimal.equal?(balance(portfolio, "Test-Cash"), Decimal.new("1090.00"))
      assert sale_cash(portfolio, ~D[2026-06-15]) == ["120.000000"]
    end

    # User story (#1197, Sprint 21 α7; board 07 ⑧ and its found while
    # drawing 12):
    # As the operator correcting bookings on an account whose balance I set
    # after them,
    # I want the dialog to name the set balance that absorbs the change, and
    # the part it absorbs where it absorbs only part,
    # so that I am not told the balance moves when it does not.
    #
    # Acceptance criteria:
    # - A drifted sale on 2026-06-15 and a set balance of 2026-07-01: the
    #   dialog reads "On Test-Cash, the set balance of 2026-07-01 absorbs
    #   the 25.00 EUR: its balance stays as it is."; the confirm leaves the
    #   balance at the set 1,000.00, and the result adds "— the set balance
    #   of 2026-07-01 holds Test-Cash's balance".
    # - Two drifted sales, on 2026-06-15 and 2026-08-17, around the same set
    #   balance: "On Test-Cash, the set balance of 2026-07-01 absorbs 25.00
    #   EUR of the 50.00 EUR: its balance changes by -25.00 EUR."
    test "the dialog names a later set balance that absorbs the change", %{conn: conn} do
      portfolio = portfolio!()
      apply_before_the_amendment!(portfolio, sales_json([{"2026-06-15", "15:30"}]))
      cash = Enum.find(Portfolios.list_cash_accounts(), &(&1.name == "Test-Cash"))

      {:ok, _anchor} =
        Ledger.set_cash_balance(Actor.owner_ui(), cash, %{date: ~D[2026-07-01], amount: "1000"})

      {:ok, view, _html} = live(conn, "/imports")
      upload(view, "history.json", sales_json([{"2026-06-15", "15:31"}]), "application/json")
      view |> element("#import-correction-open") |> render_click()

      assert text(view, "[data-role='import-correction-consequence']") =~
               "On Test-Cash, the set balance of 2026-07-01 absorbs the 25.00 EUR: its balance stays as it is."

      view |> element("#import-correction-confirm") |> render_click()
      render_async(view, 1_000)
      assert Decimal.equal?(balance(portfolio, "Test-Cash"), Decimal.new("1000"))

      # The account's name is isolated in <bdi>; the text helper joins the
      # nodes with a space.
      assert text(view, "#import-correction-result") =~
               ~r/— the set balance of 2026-07-01 holds Test-Cash ?'s balance/
    end

    test "a set balance between two corrected bookings absorbs only part", %{conn: conn} do
      portfolio = portfolio!()

      apply_before_the_amendment!(
        portfolio,
        sales_json([{"2026-06-15", "15:30"}, {"2026-08-17", "15:30"}])
      )

      cash = Enum.find(Portfolios.list_cash_accounts(), &(&1.name == "Test-Cash"))

      {:ok, _anchor} =
        Ledger.set_cash_balance(Actor.owner_ui(), cash, %{date: ~D[2026-07-01], amount: "1000"})

      {:ok, view, _html} = live(conn, "/imports")

      upload(
        view,
        "history.json",
        sales_json([{"2026-06-15", "15:31"}, {"2026-08-17", "15:31"}]),
        "application/json"
      )

      view |> element("#import-correction-open") |> render_click()

      assert text(view, "[data-role='import-correction-consequence']") =~
               "On Test-Cash, the set balance of 2026-07-01 absorbs 25.00 EUR of the 50.00 EUR: its balance changes by -25.00 EUR."
    end

    # User story (#1194, Sprint 21 α7; ADR-0053 A11, K22):
    # As the operator confirming the correction of a JSON sale whose cash
    # agrees with the file and whose price does not,
    # I want the result line to say that the price was corrected and the
    # cash kept,
    # so that it never reads "One booking corrected: ." with nothing named.
    #
    # Acceptance criteria:
    # - K22's sale, stored with the file's cash and the price 12.50 by no
    #   other actor's edit: the confirm writes the price (10.00), and the result
    #   reads "One booking corrected: the price, the cash kept. The journal
    #   keeps the previous price."; in German "Eine Buchung korrigiert: der
    #   Kurs, der Betrag bleibt. Das Journal hält den bisherigen Kurs."
    test "K22: a price-only confirm says the price was corrected", %{conn: conn} do
      assert price_only_result(conn) ==
               "Note One booking corrected: the price, the cash kept. The journal keeps the previous price. ×"
    end

    test "K22: a price-only confirm says so in German", %{conn: conn} do
      assert price_only_result(german(conn)) ==
               "Hinweis Eine Buchung korrigiert: der Kurs, der Betrag bleibt. Das Journal hält den bisherigen Kurs. ×"
    end

    # K22's sale stored with the file's cash and the price 12.50, by no other
    # actor's edit; the page re-drops the file and confirms its correction.
    defp price_only_result(conn) do
      body = sales_json([{"2026-06-15", "15:30"}], 10)
      portfolio = portfolio!()
      apply_as_read_today!(portfolio, body, "history.json")

      sale =
        portfolio.id
        |> Ledger.list_transactions_for_portfolio()
        |> Enum.find(&(&1.type == "sell"))

      store_old_price!(sale, "12.50")

      {:ok, view, _html} = live(conn, "/imports")
      upload(view, "history.json", body, "application/json")
      view |> element("#import-correction-open") |> render_click()
      view |> element("#import-correction-confirm") |> render_click()
      render_async(view, 1_000)

      assert Decimal.equal?(Repo.get!(Transaction, sale.id).price, Decimal.new("10.00"))
      text(view, "#import-correction-result [role='status']")
    end

    # User story (#1205, Sprint 21 α7; ADR-0053 A12; board 07):
    # As the operator who confirms the import while a row found by its date
    # and figures is left uncorrected,
    # I want the done page's skip list to say that row is already imported
    # with a different amount, and the amount stored,
    # so that two lines under "is not corrected" no list says it has the
    # same amount.
    #
    # Acceptance criteria:
    # - The drifted sale (stored at 120.00 under the old reading, the file
    #   stating 95.00) is skipped under its own group, open: "1 · already
    #   imported, with a different amount — not corrected by this import",
    #   its line "Row 3: Sell … — 120.00 EUR stored"; the economic group
    #   ("same date, security, quantity and amount") keeps only the refund
    #   stored beside it.
    # - In German: "bereits importiert, mit anderem Betrag — von diesem
    #   Import nicht korrigiert" and "— 120,00 EUR gespeichert".
    test "the done page names a row found by its figures as differing", %{conn: conn} do
      portfolio = portfolio!()
      apply_before_the_amendment!(portfolio, sales_json([{"2026-06-15", "15:30"}], 10))

      for {conn, head, stored} <- [
            {conn, "1 · already imported, with a different amount — not corrected by this import",
             "— 120.00 EUR stored"},
            {german(conn),
             "1 · bereits importiert, mit anderem Betrag — von diesem Import nicht korrigiert",
             "— 120,00 EUR gespeichert"}
          ] do
        {:ok, view, _html} = live(conn, "/imports")

        upload(
          view,
          "history.json",
          sales_json([{"2026-06-15", "15:31"}], 10),
          "application/json"
        )

        assert has_element?(view, "#import-correction-open")

        view |> element("form#pp-import-apply") |> render_submit()
        # The apply, then the done page's own dry run for the correction.
        render_async(view, 1_000)
        render_async(view, 1_000)

        assert has_element?(view, "[data-role='correction-not-applied']")

        # The refund stored beside the sale is the one economic duplicate.
        economics = text(view, "[data-role='duplicate-group'][data-layer='economics']")
        assert economics =~ ~r/^1 · /
        refute economics =~ ~r/(Entry|Eintrag) 3: /

        group = "[data-role='duplicate-group'][data-layer='differs'][open]"
        assert text(view, group <> " summary") == head
        line = text(view, group <> " li")
        assert line =~ ~r/^(Entry|Eintrag) 3: /
        assert String.ends_with?(line, stored)
      end
    end

    # K17's transfer (ADR-0053 K20): 100.00 from Test-Cash to Test-Savings
    # with a tax unit of -5.00, after a deposit of 1,000.00.
    @k20_json """
    {"version": 1, "transactions": [
      {"type": "DEPOSIT", "account": "Test-Cash", "date": "2026-02-09", "currency": "EUR", "amount": 1000.0},
      {"type": "CASH_TRANSFER", "account": "Test-Cash", "otherAccount": "Test-Savings", "date": "2026-02-10", "currency": "EUR", "amount": 100.0,
       "units": [{"type": "TAX", "amount": -5.0}]}
    ]}
    """

    # Sprint 20's reading (release 2026.10.13): the row A8 now refuses
    # booked as the preview keeps it, its refund split off beside it.
    defp apply_as_sprint_20!(portfolio, body) do
      {:ok, %Preview{} = preview} = PortfolioPerformance.parse(body, filename: "history.json")

      entries =
        (preview.entries ++ Enum.map(preview.refused_credits, & &1.entry))
        |> Enum.sort_by(& &1.source_row)

      {:ok, _result} =
        Imports.apply(%{preview | entries: entries, errors: [], refused_credits: []}, %{
          portfolio_id: portfolio.id
        })

      :ok
    end

    # User story (#1193, Sprint 21 α7; ADR-0053 A10, K20):
    # As the operator re-dropping a transfer with a tax refund that was
    # imported before A8 refused it,
    # I want its line to show each cash account the transfer moves, as
    # stored, and the difference to the file,
    # so that I see that Test-Savings holds the refund Portfolio Performance
    # never moved, not only that Test-Cash agrees.
    #
    # Acceptance criteria:
    # - Stored under Sprint 20's reading: the table shows Test-Cash -100.00
    #   kept 0.00 and, on a line of its own, Test-Savings +105.00 kept
    #   -5.00; the phone rows show the same two accounts.
    # - No confirm.
    # - Stored under the old reading (the second test): Test-Cash -95.00
    #   kept -5.00 and Test-Savings +100.00 kept 0.00.
    test "K20: a refused transfer shows each account it moves", %{conn: conn} do
      portfolio = portfolio!()
      apply_as_sprint_20!(portfolio, @k20_json)

      {:ok, view, _html} = live(conn, "/imports")
      upload(view, "history.json", @k20_json, "application/json")

      assert text(view, "#import-correction-table tbody tr:nth-child(1)") =~
               "-100.00 kept 0.00"

      assert text(view, "#import-correction-table tbody tr:nth-child(2)") ==
               "Test-Savings +105.00 kept -5.00"

      assert text(view, "#import-correction-phone-rows li:nth-child(2)") =~
               "Test-Savings"

      assert text(view, "#import-correction-phone-rows li:nth-child(2)") =~
               "-5.00 +105.00 → kept"

      refute has_element?(view, "#import-correction-open")
    end

    test "K20: a refused transfer stored under the old reading shows each account it moves", %{
      conn: conn
    } do
      portfolio = portfolio!()
      apply_before_the_amendment!(portfolio, @k20_json)

      {:ok, view, _html} = live(conn, "/imports")
      upload(view, "history.json", @k20_json, "application/json")

      assert text(view, "#import-correction-table tbody tr:nth-child(1)") =~
               "-95.00 kept -5.00"

      assert text(view, "#import-correction-table tbody tr:nth-child(2)") ==
               "Test-Savings +100.00 kept 0.00"
    end

    # User story (board 07, N21 A and found while drawing 1):
    # As the operator reading a state sentence beside the figures,
    # I want the table to fill the note and wrap, not to widen past it,
    # so that no figure column is pushed out of view.
    #
    # Acceptance criteria:
    # - The correction table takes its min-content as its floor; the state
    #   is a 12 px muted line, a kept line's in the text colour; on a phone
    #   row it spans the row.
    test "the table fills its note and wraps; the state line's rules" do
      css = File.read!(Path.expand("../../../priv/static/app.css", __DIR__))

      assert css =~
               ~r/\.data-table-wrapper > #import-correction-table \{\s*min-width: min-content;/

      assert css =~ ~r/\.import-correction__state \{[^}]*font-size: 12px;/
      assert css =~ ~r/\.phone-row > \.import-correction__state \{\s*grid-column: 1 \/ -1;/
      assert css =~ ~r/\.import-correction__state--kept \{\s*color: var\(--color-text\);/
    end
  end

  # A sale stored with the file's cash and an older price, as an import
  # stored it before ADR-0053 A2; written below the ledger, since an edit of
  # the price alone on a stored-cash trade states its cash since #1371 (the
  # ADR-0053 amendment of 2026-11-02). No actor's edit is journaled.
  defp store_old_price!(%Transaction{} = row, price) do
    {:ok, stored} =
      Repo.transaction(fn ->
        Repo.query!("SELECT set_config('portfolixir.journal_actor', 'import_session', true)")
        row |> Ecto.Changeset.change(price: Decimal.new(price)) |> Repo.update!()
      end)

    stored
  end
end
