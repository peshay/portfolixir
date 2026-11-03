defmodule PortfolixirWeb.ImportsPolishLiveTest do
  # Three lines of the Imports polish list (#1355) that Sprint 23's Lane I
  # page story fixes: #1327 (a hand-made plural on the done page), #1267 (an
  # unsupported version string printed at any length) and the parsers' bare
  # date atoms shown as a row error. The preview store is shared state, so
  # this module runs alone. Every name, amount and identifier is synthetic.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Imports
  alias Portfolixir.Imports.PreviewStore
  alias Portfolixir.Portfolios

  @session_token "DDDDDDDDDDDDDDDDDDDDDDDD"
  @csv_header "Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle"

  setup %{conn: conn} do
    {:ok, _portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "PP Import Target",
        base_currency_code: "EUR"
      })

    on_exit(fn -> PreviewStore.delete(PreviewStore.key_for(@session_token)) end)

    %{
      conn:
        conn
        |> init_test_session(%{"_csrf_token" => @session_token})
        |> put_req_header("accept-language", "de-DE,de;q=0.9")
    }
  end

  defp num(digits), do: Jason.Fragment.new(digits)

  defp json(rows), do: Jason.encode!(%{"version" => 1, "transactions" => rows})

  defp deposit(date, amount) do
    %{
      "type" => "DEPOSIT",
      "account" => "Test-Cash",
      "date" => date,
      "currency" => "EUR",
      "amount" => amount
    }
  end

  defp drop!(view, name, content, type) do
    file_input(view, "#pp-import-form", :pp_file, [
      %{name: name, content: content, type: type, last_modified: 1_700_000_000_000}
    ])
    |> render_upload(name)

    render_async(view)
  end

  # A second drop in the same session starts from a fresh page: the first
  # preview is parked for the session, and a remount would restore it.
  defp fresh(conn) do
    PreviewStore.delete(PreviewStore.key_for(@session_token))
    {:ok, view, _html} = live(conn, "/imports")
    view
  end

  defp squish(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()

  defp text(view, selector) do
    view
    |> element(selector)
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.text()
    |> squish()
  end

  # User story (#1327):
  # As the operator who mapped one security by hand,
  # I want the done page to say so in its grammatical number,
  # so that "1 Wertpapiere wurden" does not read as a slip.
  #
  # Acceptance criteria:
  # - One security mapped by hand reads „1 Wertpapier wurde manuell
  #   zugeordnet.“ (English "1 security was mapped manually.").
  test "the done page counts one hand-mapped security in the singular (#1327)",
       %{conn: conn} do
    {:ok, target} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Harborline Freight Inc",
        isin: "US0000HRB017",
        currency_code: "EUR"
      })

    rows = [
      deposit("2026-01-02", num("2000.00")),
      %{
        "type" => "PURCHASE",
        "account" => "Test-Cash",
        "portfolio" => "Depot Muster",
        "date" => "2026-01-15",
        "currency" => "EUR",
        "amount" => num("100.00"),
        "shares" => num("10"),
        "security" => %{"name" => "Harborline Freight", "currency" => "EUR"}
      }
    ]

    {:ok, preview} = Imports.parse_portfolio_performance(json(rows), filename: "one.json")
    [res] = Imports.resolve_securities(preview).resolutions

    {:ok, view, _html} = live(conn, "/imports")
    drop!(view, "one.json", json(rows), "application/json")

    choice = %{"security" => %{res.key => %{"choice" => "existing:#{target.id}"}}}
    view |> element("form#pp-import-apply") |> render_change(choice)
    view |> element("form#pp-import-apply") |> render_submit(choice)
    render_async(view, 1_000)

    assert text(view, "[data-role='security-overrides']") ==
             "1 Wertpapier wurde manuell zugeordnet."
  end

  # User story (#1267):
  # As the operator dropping a JSON file whose version is a long string,
  # I want the file error to name it shortened, as the row messages do,
  # so that the error band does not fill with the file's text.
  #
  # Acceptance criteria:
  # - A version string past 40 characters is cut at 40 and the cut marked
  #   "…"; a short one is named whole.
  test "an unsupported version string is named shortened (#1267)", %{conn: conn} do
    long = String.duplicate("v", 41) <> String.duplicate("x", 500)

    {:ok, view, _html} = live(conn, "/imports")
    drop!(view, "long.json", ~s({"version": "#{long}", "transactions": []}), "application/json")

    assert text(view, ".alert-error[role=alert]") =~
             "Nicht unterstützte PP-JSON-Version: " <> String.duplicate("v", 40) <> "…"

    refute render(view) =~ "vx"
  end

  # User story (#1355's parse_date line, found on #1367):
  # As the operator whose export holds a row without a readable date,
  # I want the row's warning to say what is wrong in words,
  # so that I can fix the row, rather than read ":invalid_format".
  #
  # Acceptance criteria:
  # - JSON v1: a date that is not YYYY-MM-DD reads „Datum „15.01.2026“ nicht
  #   lesbar: JJJJ-MM-TT angeben — Eintrag nicht übernommen“; a missing date
  #   reads „kein Datum — Eintrag nicht übernommen“ (a JSON row is an entry).
  # - CSV: a `Datum` whose date is not YYYY-MM-DD reads the same; a blank one
  #   reads „kein Datum — Zeile nicht übernommen“.
  # - No warning carries an inspected atom.
  test "a row's unreadable or missing date is a sentence, not an atom", %{conn: conn} do
    rows = [
      deposit("2026-01-02", num("100.00")),
      deposit("15.01.2026", num("100.00")),
      Map.delete(deposit("2026-01-03", num("100.00")), "date")
    ]

    {:ok, view, _html} = live(conn, "/imports")
    drop!(view, "dates.json", json(rows), "application/json")

    # A JSON file's rows are entries, so the page says "Eintrag" (#1179).
    assert text(view, "#parser-warnings-box pre") ==
             "Eintrag 2: Datum „15.01.2026“ nicht lesbar: JJJJ-MM-TT angeben — " <>
               "Eintrag nicht übernommen Eintrag 3: kein Datum — Eintrag nicht übernommen"

    csv =
      Enum.join(
        [
          @csv_header,
          "2026-01-02 00:00:00;Einlage;;;;100,00;;;100,00;Test-Cash;;;",
          "15.01.2026 00:00:00;Einlage;;;;100,00;;;100,00;Test-Cash;;;",
          ";Einlage;;;;100,00;;;100,00;Test-Cash;;;"
        ],
        "\n"
      )

    view = fresh(conn)
    drop!(view, "dates.csv", csv, "text/csv")

    warnings = text(view, "#parser-warnings-box pre")

    assert warnings =~
             "Datum „15.01.2026“ nicht lesbar: JJJJ-MM-TT angeben — Zeile nicht übernommen"

    assert warnings =~ "kein Datum — Zeile nicht übernommen"
    refute warnings =~ ~r/:\w+_\w+/
  end
end
