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
  alias Portfolixir.Journal.Entry
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Repo

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

  # User story:
  # As the operator and the agent reading one journal,
  # I want every filter of the page to be the API's filter of the same name,
  # so that a link the agent hands over opens the rows it read, and what I
  # see is what it saw (two-way coverage, board 03 ②).
  #
  # Acceptance criteria:
  # - For actor_type, operation, resource_type and include_scenarios, alone
  #   and combined, the page lists exactly the ids GET /api/v1/journal
  #   answers for the same parameters, in its order.
  # - The basis line names each filter in words: „Akteur Agent“, „Vorgang
  #   Gelöscht“, „Art Wertpapier“, „mit Was-wäre-wenn-Szenarien“.
  test "each filter narrows to what the API answers for the same parameters", %{conn: conn} do
    write_some_history!()

    for params <- [
          %{"actor_type" => "api_token_rw"},
          %{"actor_type" => "owner_ui"},
          %{"operation" => "delete"},
          %{"operation" => "update"},
          %{"resource_type" => "security"},
          %{"resource_type" => "cash_account"},
          %{"include_scenarios" => "true"},
          %{
            "actor_type" => "api_token_rw",
            "operation" => "delete",
            "resource_type" => "security"
          }
        ] do
      expected = api_ids(conn, params)
      assert expected != [], inspect(params)

      {:ok, view, _html} =
        live(conn, "/journal?" <> URI.encode_query(Map.put(params, "locale", "de")))

      assert page_ids(view) == expected, inspect(params)
    end

    {:ok, view, _html} =
      live(
        conn,
        "/journal?locale=de&actor_type=api_token_rw&operation=delete&resource_type=security&include_scenarios=true"
      )

    count = length(page_ids(view))

    assert view |> element("[data-role='journal-basis']") |> render() |> text() ==
             "Neueste zuerst · #{count} #{if count == 1, do: "Eintrag", else: "Einträge"} · " <>
               "Akteur Agent · Vorgang Gelöscht · Art Wertpapier · " <>
               "mit Was-wäre-wenn-Szenarien · Zeiten in UTC"
  end

  # User story:
  # As the operator narrowing the journal,
  # I want the actor and the operation as chips, the kind as a select and
  # the what-if scenarios as a checkbox, each writing its parameter into
  # the URL,
  # so that the view I narrowed to is a link that reproduces it (board 03
  # ②; the history's `?since=` rule, #731).
  #
  # Acceptance criteria:
  # - Akteur: Alle · Operator · Agent · Import · System; one is pressed.
  # - Vorgang: Angelegt · Geändert · Gelöscht · Angelegt oder ersetzt; a
  #   pressed chip pressed again clears its filter.
  # - The kind select „Alle Arten“ and the checkbox „Was-wäre-wenn-Szenarien
  #   einbeziehen“ patch the URL too.
  test "the chips, the select and the checkbox write the API's parameters into the URL",
       %{conn: conn} do
    write_some_history!()
    {:ok, view, _html} = live(conn, "/journal?locale=de")

    assert has_element?(view, "#journal-chip-actor-all[aria-pressed='true']", "Alle")

    for {type, word} <- [
          {"owner_ui", "Operator"},
          {"api_token_rw", "Agent"},
          {"import_session", "Import"},
          {"system_job", "System"}
        ] do
      assert has_element?(view, "#journal-chip-actor-#{type}[aria-pressed='false']", word)
    end

    for {operation, word} <- [
          {"create", "Angelegt"},
          {"update", "Geändert"},
          {"delete", "Gelöscht"},
          {"upsert", "Angelegt oder ersetzt"}
        ] do
      assert has_element?(view, "#journal-chip-operation-#{operation}", word)
    end

    view |> element("#journal-chip-actor-api_token_rw") |> render_click()
    assert_patch(view, "/journal?actor_type=api_token_rw")
    assert has_element?(view, "#journal-chip-actor-api_token_rw[aria-pressed='true']")
    assert has_element?(view, "#journal-chip-actor-all[aria-pressed='false']")

    view |> element("#journal-chip-operation-delete") |> render_click()
    assert_patch(view, "/journal?actor_type=api_token_rw&operation=delete")

    view |> element("#journal-chip-operation-delete") |> render_click()
    assert_patch(view, "/journal?actor_type=api_token_rw")

    assert has_element?(view, "#journal-kind option[value='']", "Alle Arten")
    assert has_element?(view, "#journal-kind option[value='security']", "Wertpapier")
    assert has_element?(view, "label", "Was-wäre-wenn-Szenarien einbeziehen")

    view
    |> form("#journal-filters", %{"resource_type" => "security", "include_scenarios" => "true"})
    |> render_change()

    assert_patch(
      view,
      "/journal?resource_type=security&actor_type=api_token_rw&include_scenarios=true"
    )

    assert has_element?(view, "#journal-kind option[value='security'][selected]")
    assert has_element?(view, "#journal-scenarios[checked]")

    view |> element("#journal-chip-actor-all") |> render_click()
    assert_patch(view, "/journal?resource_type=security&include_scenarios=true")
  end

  # User story:
  # As the operator reading one entry's change,
  # I want „Nur dieser Eintrag“ beside it to list that entry's history alone,
  # so that "what happened to this security?" is one click and a link, the
  # per-entity view board 03's variant B would have drawn on every page.
  #
  # Acceptance criteria:
  # - Each row links /journal?resource_type=…&resource_id=… .
  # - Followed, the page lists exactly what the API answers for those two
  #   parameters, and the basis line says „nur Wertpapier <id>“.
  # - „Alle Einträge zeigen“ leads back to the whole journal.
  test "„Nur dieser Eintrag“ filters to one entry", %{conn: conn} do
    %{kept: kept} = write_some_history!()
    {:ok, view, _html} = live(conn, "/journal?locale=de")

    href = "/journal?resource_type=security&resource_id=#{kept.id}"
    [update | _] = api_ids(conn, %{"resource_type" => "security", "resource_id" => "#{kept.id}"})

    view
    |> element("#journal-entry-#{update} a[href='#{href}']", "Nur dieser Eintrag")
    |> render_click()

    assert_patch(view, href)

    expected = api_ids(conn, %{"resource_type" => "security", "resource_id" => "#{kept.id}"})
    assert length(expected) == 2
    assert page_ids(view) == expected

    assert view |> element("[data-role='journal-basis']") |> render() |> text() =~
             "· nur Wertpapier #{kept.id} ·"

    assert has_element?(
             view,
             "[data-role='journal-entity-filter'] a[href='/journal']",
             "Alle Einträge zeigen"
           )
  end

  # User story:
  # As the operator reading what an agent changed,
  # I want each change said in one line per changed field, with its stored
  # before and after values folded beneath, reduced to the fields that
  # changed,
  # so that I see what changed without reading the whole record twice
  # (board 03 ③).
  #
  # Acceptance criteria:
  # - The column „Änderung“ reads „name: Festgeld → Festgeld Plus“, the old
  #   value struck and muted.
  # - The fold „Gespeicherte Werte“ is closed and holds a table Feld ·
  #   Vorher · Danach whose fields are exactly the keys whose stored before
  #   and after differ in the API's entry; an unchanged field is not there.
  # - A created entry folds every stored value, its „Vorher“ „—“.
  # - The entry links its page where it has one: a security its own page, a
  #   cash account Accounts & depots, a booking (no page of its own) the
  #   history, named by its kind and date.
  test "the fold shows only the changed fields", %{conn: conn} do
    %{cash: cash, kept: kept, deposit: deposit} = write_some_history!()

    [entry | _] =
      api_entries(conn, %{"resource_type" => "cash_account", "operation" => "update"})

    changed =
      entry["after"]
      |> Map.keys()
      |> Enum.filter(&(entry["before"][&1] != entry["after"][&1]))
      |> Enum.sort()

    assert "name" in changed
    refute "currency_code" in changed

    {:ok, view, _html} = live(conn, "/journal?locale=de")

    row = "#journal-entry-#{entry["id"]}"
    assert has_element?(view, "table.journal-table th", "Änderung")
    assert has_element?(view, "#{row} a[href='/portfolios']", "Verrechnungskonto #{cash.id}")

    # A booking has no page of its own: it reads its kind and date and
    # links the history.
    [booking] =
      api_entries(conn, %{"resource_type" => "transaction", "resource_id" => "#{deposit.id}"})

    assert has_element?(
             view,
             "#journal-entry-#{booking["id"]} a[href='/transactions']",
             "Transaktion #{deposit.id} · Einlage 05.05.2025"
           )

    # One line per changed field; the timestamps stay in the fold.
    lines = change_lines(view, row)
    assert length(lines) == length(changed -- ["inserted_at", "updated_at"])
    assert "name: Festgeld → Festgeld Plus" in lines

    assert has_element?(view, "#{row} .journal-change__from", "Festgeld")

    fold = view |> element("#{row} details.journal-values") |> render() |> Floki.parse_fragment!()
    assert Floki.attribute(fold, "open") == []
    assert fold |> Floki.find("summary") |> Floki.text() |> String.trim() == "Gespeicherte Werte"

    assert fold |> Floki.find("th") |> Enum.map(&String.trim(Floki.text(&1))) ==
             ["Feld", "Vorher", "Danach"]

    assert fold
           |> Floki.find("tbody tr td:first-child")
           |> Enum.map(&String.trim(Floki.text(&1))) == changed

    assert fold
           |> Floki.find("tbody tr")
           |> Enum.map(&row_cells/1)
           |> Enum.find(&(hd(&1) == "name")) ==
             ["name", "Festgeld", "Festgeld Plus"]

    [create | _] =
      api_entries(conn, %{
        "resource_type" => "security",
        "resource_id" => "#{kept.id}",
        "operation" => "create"
      })

    create_row = "#journal-entry-#{create["id"]}"
    assert has_element?(view, "#{create_row} a[href='/securities/#{kept.id}']")

    create_fold =
      view
      |> element("#{create_row} details.journal-values")
      |> render()
      |> Floki.parse_fragment!()

    cells = create_fold |> Floki.find("tbody tr") |> Enum.map(&row_cells/1)
    assert Enum.map(cells, &hd/1) == create["after"] |> Map.keys() |> Enum.sort()
    assert Enum.all?(cells, fn [_field, before, _after] -> before == "—" end)
    assert ["name", "—", "Alder Creek Fund"] in cells
  end

  # User story:
  # As the operator reading a deletion,
  # I want it said as „gelöscht, mit allen Werten“, every value the record
  # held folded beneath, and no link to a page that is gone,
  # so that the page reads the operation and not a before/after comparison
  # of a record that no longer exists (board 03; found while drawing 7).
  #
  # Acceptance criteria:
  # - The operation reads „Gelöscht“, the change „gelöscht, mit allen
  #   Werten“.
  # - The fold lists every field of the stored before-image, each „Danach“
  #   „—“, whatever the entry's after-image holds.
  # - The entry is text, not a link.
  test "a delete reads „gelöscht, mit allen Werten“", %{conn: conn} do
    %{gone: gone} = write_some_history!()

    [entry] =
      api_entries(conn, %{
        "resource_type" => "security",
        "resource_id" => "#{gone.id}",
        "operation" => "delete"
      })

    {:ok, view, _html} = live(conn, "/journal?locale=de")
    row = "#journal-entry-#{entry["id"]}"

    assert row_text(view, entry["id"]) =~ "Gelöscht"

    assert change_lines(view, row) == ["gelöscht, mit allen Werten"]

    assert has_element?(view, "#{row} .cell-name", "Wertpapier #{gone.id} · Brookfield Note")
    refute has_element?(view, "#{row} .cell-name a[href^='/securities']")

    cells =
      view
      |> element("#{row} details.journal-values")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find("tbody tr")
      |> Enum.map(&row_cells/1)

    assert Enum.map(cells, &hd/1) == entry["before"] |> Map.keys() |> Enum.sort()
    assert Enum.all?(cells, fn [_field, _before, after_value] -> after_value == "—" end)
    assert ["name", "Brookfield Note", "—"] in cells
  end

  # User story:
  # As the operator reading further back than one page,
  # I want the page to page as the API does — a limit, and whether more
  # matched — and to say when the list is cut,
  # so that "the newest 100" never reads as "all 100" (UX-DR26), and a link
  # with a limit reproduces what the agent read.
  #
  # Acceptance criteria:
  # - ?limit=N lists the API's rows for limit=N; when the API answers
  #   truncated, the basis line says „die neuesten N Einträge“ and
  #   „Ältere Einträge zeigen“ links the next page, limit + 100.
  # - A whole answer offers no further page.
  # - At the API's maximum (1000) no further page exists: the page says so
  #   and that a filter reaches older entries.
  test "the page pages like the API", %{conn: conn} do
    write_some_history!()

    {:ok, view, _html} = live(conn, "/journal?locale=de&limit=2")

    assert page_ids(view) == api_ids(conn, %{"limit" => "2"})

    assert view |> element("[data-role='journal-basis']") |> render() |> text() ==
             "Neueste zuerst · die neuesten 2 Einträge · ohne Was-wäre-wenn-Szenarien · Zeiten in UTC"

    view |> element("a[data-role='journal-more']", "Ältere Einträge zeigen") |> render_click()
    assert_patch(view, "/journal?limit=102")

    assert page_ids(view) == api_ids(conn, %{"limit" => "102"})
    refute has_element?(view, "[data-role='journal-more']")

    # The API's maximum: 1001 synthetic entries, written as rows (inserts are
    # what the append-only journal allows).
    now = DateTime.utc_now()

    rows =
      for n <- 1..1001 do
        %{
          actor_type: :system_job,
          actor_label: "synthetic",
          operation: :create,
          resource_type: "setting",
          resource_id: "page-#{n}",
          after: %{"key" => "page-#{n}"},
          inserted_at: now
        }
      end

    Repo.insert_all(Entry, rows)

    {:ok, view, _html} = live(conn, "/journal?locale=de&limit=1000")
    assert length(page_ids(view)) == 1000
    refute has_element?(view, "[data-role='journal-more']")

    assert has_element?(
             view,
             "[data-role='journal-at-max']",
             "Hier stehen die neuesten 1000, mehr fasst eine Seite nicht; ein Filter erreicht ältere Einträge."
           )
  end

  # User story:
  # As the operator looking for the journal,
  # I want its entry in the sidebar's „Verwaltung“ group, after
  # „Klassifizierungen“, where the other record-keeping pages are,
  # so that the journal is one click from every page and does not claim to
  # be about bookings only (board 03, pick Q6).
  #
  # Acceptance criteria:
  # - #nav-journal links /journal, reads „Audit-Journal“ and is the last
  #   link of the group, right after #nav-classifications.
  # - On /journal it is the current entry and no other is.
  test "the sidebar's „Verwaltung“ group ends with the journal", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/?locale=de")

    assert has_element?(view, "#nav-journal[href='/journal']", "Audit-Journal")

    group =
      view
      |> element("#app-sidebar .nav-group:has(#nav-journal)")
      |> render()
      |> Floki.parse_fragment!()

    assert group |> Floki.find(".nav-group-head") |> Floki.text() |> String.trim() == "Verwaltung"

    assert group
           |> Floki.find("a.nav-link")
           |> Enum.flat_map(&Floki.attribute(&1, "id"))
           |> Enum.take(-2) ==
             ["nav-classifications", "nav-journal"]

    {:ok, view, _html} = live(conn, "/journal?locale=de")
    assert has_element?(view, "#nav-journal.is-active[aria-current='page']")

    assert [_one] =
             view
             |> render()
             |> Floki.parse_document!()
             |> Floki.find("#app-sidebar .nav-link.is-active")
  end

  # User story:
  # As the operator reading the journal on a phone,
  # I want each entry as a two-line row — time, operation and actor over
  # the entry and its change — instead of a table that scrolls sideways,
  # so that the page works at 390 px as board 03's phone frame draws it
  # (UX-DR27).
  #
  # Acceptance criteria:
  # - Beside the table, ul.phone-rows.journal-rows holds one row per entry,
  #   in the table's order.
  # - A row's first line reads „<time> · <operation> · <actor> (<token>)“,
  #   then the entry (its link) with „Nur dieser Eintrag“, then the change
  #   lines and the fold of stored values.
  # - Under 560 px the stylesheet hides the table and shows the rows.
  test "under 560 px the entries are two-line rows", %{conn: conn} do
    %{cash: cash} = write_some_history!()

    [entry | _] =
      api_entries(conn, %{"resource_type" => "cash_account", "operation" => "update"})

    {:ok, view, _html} = live(conn, "/journal?locale=de")

    doc = view |> render() |> Floki.parse_document!()

    phone_ids =
      doc
      |> Floki.find("ul.phone-rows.journal-rows > li.phone-row[data-entry]")
      |> Enum.flat_map(&Floki.attribute(&1, "data-entry"))
      |> Enum.map(&String.to_integer/1)

    assert phone_ids == page_ids(view)

    [row] = Floki.find(doc, "ul.journal-rows > li[data-entry='#{entry["id"]}']")

    name =
      row |> Floki.find(".phone-row__name") |> Floki.text() |> String.split() |> Enum.join(" ")

    assert name =~ ~r/^\d{2}\.\d{2}\.\d{4} \d{2}:\d{2}:\d{2} · Geändert · Agent \(review seed\)$/

    assert Floki.find(row, "a[href='/portfolios']") |> Floki.text() =~
             "Verrechnungskonto #{cash.id}"

    assert Floki.find(row, "a[href='/journal?resource_type=cash_account&resource_id=#{cash.id}']") !=
             []

    assert Floki.find(row, ".journal-change__line") != []
    assert Floki.find(row, "details.journal-values") != []

    css = File.read!("priv/static/app.css")

    assert css =~
             ~r/@media \(max-width: 560px\)\s*\{\s*\.journal-table-wrap\s*\{\s*display: none;/

    assert css =~ ~r/\.journal-rows \.phone-row\s*\{[^}]*grid-template-columns: minmax\(0, 1fr\)/
  end

  # -- helpers ------------------------------------------------------------------

  defp row_cells(tr), do: tr |> Floki.find("td") |> Enum.map(&String.trim(Floki.text(&1)))

  defp api_entries(conn, params) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header(elem(@auth, 0), elem(@auth, 1))
    |> get("/api/v1/journal", params)
    |> json_response(200)
    |> Map.fetch!("data")
  end

  # A short synthetic history: the operator creates two securities and a
  # cash account, the agent renames one security, deletes the other and
  # renames the cash account.
  defp write_some_history! do
    owner = Actor.owner_ui()
    agent = Actor.api_token_rw("review seed")

    {:ok, portfolio} =
      Portfolios.create_portfolio(owner, %{name: "Main", base_currency_code: "EUR"})

    {:ok, kept} =
      Catalog.create_security(owner, %{name: "Alder Creek Fund", currency_code: "EUR"})

    {:ok, gone} = Catalog.create_security(owner, %{name: "Brookfield Note", currency_code: "EUR"})

    {:ok, cash} =
      Portfolios.create_cash_account(owner, %{
        portfolio_id: portfolio.id,
        name: "Festgeld",
        currency_code: "EUR"
      })

    {:ok, kept} = Catalog.update_security(agent, kept, %{name: "Alder Creek Fund A"})
    {:ok, _} = Catalog.delete_security(agent, gone)
    {:ok, cash} = Portfolios.update_cash_account(agent, cash, %{name: "Festgeld Plus"})

    {:ok, deposit} =
      Ledger.create_transaction(agent, %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        type: "deposit",
        date: ~D[2025-05-05],
        gross_amount: "600.00",
        currency_code: "EUR"
      })

    %{kept: kept, gone: gone, cash: cash, deposit: deposit}
  end

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

  # The change lines as they read on screen; the arrow's spoken words
  # („geändert in“) are for a screen reader only.
  defp change_lines(view, row) do
    view
    |> element(row)
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.find(".journal-change__line")
    |> Enum.map(fn line ->
      line
      |> Floki.filter_out(".visually-hidden")
      |> Floki.text()
      |> String.split()
      |> Enum.join(" ")
    end)
  end

  defp text(html),
    do: html |> Floki.parse_fragment!() |> Floki.text() |> String.split() |> Enum.join(" ")
end
