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

    # Issue 1435 (Sprint 29 L2; board 06 ①): the field is a group of the
    # journal's one bar of labelled controls, „Seit“ its label, after the
    # kind's group „Art“.
    labels =
      html
      |> Floki.parse_document!()
      |> Floki.find("#journal-filters .control-bar__label")
      |> Enum.map(&(&1 |> Floki.text() |> String.trim()))

    assert labels == ["Akteur", "Vorgang", "Art", "Seit"]

    assert has_element?(
             view,
             "#journal-filters label.control-bar__label[for='journal-since']",
             "Seit"
           )

    assert has_element?(
             view,
             "#journal-filters label.control-bar__label[for='journal-kind']",
             "Art"
           )

    # UX-DR19: the app's ISO text input, not a native date input (which
    # renders the browser locale's format), sent on blur so a half-typed date
    # never patches the cut away.
    assert has_element?(
             view,
             "#journal-since[type='text'][name='since'][value=''][placeholder='YYYY-MM-DD']" <>
               "[pattern='[0-9]{4}-[0-9]{2}-[0-9]{2}'][maxlength='10'][phx-debounce='blur']"
           )

    refute has_element?(view, "#journal-since[inputmode]")

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

  # User story (Sprint 24 closing act, J3; board 01 ①):
  # As the operator typing a date into „Seit“,
  # I want a date the field cannot read to leave my cut as it was,
  # so that a slip of one digit neither widens the list to the whole
  # journal nor erases what I typed (the field marks it as not a date).
  #
  # Acceptance criteria:
  # - With a cut set, „2026-10-2“ patches nothing: the URL and the cut stay,
  #   and the rows stay the cut's.
  # - With no cut, „2026-10“ patches nothing.
  # - An empty field still clears the cut.
  test "an unreadable „Seit“ keeps the cut and patches nothing", %{conn: conn} do
    %{old: old, recent: recent} = fixture!()
    since = Date.to_iso8601(Date.add(Date.utc_today(), -1))

    {:ok, view, _html} = live(conn, "/journal?since=#{since}&locale=de")

    view |> form("#journal-filters", %{"since" => "2026-10-2"}) |> render_change()
    refute_patched(view)
    assert has_element?(view, "#journal-since[value='#{since}']")
    assert basis(view) =~ "seit "
    assert Enum.all?(recent, &(&1 in page_ids(view)))
    refute Enum.any?(old, &(&1 in page_ids(view)))

    view |> form("#journal-filters", %{"since" => ""}) |> render_change()
    assert_patch(view, "/journal")

    {:ok, view, _html} = live(conn, "/journal?locale=de")
    view |> form("#journal-filters", %{"since" => "2026-10"}) |> render_change()
    refute_patched(view)
    refute basis(view) =~ "seit"
  end

  # User story (Sprint 24 closing act, J3; board 01 ①):
  # As the operator who types a date into „Seit“ and presses Enter,
  # I want Enter to set the cut as leaving the field does,
  # so that the actor, the operation and the one entry I filtered on stay.
  #
  # Acceptance criteria:
  # - The form submits to the page itself (`phx-submit`), never as a
  #   native GET that rebuilds the URL from the form's fields alone.
  # - Submitting a date patches the cut in and keeps actor_type, operation,
  #   resource_type and resource_id.
  test "Enter in „Seit“ sets the cut and keeps the other filters", %{conn: conn} do
    fixture!()
    since = Date.to_iso8601(Date.add(Date.utc_today(), -1))

    {:ok, view, _html} =
      live(
        conn,
        "/journal?resource_type=security&resource_id=r-1&actor_type=owner_ui&operation=update&locale=de"
      )

    assert has_element?(view, "#journal-filters[phx-submit='filter_form']")

    view
    |> form("#journal-filters", %{"since" => since, "resource_type" => "security"})
    |> render_submit()

    assert_patch(
      view,
      "/journal?" <>
        URI.encode_query(
          resource_type: "security",
          resource_id: "r-1",
          actor_type: "owner_ui",
          operation: "update",
          since: since
        )
    )
  end

  # User story (Sprint 24 closing act, J3; decision D-4):
  # As the operator opening a link whose since the page cannot read,
  # I want the page to say so beside its basis line,
  # so that the whole journal is never mistaken for the slice I was sent.
  #
  # Acceptance criteria:
  # - /journal?since=garbage, a cursor cut after its „~“ and 2026-13-01
  #   each show the whole journal with a note naming the value: „„Seit“-Wert
  #   „garbage“ ist nicht lesbar — das ganze Journal wird gezeigt.“ /
  #   "The “Since” value “garbage” is not readable — the whole journal is
  #   shown."
  # - The value is untrusted: it renders as text only, and past 40
  #   characters it is cut with „…“.
  # - A readable since, or none, shows no note.
  test "an unreadable since in a link is named, the whole journal shown", %{conn: conn} do
    %{old: old, recent: recent} = fixture!()

    for value <- ["garbage", "2026-10-28T09:15:02Z~", "2026-13-01"] do
      {:ok, view, _html} =
        live(conn, "/journal?" <> URI.encode_query(since: value, locale: "de"))

      assert Enum.all?(old ++ recent, &(&1 in page_ids(view)))
      refute basis(view) =~ "seit"

      assert view |> element("[data-role='journal-since-unread']") |> render() |> text() =~
               "„Seit“-Wert „#{value}“ ist nicht lesbar — das ganze Journal wird gezeigt."
    end

    {:ok, view, _html} = live(conn, "/journal?since=garbage&locale=en")

    assert view |> element("[data-role='journal-since-unread']") |> render() |> text() =~
             "The “Since” value “garbage” is not readable — the whole journal is shown."

    hostile = "<script>alert(1)</script>" <> String.duplicate("x", 60)
    {:ok, view, html} = live(conn, "/journal?" <> URI.encode_query(since: hostile))
    refute html =~ "<script>alert(1)"
    note = view |> element("[data-role='journal-since-unread']") |> render() |> text()
    assert note =~ "“" <> String.slice(hostile, 0, 40) <> "…”"
    refute note =~ String.slice(hostile, 0, 41)

    for link <- ["/journal", "/journal?since=#{Date.to_iso8601(Date.utc_today())}"] do
      {:ok, view, _html} = live(conn, link)
      refute has_element?(view, "[data-role='journal-since-unread']")
    end
  end

  # User story (Sprint 24 closing act, J3; board 01 ①; UX-DR19):
  # As the operator reading the field „Seit“,
  # I want its placeholder and a date to fit the field whole,
  # so that neither „YYYY-MM-DD“ nor „2026-10-20“ is cut at its end.
  #
  # Acceptance criteria:
  # - The input is twelve characters wide plus its 9 px paddings and 1 px
  #   borders (the box is border-box): `width: calc(12ch + 20px)`. Measured
  #   in Chromium at 13 px, the placeholder's text, the widest of the three,
  #   fits with Inter, DejaVu Sans, FreeSans and Arial (scrollWidth equals
  #   clientWidth); `11ch` cut „2026-10-20“ (91 > 88 px) and
  #   `calc(11ch + 20px)` cut „YYYY-MM-DD“ in Arial (101 > 98 px).
  test "the field „Seit“ holds its placeholder and a date whole" do
    css = File.read!("priv/static/app.css")

    assert [_, rule] = Regex.run(~r/\.journal-filters__since input \{([^}]*)\}/, css)
    assert rule =~ "width: calc(12ch + 20px);"
  end
end
