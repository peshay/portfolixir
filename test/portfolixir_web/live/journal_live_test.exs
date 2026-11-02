defmodule PortfolixirWeb.JournalLiveTest do
  # Sprint 23 V3, idea U2 (board ux-design-2026-11-02-sprint23/03-journal,
  # picks Q5 = A and Q6): the audit journal gets its human page, the
  # operator's view of GET /api/v1/journal. Both read
  # PortfolixirWeb.Api.V1.JournalQuery, so a page and the API answer the
  # same rows for the same parameters. Every name and figure is synthetic.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog

  @auth {"authorization", "Bearer test-api-token"}

  # User story:
  # As the operator who lets an agent write,
  # I want one page listing every stored change, newest first, saying when
  # (in UTC), who made it, what was done and to which entry,
  # so that I can answer "what did the agent change?" without asking the
  # agent (U2; board 03, pick Q5 = A).
  #
  # Acceptance criteria:
  # - /journal is the page „Audit-Journal“ with its subtitle and the
  #   section „Einträge“.
  # - The rows are the API's rows for the same (no) parameters, in its
  #   order: newest first.
  # - A row reads the time in UTC to the second, the actor in words with
  #   the token's name as its second line, the operation in words and the
  #   entry as its kind, its id and its stored name.
  # - The basis line says the order, the count and that times are UTC.
  test "lists every entry newest first, as the API answers it", %{conn: conn} do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{name: "Alder Creek Fund", currency_code: "EUR"})

    {:ok, _} =
      Catalog.update_security(Actor.api_token_rw("review seed"), security, %{
        name: "Alder Creek Fund A"
      })

    {:ok, view, _html} = live(conn, "/journal?locale=de")

    assert has_element?(view, "#app-topbar-title", "Audit-Journal")

    assert has_element?(
             view,
             "#app-topbar-subtitle",
             "Jede gespeicherte Änderung, wer sie machte und was vorher stand"
           )

    assert has_element?(view, "#journal-panel h2", "Einträge")

    api_ids = api_ids(conn, %{})
    assert page_ids(view) == api_ids
    assert api_ids == Enum.sort(api_ids, :desc)

    [update, create | _] = page_ids(view)
    row = row_text(view, update)
    assert row =~ "Agent review seed"
    assert row =~ "Geändert"
    assert row =~ "Wertpapier #{security.id} · Alder Creek Fund A"
    assert row =~ ~r/\d{2}\.\d{2}\.\d{4} \d{2}:\d{2}:\d{2}/

    assert row_text(view, create) =~ "Operator"
    assert row_text(view, create) =~ "Angelegt"

    assert view |> element("[data-role='journal-basis']") |> render() |> text() ==
             "Neueste zuerst · #{length(api_ids)} Einträge · ohne Was-wäre-wenn-Szenarien · Zeiten in UTC"
  end

  # User story:
  # As the operator whose filters select nothing,
  # I want the page to say so in one sentence and offer the whole journal,
  # so that an empty list never reads as a broken page.
  #
  # Acceptance criteria:
  # - With no entry for the parameters the API answers an empty list and
  #   the page shows „Kein Eintrag passt zu diesen Filtern.“, no table.
  # - „Alle Einträge zeigen“ leads back to /journal.
  test "an empty answer reads as one sentence", %{conn: conn} do
    params = %{"actor_type" => "import_session"}
    assert api_ids(conn, params) == []

    {:ok, view, _html} = live(conn, "/journal?locale=de&actor_type=import_session")

    assert has_element?(view, "#journal-empty", "Kein Eintrag passt zu diesen Filtern.")
    assert has_element?(view, "#journal-empty a[href='/journal']", "Alle Einträge zeigen")
    refute has_element?(view, "table.journal-table")
  end

  # -- helpers ------------------------------------------------------------------

  defp api_ids(conn, params) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header(elem(@auth, 0), elem(@auth, 1))
    |> get("/api/v1/journal", params)
    |> json_response(200)
    |> Map.fetch!("data")
    |> Enum.map(& &1["id"])
  end

  defp page_ids(view) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find("table.journal-table tbody tr[data-entry]")
    |> Enum.flat_map(&Floki.attribute(&1, "data-entry"))
    |> Enum.map(&String.to_integer/1)
  end

  defp row_text(view, id), do: view |> element("#journal-entry-#{id}") |> render() |> text()

  defp text(html),
    do: html |> Floki.parse_fragment!() |> Floki.text() |> String.split() |> Enum.join(" ")
end
