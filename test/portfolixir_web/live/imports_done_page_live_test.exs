defmodule PortfolixirWeb.ImportsDonePageLiveTest do
  # Board 07 ⑦ and ⑨ of the 2026-10-09 pass: what the Imports page says
  # when work remains after a step that reads as done — the lead note above
  # a correction section (#1207 (1)) — and what the done page names after
  # the apply: the rows the preview refused (#1207 (2)), the portfolio
  # record a first import created (#1178), the bookings that reached an
  # account through a former name (#962) and the outline secondary action
  # (#1181). Every name, amount and identifier is synthetic.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Entry
  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Imports.Preview
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  @fund %{"name" => "Wrenfield Gardens AG", "isin" => "DE000EXMPL17", "currency" => "EUR"}

  # User story (#1207 (1), Sprint 21 γ7; board 07 ⑦): As the operator who
  # drops a file again that books nothing new but corrects a booking, I
  # want the lead note to say that work remains below and where, so that
  # "the import creates nothing" does not read as "nothing to do".
  #
  # Acceptance criteria:
  # - The nothing-to-import note ends "One booking already imported differs
  #   from the file, though: correct it under “Already imported, with a
  #   different amount” below.", the heading a link to `#import-correction`;
  #   the note stays a `note`.
  # - With only lines the confirm leaves, it ends "…: see why under
  #   “Already imported, with a different amount” below."
  # - In German: "Eine bereits importierte Buchung weicht aber von der Datei
  #   ab: unten unter „Bereits importiert, mit anderem Betrag“ korrigieren."
  test "the lead note names the correction section below when one shows", %{conn: conn} do
    portfolio = portfolio!()
    apply_old_reading!(portfolio, json(history()))

    {:ok, view, _html} = live(conn, "/imports")
    upload(view, "history.json", json(history()))

    lead = "[data-role='nothing-to-import']"
    assert has_element?(view, lead <> ".data-note--note")

    assert text(view, lead <> " .data-note__body") =~
             "The import creates nothing: no booking, no account, no depot, no security. " <>
               "One booking already imported differs from the file, though: correct it under " <>
               "“Already imported, with a different amount” below."

    assert has_element?(
             view,
             lead <> " a[href='#import-correction']",
             "“Already imported, with a different amount”"
           )

    {:ok, german, _html} = live(german(conn), "/imports")
    upload(german, "history.json", json(history()))

    assert text(german, lead <> " .data-note__body") =~
             "Eine bereits importierte Buchung weicht aber von der Datei ab: unten unter " <>
               "„Bereits importiert, mit anderem Betrag“ korrigieren."

    sale = Enum.find(Ledger.list_transactions_for_portfolio(portfolio.id), &(&1.type == "sell"))
    {:ok, _} = Ledger.update_transaction(Actor.owner_ui(), sale, %{gross_amount: "119.00"})

    {:ok, view, _html} = live(conn, "/imports")
    upload(view, "history.json", json(history()))

    assert text(view, lead <> " .data-note__body") =~
             "One booking already imported differs from the file, though: see why under " <>
               "“Already imported, with a different amount” below."
  end

  # User story (#1207 (2), Sprint 21 γ7; board 07 ⑨): As the operator who
  # confirmed an import whose preview refused rows, I want the done page to
  # list those rows first, each with its remedy, so that a refused sale I
  # still have to book by hand is not forgotten once the page says
  # "Import complete".
  #
  # Acceptance criteria:
  # - First among the lists, in `.import-skipped`'s form
  #   (`data-role="refused-rows"`): "2 entries the preview refused were not
  #   imported:", then each entry's message with its remedy, "Entry 2: …"
  #   and "Entry 4: …", as the parser warnings said them.
  # - A CSV file's single refused row: "One row the preview refused was not
  #   imported:", then "Row 3: transfer without a counter account — row not
  #   imported".
  # - In German: "2 Einträge, die die Vorschau abgelehnt hat, sind nicht
  #   importiert:".
  test "the done page lists the rows the preview refused, first, with their remedies",
       %{conn: conn} do
    _portfolio = portfolio!()
    body = json(refused_rows())

    {:ok, view, _html} = live(conn, "/imports")
    upload(view, "refused.json", body)
    confirm(view)

    refused = "[data-role='refused-rows']"
    assert has_element?(view, ".import-skipped" <> refused)
    assert text(view, refused <> " p") == "2 entries the preview refused were not imported:"

    assert [first, second] = texts(view, refused <> " li")

    assert first =~
             ~r/^Entry 2: inbound delivery with a tax refund of 0\.40: .* — entry not imported\. /

    assert second =~
             ~r/^Entry 4: booking with a negative fee \(-2\.00\): .* — entry not imported\. /

    assert first_list(view) == "refused-rows"

    csv = """
    Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle
    2026-01-02;Einlage;;;;1.000,00;;;;Test-Cash;;;
    2026-01-05;Umbuchung (Ausgang);;;;100,00;;;;Test-Cash;;;
    """

    {:ok, view, _html} = live(conn, "/imports")
    upload(view, "export.csv", csv, "text/csv")
    confirm(view)

    assert text(view, refused <> " p") == "One row the preview refused was not imported:"

    assert texts(view, refused <> " li") == [
             "Row 3: transfer without a counter account — row not imported"
           ]

    {:ok, german, _html} = live(german(conn), "/imports")
    upload(german, "refused.json", body)
    confirm(german)

    assert text(german, refused <> " p") ==
             "2 Einträge, die die Vorschau abgelehnt hat, sind nicht importiert:"
  end

  # --- the exports -------------------------------------------------------------

  defp history do
    [
      deposit("1000.00"),
      %{
        "type" => "PURCHASE",
        "account" => "Test-Cash",
        "portfolio" => "Depot Muster",
        "date" => "2026-01-15",
        "time" => "10:00",
        "currency" => "EUR",
        "amount" => num("100.00"),
        "shares" => num("10"),
        "security" => @fund
      },
      %{
        "type" => "SALE",
        "account" => "Test-Cash",
        "portfolio" => "Depot Muster",
        "date" => "2026-03-16",
        "time" => "15:30",
        "currency" => "EUR",
        "amount" => num("120.00"),
        "shares" => num("10"),
        "security" => @fund,
        "units" => [
          %{"type" => "FEE", "amount" => num("5.00")},
          %{"type" => "TAX", "amount" => num("-25.00")}
        ]
      }
    ]
  end

  # A deposit, a delivery with a tax refund and a booking with a negative
  # fee (board 07 ③, the two row errors), and a deposit.
  defp refused_rows do
    [
      deposit("1000.00"),
      %{
        "type" => "INBOUND_DELIVERY",
        "portfolio" => "Depot Muster",
        "date" => "2026-01-15",
        "time" => "10:00",
        "currency" => "EUR",
        "amount" => num("100.00"),
        "shares" => num("10"),
        "security" => @fund,
        "units" => [%{"type" => "TAX", "amount" => num("-0.40")}]
      },
      deposit("50.00"),
      %{
        "type" => "INTEREST",
        "account" => "Test-Cash",
        "date" => "2026-02-28",
        "currency" => "EUR",
        "amount" => num("1.00"),
        "units" => [%{"type" => "FEE", "amount" => num("-2.00")}]
      }
    ]
  end

  defp deposit(amount) do
    %{
      "type" => "DEPOSIT",
      "account" => "Test-Cash",
      "date" => "2026-01-02",
      "currency" => "EUR",
      "amount" => num(amount)
    }
  end

  defp num(digits), do: Jason.Fragment.new(digits)

  defp json(rows), do: Jason.encode!(%{"version" => 1, "transactions" => rows})

  # The file applied the way the importer booked it before ADR-0053 and its
  # amendment: every row's cash cell whole, a JSON trade priced the old way.
  defp apply_old_reading!(portfolio, body) do
    {:ok, %Preview{errors: []} = preview} =
      PortfolioPerformance.parse(body, filename: "history.json")

    old =
      Enum.map(preview.entries, fn %Entry{} = entry ->
        %{entry | gross_amount: entry.hash_amount, price: entry.hash_price || entry.price}
      end)

    {:ok, _result} = Imports.apply(%{preview | entries: old}, %{portfolio_id: portfolio.id})
    :ok
  end

  # --- the page ----------------------------------------------------------------

  defp upload(view, name, content, type \\ "application/json") do
    view
    |> file_input("#pp-import-form", :pp_file, [
      %{name: name, content: content, type: type, last_modified: 1_700_000_000_000}
    ])
    |> render_upload(name)

    render_async(view)
  end

  defp confirm(view) do
    view |> element("form#pp-import-apply") |> render_submit()
    render_async(view, 2_000)
    assert has_element?(view, ".import-done")
  end

  defp german(conn), do: put_req_header(conn, "accept-language", "de-DE,de;q=0.9")

  # The data-role of the done page's first list after its counts.
  defp first_list(view) do
    view
    |> element(".import-done")
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.find(".import-done > .import-skipped")
    |> List.first()
    |> Floki.attribute("data-role")
    |> List.first()
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

  defp texts(view, selector) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find(selector)
    |> Enum.map(fn node ->
      node
      |> Floki.text(sep: " ")
      |> String.replace(~r/\s+/u, " ")
      |> String.replace(~r/ ([.,:])/u, "\\1")
      |> String.trim()
    end)
  end

  defp portfolio! do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "PP Import Target",
        base_currency_code: "EUR"
      })

    portfolio
  end
end
