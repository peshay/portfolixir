defmodule PortfolixirWeb.ImportsRefundRowErrorsLiveTest do
  # ADR-0053 A8 and A9 (the amendment of 2026-10-09; #1188, #1177's negative
  # FEE unit) on the Imports page, as board ux-design-2026-10-09/07-imports ③
  # draws them: a delivery or a transfer with a tax refund, and a booking
  # with a negative fee, are parser warnings in the one attention note,
  # their entries out of the counts, and the rest of the file previews and
  # books. Every name and amount is synthetic.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  # K16's history with K18's purchase beside it: a deposit, an inbound
  # delivery with a TAX unit of -0.40, a purchase of 5 shares and a purchase
  # with FEE units 5.00 and -2.00.
  @json """
  {"version": 1, "transactions": [
    {"type": "DEPOSIT", "account": "Test-Cash", "date": "2026-02-02",
     "currency": "EUR", "amount": 2000.00},
    {"type": "INBOUND_DELIVERY", "portfolio": "Test-Depot", "date": "2026-02-03",
     "currency": "EUR", "amount": 999.60, "shares": 10,
     "security": {"name": "Arbolia Inc.", "currency": "EUR"},
     "units": [{"type": "TAX", "amount": -0.40}]},
    {"type": "PURCHASE", "account": "Test-Cash", "portfolio": "Test-Depot",
     "date": "2026-02-04", "currency": "EUR", "amount": 501.00, "shares": 5,
     "security": {"name": "Arbolia Inc.", "currency": "EUR"},
     "units": [{"type": "FEE", "amount": 1.00}]},
    {"type": "PURCHASE", "account": "Test-Cash", "portfolio": "Test-Depot",
     "date": "2026-03-03", "currency": "EUR", "amount": 1003.00, "shares": 10,
     "security": {"name": "Arbolia Inc.", "currency": "EUR"},
     "units": [{"type": "FEE", "amount": 5.00}, {"type": "FEE", "amount": -2.00}]}
  ]}
  """

  # K17's transfer as a Portfolio Performance CSV writes it.
  @csv """
  Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle
  2026-02-02 00:00:00;Einlage;;;;1.000,00;;;1.000,00;Test-Cash;;;
  2026-02-10 00:00:00;Umbuchung (Ausgang);;;;105,00;;-5,00;100,00;Test-Cash;Test-Savings;;
  """

  # User story (#1188, #1177; Sprint 21 α5; board 07 ③):
  # As the operator dropping a Portfolio Performance export whose delivery
  # carries a tax refund, or whose purchase carries a negative fee unit,
  # I want each such row named in the parser warnings with what to do, and
  # the rest of the file to preview and import,
  # so that one row the ledger cannot carry never fails the whole file, and
  # I know which bookings to enter by hand.
  #
  # Acceptance criteria:
  # - German: the note reads "Zeile 2: Einlieferung mit Steuererstattung
  #   0,40: … — Zeile nicht übernommen. …" and "Zeile 4: Buchung mit einer
  #   negativen Gebühr (-2,00): … (3,00)."; the Warnings card counts 2, and
  #   the Entries card counts the 2 entries that import (the delivery's
  #   split-off refund is not among them).
  # - English: the same rows in the board's English.
  # - The deposit and the purchase of 5 shares preview under the import's
  #   confirm, one each.
  test "a delivery's tax refund and a negative fee are parser warnings, and the rest previews",
       %{conn: conn} do
    {:ok, view, _html} = live(german(conn), "/imports")
    upload(view, "refunds.json", @json, "application/json")

    assert text(view, "#parser-warnings-box pre") ==
             "Zeile 2: Einlieferung mit Steuererstattung 0,40: Eine Einlieferung bewegt kein " <>
               "Geld, die Erstattung hätte kein Konto — Zeile nicht übernommen. Die " <>
               "Einlieferung ohne sie von Hand buchen; ist Geld geflossen, das als eigene " <>
               "Steuererstattung. Zeile 4: Buchung mit einer negativen Gebühr (-2,00): Eine " <>
               "Gebührenerstattung bucht der Import noch nicht — Zeile nicht übernommen. Die " <>
               "Buchung von Hand erfassen, mit den Gebühren abzüglich der Erstattung (3,00)."

    assert stat(view, "Warnungen") == "2"
    assert stat(view, "Einträge") == "2"

    {:ok, view, _html} = live(conn, "/imports")
    upload(view, "refunds.json", @json, "application/json")

    assert text(view, "#parser-warnings-box pre") ==
             "Row 2: inbound delivery with a tax refund of 0.40: an inbound delivery moves no " <>
               "cash, so the refund would have no account — row not imported. Book the inbound " <>
               "delivery by hand without it; if money did move, book that as a tax refund of " <>
               "its own. Row 4: booking with a negative fee (-2.00): the import does not book " <>
               "a fee refund yet — row not imported. Enter the booking by hand, with its fees " <>
               "less the refund (3.00)."

    # The rest previews: the deposit and the purchase of 5 shares, under
    # the import's own confirm (their booking is negative_tax_booking_test's).
    assert has_element?(view, "#pp-import-confirm")
    assert kinds(view) == [{"Buy", "1"}, {"Deposit", "1"}]
  end

  # User story (#1188; Sprint 21 α5; board 07 ③):
  # As the operator dropping a Portfolio Performance CSV whose cash
  # transfer carries a negative Steuern,
  # I want the row named with its remedy,
  # so that no refund lands on one side of the transfer only.
  #
  # Acceptance criteria:
  # - German: "Zeile 3: Umbuchung mit Steuererstattung 5,00: Eine Umbuchung
  #   bewegt Geld zwischen zwei Konten, eine abgespaltene Erstattung landete
  #   nur auf einer Seite — Zeile nicht übernommen. …".
  test "a CSV transfer's tax refund is a parser warning", %{conn: conn} do
    {:ok, view, _html} = live(german(conn), "/imports")
    upload(view, "transfer.csv", @csv, "text/csv")

    assert text(view, "#parser-warnings-box pre") ==
             "Zeile 3: Umbuchung mit Steuererstattung 5,00: Eine Umbuchung bewegt Geld " <>
               "zwischen zwei Konten, eine abgespaltene Erstattung landete nur auf einer Seite " <>
               "— Zeile nicht übernommen. Die Umbuchung ohne sie von Hand buchen; ist Geld " <>
               "geflossen, das als eigene Steuererstattung."

    assert stat(view, "Warnungen") == "1"
    assert stat(view, "Einträge") == "1"
  end

  defp upload(view, name, content, type) do
    view
    |> file_input("#pp-import-form", :pp_file, [
      %{name: name, content: content, type: type, last_modified: 1_700_000_000_000}
    ])
    |> render_upload(name)

    render_async(view)
  end

  defp german(conn), do: put_req_header(conn, "accept-language", "de-DE,de;q=0.9")

  # The value of the summary card labelled `label`.
  defp stat(view, label) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find(".import-stat-card")
    |> Enum.find_value(fn card ->
      if card |> Floki.find(".label") |> Floki.text() |> String.trim() == label,
        do: card |> Floki.find(".value") |> Floki.text() |> String.trim()
    end)
  end

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

  # The "Counts by kind" chips, as {label, count}.
  defp kinds(view) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find(".kind-chip")
    |> Enum.map(fn chip ->
      {chip |> Floki.find(".name") |> Floki.text() |> String.trim(),
       chip |> Floki.find(".count") |> Floki.text() |> String.trim()}
    end)
  end
end
