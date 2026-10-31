defmodule PortfolixirWeb.ImportsEntryLabelLiveTest do
  # Board 07 ⑥ of the 2026-10-09 pass (#1179): a JSON export numbers its
  # rows by their place in the `transactions` list, not by a line of the
  # file, so a JSON preview and its done page say "Entry N" ("Eintrag N")
  # wherever they name a row; a CSV keeps "Row N" ("Zeile N"), the row a
  # spreadsheet shows (#1128). Every name, amount and identifier is
  # synthetic.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Entry
  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Imports.Preview
  alias Portfolixir.Portfolios

  @fund %{"name" => "Wrenfield Gardens AG", "isin" => "DE000EXMPL17", "currency" => "EUR"}

  # User story (#1179, Sprint 21 γ7; board 07 ⑥): As the operator reading
  # a JSON export's preview, I want every row it names called "Entry N",
  # the N-th entry of the export's transactions, so that "Row N" never
  # sends me to a line of a file that has none.
  #
  # Acceptance criteria:
  # - The parser warnings read "Entry 4: currency “EURO” is not supported —
  #   entry not imported" and "Entry 5: transfer without a counter account
  #   — entry not imported".
  # - The correction table's first column is headed "Entry"; its phone row
  #   reads "Entry 3 · …".
  # - The correction dialog names the booking as "Entry 3".
  # - In German: "Eintrag 4: … — Eintrag nicht übernommen" and the column
  #   "Eintrag".
  test "a JSON preview names its rows as entries", %{conn: conn} do
    portfolio = portfolio!()
    apply_old_reading!(portfolio, json(history()))

    drop = json(history() ++ [deposit("EURO"), transfer_without_counter()])

    {:ok, view, _html} = live(conn, "/imports")
    upload(view, "history.json", drop)

    warnings = text(view, "[data-role='parser-warnings'] pre")
    assert warnings =~ "Entry 4: currency “EURO” is not supported — entry not imported"
    assert warnings =~ "Entry 5: transfer without a counter account — entry not imported"
    refute warnings =~ "Row"
    refute warnings =~ "row not imported"

    assert text(view, "#import-correction-table thead th:first-child") == "Entry"

    assert text(view, "#import-correction-phone-rows li:first-child .phone-row__ids") =~
             "Entry 3 ·"

    view |> element("#import-correction-open") |> render_click()
    assert text(view, "#import-correction-dialog") =~ "Entry 3"
    refute text(view, "#import-correction-dialog") =~ "Row 3"

    {:ok, german, _html} = live(german(conn), "/imports")
    upload(german, "history.json", drop)

    assert text(german, "[data-role='parser-warnings'] pre") =~
             "Eintrag 5: Umbuchung ohne Gegenkonto — Eintrag nicht übernommen"

    assert text(german, "#import-correction-table thead th:first-child") == "Eintrag"
  end

  # User story (#1179, Sprint 21 γ7; board 07 ⑥ and ⑨): As the operator
  # reading the done page of a JSON import, I want its lists to name rows as
  # entries too, and a CSV's to keep rows, so that the word means one thing
  # per format.
  #
  # Acceptance criteria:
  # - A JSON file dropped again lists its skipped records as "Entry 1: …",
  #   never "Row 1: …".
  # - A CSV file's parser warning still reads "Row N: … — row not
  #   imported".
  test "a JSON done page names entries, and a CSV keeps rows", %{conn: conn} do
    portfolio = portfolio!()
    body = json(history())
    {:ok, preview} = Imports.parse_portfolio_performance(body, filename: "history.json")
    {:ok, _result} = Imports.apply(preview, %{portfolio_id: portfolio.id})

    {:ok, view, _html} = live(conn, "/imports")
    upload(view, "history.json", body)
    view |> element("form#pp-import-apply") |> render_submit()
    render_async(view, 2_000)

    skipped = text(view, "[data-role='duplicate-entries']")
    assert skipped =~ "Entry 1: Deposit"
    refute skipped =~ "Row 1"

    csv = """
    Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle
    2026-01-02;Einlage;;;;1.000,00;;;;Test-Cash;;;
    2026-01-05;Umbuchung (Ausgang);;;;100,00;;;;Test-Cash;;;
    """

    {:ok, view, _html} = live(conn, "/imports")
    upload(view, "export.csv", csv, "text/csv")

    assert text(view, "[data-role='parser-warnings'] pre") =~
             "Row 3: transfer without a counter account — row not imported"
  end

  # --- the export ------------------------------------------------------------

  defp history do
    [
      deposit("EUR"),
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

  defp deposit(currency) do
    %{
      "type" => "DEPOSIT",
      "account" => "Test-Cash",
      "date" => "2026-01-02",
      "currency" => currency,
      "amount" => num("1000.00")
    }
  end

  defp transfer_without_counter do
    %{
      "type" => "CASH_TRANSFER",
      "account" => "Test-Cash",
      "date" => "2026-01-05",
      "currency" => "EUR",
      "amount" => num("100.00")
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

  defp upload(view, name, content, type \\ "application/json") do
    view
    |> file_input("#pp-import-form", :pp_file, [
      %{name: name, content: content, type: type, last_modified: 1_700_000_000_000}
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
    |> String.replace(~r/ ([.,:])/u, "\\1")
    |> String.trim()
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
