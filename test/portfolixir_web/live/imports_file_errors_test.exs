defmodule PortfolixirWeb.ImportsFileErrorsTest do
  @moduledoc false
  # E25 S5: the files that used to stall or crash the Imports preview (board
  # 11, part 1). The preview store is shared state, so this module runs alone,
  # like the other Imports page tests.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Plug.Conn.Query
  alias Portfolixir.Actor
  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Imports.PreviewStore
  alias Portfolixir.Portfolios

  @moduletag :capture_log

  @session_token "CCCCCCCCCCCCCCCCCCCCCCCC"
  @csv_header "Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle"
  @csv_ok "2024-01-15 10:01:00;Kauf;Synthetic AG;10;150,25;1.502,50;2,50;;1.502,50;Test-Depot;Test-Cash;;"

  setup %{conn: conn} do
    {:ok, _portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "PP Import Target",
        base_currency_code: "EUR"
      })

    on_exit(fn -> PreviewStore.delete(PreviewStore.key_for(@session_token)) end)
    %{conn: init_test_session(conn, %{"_csrf_token" => @session_token})}
  end

  defp csv(rows), do: Enum.join([@csv_header | rows], "\n")

  defp upload(view, name, content) do
    file_input(view, "#pp-import-form", :pp_file, [
      %{name: name, content: content, type: "text/csv", last_modified: 1_700_000_000_000}
    ])
    |> render_upload(name)
  end

  defp parked, do: PreviewStore.get(PreviewStore.key_for(@session_token))

  # User story (E25 S5, F34):
  # As an operator dropping an export a spreadsheet saved in another encoding,
  # I want the page to name the problem and its remedy in the error band,
  # so that the page stays usable and nothing broken is kept for my next visit.
  #
  # Acceptance criteria:
  # - The named file error appears in the error band above the drop zone.
  # - Nothing is parked, and the drop zone takes the next file at once.
  test "a file that is not UTF-8 is a named file error and nothing is parked", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/imports")

    latin1 =
      <<"2024-01-16 10:01:00;Kauf;Synthetic M", 0xFC,
        "nchen AG;10;150,25;1.502,50;2,50;;1.502,50;Test-Depot;Test-Cash;;">>

    upload(view, "latin1.csv", csv([@csv_ok, latin1]))

    assert has_element?(
             view,
             ".alert-error[role=alert]",
             "The file is not UTF-8 encoded. Remedy: export it again from Portfolio Performance"
           )

    assert has_element?(view, "form#pp-import-form.import-drop-zone")
    assert parked() == nil

    upload(view, "sound.csv", csv([@csv_ok]))
    assert render(view) =~ "Preview"
    refute has_element?(view, ".alert-error[role=alert]")
  end

  test "the German page names the encoding error in German", %{conn: conn} do
    conn = put_req_header(conn, "accept-language", "de-DE,de;q=0.9")
    {:ok, view, _html} = live(conn, "/imports")

    upload(view, "latin1.csv", csv([<<"2024-01-16 10:01:00;K", 0xE4, "uf;x;1;1;1;;;1;D;C;;">>]))

    assert has_element?(view, ".alert-error", "Die Datei ist nicht in UTF-8 kodiert.")
  end

  defp json_export(transactions) do
    Jason.encode!(%{"version" => 1, "transactions" => transactions})
  end

  defp upload_json(view, name, content) do
    file_input(view, "#pp-import-form", :pp_file, [
      %{name: name, content: content, type: "application/json", last_modified: 1_700_000_000_000}
    ])
    |> render_upload(name)
  end

  defp purchase(row_security) do
    %{
      "type" => "PURCHASE",
      "account" => "Test-Cash",
      "portfolio" => "Test-Depot",
      "date" => "2024-04-01",
      "currency" => "EUR",
      "amount" => "500.00",
      "shares" => "5",
      "security" => row_security
    }
  end

  # User story (E25 S5, F33, board 11):
  # As an operator importing an export whose security entries are incomplete,
  # I want the preview to show them, survive a reload and be discardable,
  # so that one odd entry never locks me out of the Imports page.
  #
  # Acceptance criteria:
  # - A security with neither a name nor an ISIN (a WKN or a ticker only)
  #   previews, counted once under the securities.
  # - A security that names nothing is a parser warning and not an entry.
  # - The parked preview remounts, and "Discard" returns to the drop zone.
  test "blank and partial security references preview, remount and discard", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/imports")

    export =
      json_export([
        purchase(%{"wkn" => "A0RPWH", "currency" => "EUR"}),
        purchase(%{"ticker" => "SYN", "currency" => "EUR"}),
        purchase(%{"currency" => "EUR"})
      ])

    upload_json(view, "partial.json", export)

    html = render(view)
    assert html =~ "Preview"

    assert has_element?(
             view,
             "#parser-warnings-box",
             "Row 3: security without a name and without an ISIN — row not imported"
           )

    assert view |> element(".import-stat-card", "Securities") |> render() =~ ">2<"
    assert view |> element(".import-stat-card", "Entries") |> render() =~ ">2<"
    assert parked() != nil

    {:ok, remounted, html} = live(conn, "/imports")
    assert html =~ "Preview"

    remounted |> element("button", "Discard") |> render_click()
    assert has_element?(remounted, "form#pp-import-form.import-drop-zone")
    assert parked() == nil
  end

  # User story (E25 S5, F35, board 11):
  # As an operator dropping an export that names more accounts, depots or
  # securities than one preview can show,
  # I want a named file error that says how to split the export,
  # so that the page never renders a preview too large to use.
  #
  # Acceptance criteria:
  # - A file past the cap is a named file error in the error band, the text
  #   names no number, and nothing is parked.
  # - A file at the cap previews, and its rendered size stays bounded: every
  #   depot row offers each cash account of the file exactly once.
  test "a file past the distinct-name cap is a named file error; at the cap it renders bounded",
       %{conn: conn} do
    %{accounts: cap} = PortfolioPerformance.max_names()
    half = div(cap, 2)
    long = String.duplicate("x", 40)

    rows = fn depots ->
      for i <- 1..depots do
        "2024-01-15 10:01:00;Kauf;Synthetic AG;1;1,00;1,00;;;1,00;Depot #{long} #{i};Cash #{long} #{i};;"
      end
    end

    {:ok, view, _html} = live(conn, "/imports")
    upload(view, "too-many.csv", csv(rows.(half + 1)))

    message =
      view
      |> element(".alert-error[role=alert]")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.text()

    assert message =~
             "The file names too many different accounts, depots or securities for one preview."

    refute message =~ ~r/\d/
    assert parked() == nil

    upload(view, "at-cap.csv", csv(rows.(half)))
    html = render(view)
    assert html =~ "Preview"

    doc = Floki.parse_document!(html)
    depot_rows = Floki.find(doc, ".mapping-row.depot")
    assert length(depot_rows) == half

    for row <- depot_rows do
      [_target, cash_select] = Floki.find(row, "select")

      import_options =
        cash_select |> Floki.find("option") |> Enum.filter(&(Floki.text(&1) =~ "(import)"))

      assert length(import_options) == half
    end

    assert byte_size(html) < 2_000_000
  end

  # The form as a browser sends it: every cash and depot select of the
  # mapping step under the name the page gave it, URL-encoded in page order
  # and decoded the way the socket decodes a form. `picks` overrides the
  # selected value by {row kind, file name}; any other select sends its
  # current choice.
  defp browser_form(view, picks) do
    doc = view |> render() |> Floki.parse_document!()

    pairs =
      for row <- Floki.find(doc, "#pp-import-apply .mapping-row"),
          selects = Floki.find(row, "select"),
          [first | _] = selects,
          [name] = Floki.attribute(first, "name"),
          String.starts_with?(name, ["cash[", "depot["]),
          {select, field} <- Enum.zip(selects, fields_of(row)),
          do: {select_name(select), pick(picks, field, source_name(row), select)}

    pairs |> URI.encode_query() |> Query.decode()
  end

  defp fields_of(row) do
    if row |> Floki.attribute("class") |> Enum.join(" ") =~ "depot",
      do: [:depot_target, :depot_cash],
      else: [:cash]
  end

  defp select_name(select), do: select |> Floki.attribute("name") |> hd()

  # The file's name, without the row's caption and its already-imported
  # count (board 04), which share the source cell.
  defp source_name(row) do
    [source] = Floki.find(row, ".source")
    label = source |> Floki.find("small") |> Floki.text()
    count = source |> Floki.find(".mapping-count") |> Floki.text()

    source
    |> Floki.text()
    |> String.replace(label, "")
    |> String.replace(count, "")
    |> String.trim()
  end

  defp pick(picks, field, name, select) do
    Map.get_lazy(picks, {field, name}, fn ->
      case Floki.find(select, "option[selected]") do
        [option | _] -> option |> Floki.attribute("value") |> hd()
        [] -> ""
      end
    end)
  end

  # User story (E25 S5, F42):
  # As an operator mapping an export whose account names contain brackets,
  # I want each cash-account and depot row to keep exactly the choice I make,
  # so that a name from the file can never rewrite another row's choice.
  #
  # Acceptance criteria:
  # - Rows are addressed by an opaque key: no file name appears in a field
  #   name.
  # - A bracket-bearing name neither changes a sibling row's choice nor
  #   crashes the page; the operator's pick applies to each row.
  test "bracket-bearing account names neither change sibling rows nor lose the operator's pick",
       %{conn: conn} do
    [portfolio] = Portfolios.list_portfolios()

    {:ok, main} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Main",
        currency_code: "EUR"
      })

    export =
      csv([
        "2024-01-15;Einlage;;;;100,00;;;100,00;Victim;;;",
        "2024-01-15;Einlage;;;;200,00;;;200,00;Victim][x;;;",
        "2024-01-15 10:01:00;Kauf;Synthetic AG;1;1,00;1,00;;;1,00;D1;Victim;;",
        "2024-01-15 10:02:00;Kauf;Synthetic AG;1;1,00;1,00;;;1,00;D1][cash;Victim;;"
      ])

    {:ok, view, _html} = live(conn, "/imports")
    upload(view, "brackets.csv", export)
    assert render(view) =~ "Preview"

    for name <- view |> render() |> Floki.parse_document!() |> Floki.attribute("select", "name") do
      refute name =~ ~r/Victim|D1/, name
    end

    main_choice = "existing:#{main.id}"

    params =
      browser_form(view, %{
        {:cash, "Victim][x"} => main_choice,
        {:depot_cash, "D1"} => main_choice
      })

    render_hook(view, "mapping_changed", params)
    assert Process.alive?(view.pid)

    assert {_preview, mapping} = parked()
    assert mapping.cash["Victim"] == "create:Victim"
    assert mapping.cash["Victim][x"] == main_choice
    assert mapping.depot["D1"] == %{"target" => "create:D1", "cash" => main_choice}
    assert mapping.depot["D1][cash"] == %{"target" => "create:D1][cash", "cash" => "pp:Victim"}
  end
end
