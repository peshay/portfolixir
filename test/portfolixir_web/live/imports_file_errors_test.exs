defmodule PortfolixirWeb.ImportsFileErrorsTest do
  @moduledoc false
  # E25 S5: the files that used to stall or crash the Imports preview (board
  # 11, part 1). The preview store is shared state, so this module runs alone,
  # like the other Imports page tests.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
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
end
