defmodule PortfolixirWeb.JournalSinceLiveTest do
  # Sprint 24 J3 (I16, decision D-4; board
  # ux-design-2026-11-04-sprint24/01-journal-since, pick Q1 = A): the audit
  # journal page takes `since` in its URL and in a date field „Seit“, and
  # lists the rows GET /api/v1/journal names for the same cut, newest first.
  # Every entry is synthetic and backdated.
  use PortfolixirWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Portfolixir.Journal.Entry
  alias Portfolixir.Repo

  @auth {"authorization", "Bearer test-api-token"}

  # An instant `seconds_ago` before now, whole seconds.
  defp ago(seconds) do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(-seconds, :second)
  end

  defp entry!(inserted_at, resource_id) do
    row = %{
      actor_type: :owner_ui,
      operation: :update,
      resource_type: "security",
      resource_id: resource_id,
      before: %{"name" => "Synthetic A"},
      after: %{"name" => "Synthetic B"},
      inserted_at: Map.put(inserted_at, :microsecond, {0, 6})
    }

    {1, [%{id: id}]} = Repo.insert_all(Entry, [row], returning: [:id])
    id
  end

  # Two entries three days back, four within the last hour (two of them
  # sharing one stamp).
  defp fixture! do
    old = for n <- 1..2, do: entry!(ago(3 * 86_400), "old-#{n}")
    recent = [entry!(ago(3000), "r-1"), entry!(ago(1200), "r-2")]
    shared = for n <- 3..4, do: entry!(ago(600), "r-#{n}")
    %{old: old, recent: recent ++ shared}
  end

  # The API's rows for a cut, every page of its walk, each answered `as_of`
  # fed back as the next `since` (D-9 rule 4).
  defp api_walk(conn, params) do
    Stream.unfold(params["since"], fn
      nil ->
        nil

      since ->
        body =
          conn
          |> put_req_header("accept", "application/json")
          |> put_req_header(elem(@auth, 0), elem(@auth, 1))
          |> get("/api/v1/journal", Map.put(params, "since", since))
          |> json_response(200)

        {Enum.map(body["data"], & &1["id"]), if(body["has_more"], do: body["as_of"])}
    end)
    |> Enum.concat()
  end

  defp page_ids(view) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find("table.journal-table tbody tr[data-entry]")
    |> Enum.flat_map(&Floki.attribute(&1, "data-entry"))
    |> Enum.map(&String.to_integer/1)
  end

  defp basis(view),
    do: view |> element("[data-role='journal-basis']") |> render() |> text()

  defp text(html),
    do: html |> Floki.parse_fragment!() |> Floki.text() |> String.split() |> Enum.join(" ")

  defp de_date(%Date{} = date), do: Calendar.strftime(date, "%d.%m.%Y")

  # User story (Sprint 24 J3, I16; decision D-4, D-1 criterion 2):
  # As the operator handed a link by the agent,
  # I want /journal?since=… to open the journal from that cut on, newest
  # first, its basis line naming the cut,
  # so that "what changed since Monday" is the agent's link, and the rows I
  # see are the rows the agent read.
  #
  # Acceptance criteria:
  # - The link, opened literally as the agent hands it over, with a date
  #   and with an instant, lists exactly the entries the API's since names
  #   for the same cut (its whole walk), newest first.
  # - The basis line names the cut after „Neueste zuerst“: „seit
  #   <date> (UTC)“ for a date, the instant to the second for an instant.
  # - An unreadable since reads as absent: the whole journal, no cut named.
  test "a link with since opens the slice the API names, newest first", %{conn: conn} do
    %{old: old, recent: recent} = fixture!()
    yesterday = Date.add(Date.utc_today(), -1)
    link = "/journal?since=#{Date.to_iso8601(yesterday)}"

    {:ok, view, _html} = live(conn, link <> "&locale=de")

    api = api_walk(conn, %{"since" => Date.to_iso8601(yesterday)})
    ids = page_ids(view)

    assert ids == Enum.reverse(api)
    assert Enum.all?(recent, &(&1 in ids))
    refute Enum.any?(old, &(&1 in ids))

    assert basis(view) ==
             "Neueste zuerst · seit #{de_date(yesterday)} (UTC) · #{length(ids)} Einträge · " <>
               "ohne Was-wäre-wenn-Szenarien · Zeiten in UTC"

    # An instant, as the agent writes one: between the first two recent
    # entries and the others.
    cut = ago(2000)
    instant = DateTime.to_iso8601(cut)
    {:ok, view, _html} = live(conn, "/journal?since=#{URI.encode_www_form(instant)}&locale=de")

    ids = page_ids(view)
    assert ids == Enum.reverse(api_walk(conn, %{"since" => instant}))
    refute hd(recent) in ids
    assert Enum.all?(tl(recent), &(&1 in ids))

    assert basis(view) =~
             "Neueste zuerst · seit #{de_date(DateTime.to_date(cut))} " <>
               "#{Calendar.strftime(cut, "%H:%M:%S")} (UTC) · "

    {:ok, view, _html} = live(conn, "/journal?since=soon&locale=de")
    assert Enum.all?(old ++ recent, &(&1 in page_ids(view)))
    refute basis(view) =~ "seit"
  end

  # User story (Sprint 24 J3, I16; decision D-4):
  # As the operator reading a cut longer than one page,
  # I want „Ältere Einträge zeigen“ to page within the cut,
  # so that the next page continues the slice, not the whole journal.
  #
  # Acceptance criteria:
  # - With since and a limit below the cut's entries, the page shows the
  #   newest entries after the cut and says it is cut.
  # - „Ältere Einträge zeigen“ keeps since in the URL and grows the limit.
  # - The cut combines with a filter: the URL keeps both.
  test "„Ältere Einträge zeigen“ pages within the cut", %{conn: conn} do
    %{old: old, recent: recent} = fixture!()
    since = Date.to_iso8601(Date.add(Date.utc_today(), -1))

    {:ok, view, _html} =
      live(conn, "/journal?resource_type=security&since=#{since}&limit=2&locale=de")

    assert page_ids(view) == recent |> Enum.sort(:desc) |> Enum.take(2)
    assert basis(view) =~ "seit "
    assert basis(view) =~ "die neuesten 2 Einträge"

    view |> element("a[data-role='journal-more']", "Ältere Einträge zeigen") |> render_click()
    assert_patch(view, "/journal?resource_type=security&since=#{since}&limit=102")

    assert Enum.sort(page_ids(view)) == Enum.sort(recent)
    refute Enum.any?(old, &(&1 in page_ids(view)))
  end

  # User story (Sprint 24 J3, I16; board 01, pick Q1 = A):
  # As the operator asking "what changed this week",
  # I want one date field „Seit“ beside the kind,
  # so that I set the cut myself, and a cut the agent handed over shows as
  # itself in the same field.
  #
  # Acceptance criteria:
  # - The filter form holds, right after the kind, the label „Seit“ with a
  #   native date input named since, empty without a cut.
  # - Picking a date patches /journal?since=<date>, the list starting from
  #   its newest page; clearing it patches the cut away.
  # - A link's date fills the field; a link's instant fills it with its UTC
  #   date, and another filter change keeps the instant as handed over.
  test "the date field „Seit“ sets and shows the cut", %{conn: conn} do
    %{old: old, recent: recent} = fixture!()
    since = Date.to_iso8601(Date.add(Date.utc_today(), -1))

    {:ok, view, html} = live(conn, "/journal?locale=de")

    [label] =
      html
      |> Floki.parse_document!()
      |> Floki.find("#journal-filters > label")
      |> Enum.drop(1)
      |> Enum.take(1)

    assert Floki.attribute(label, "class") == ["journal-filters__since"]
    assert label |> Floki.text() |> String.trim() == "Seit"
    assert has_element?(view, "#journal-filters .journal-filters__kind + label #journal-since")
    assert has_element?(view, "#journal-since[type='date'][name='since'][value='']")

    view |> form("#journal-filters", %{"since" => since}) |> render_change()
    assert_patch(view, "/journal?since=#{since}")
    assert has_element?(view, "#journal-since[value='#{since}']")
    assert Enum.all?(recent, &(&1 in page_ids(view)))
    refute Enum.any?(old, &(&1 in page_ids(view)))

    view |> form("#journal-filters", %{"since" => ""}) |> render_change()
    assert_patch(view, "/journal")
    assert Enum.all?(old, &(&1 in page_ids(view)))

    cut = ago(2000)
    instant = DateTime.to_iso8601(cut)
    {:ok, view, _html} = live(conn, "/journal?since=#{URI.encode_www_form(instant)}&locale=de")
    assert has_element?(view, "#journal-since[value='#{Date.to_iso8601(DateTime.to_date(cut))}']")

    view |> form("#journal-filters", %{"resource_type" => "security"}) |> render_change()
    assert_patch(view, "/journal?" <> URI.encode_query(resource_type: "security", since: instant))
  end
end
