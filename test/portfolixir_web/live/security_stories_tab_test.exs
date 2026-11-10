defmodule PortfolixirWeb.SecurityStoriesTabTest do
  # ADR-0056 §8, §10 (Sprint 28, N8; board ux-design-2026-11-08-sprint28/01,
  # "Am Wertpapier: ein Reiter „Nachrichten“"; plan D-5): the security's tab
  # „Nachrichten“ after Research. Its rows read through the context function
  # news.list answers from, and „Ins Research-Log“ opens a form pre-filled
  # as notes.append with a cluster_id pre-fills it; only its save writes,
  # through the same write (NFR-10). Synthetic names and hosts only.
  use PortfolixirWeb.ConnCase

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Portfolixir.NewsFixtures, only: [label!: 2, security!: 1, story!: 2]

  alias Portfolixir.Journal
  alias Portfolixir.Knowledge
  alias Portfolixir.Knowledge.SecurityNote
  alias Portfolixir.News.Cluster
  alias Portfolixir.News.Item
  alias Portfolixir.News.Reads
  alias Portfolixir.Repo
  alias PortfolixirWeb.Format

  @agent_token String.duplicate("s", 40)

  setup do
    previous = Application.get_env(:portfolixir, :api_tokens)
    Application.put_env(:portfolixir, :api_tokens, [{"mcp", @agent_token}])
    on_exit(fn -> Application.put_env(:portfolixir, :api_tokens, previous) end)
    :ok
  end

  defp api(path) do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer " <> @agent_token)
    |> get(path)
    |> json_response(200)
    |> Map.fetch!("data")
  end

  defp cell_time(iso) do
    {:ok, at, 0} = DateTime.from_iso8601(iso)
    Format.date(DateTime.to_date(at)) <> " " <> Calendar.strftime(at, "%H:%M")
  end

  @long_title "Northwind Harbour Logistics announces a synthetic capital increase " <>
                "to fund the new terminal and its rail link"

  # Three stories of one security: one labelled capital_measure with a
  # positive tone (its title longer than a headline), one labelled
  # earnings, one without a label.
  defp world do
    security = security!("Northwind Harbour Logistics AG")
    capital = story!(security, title: @long_title)
    capital_label = label!(capital.id, event_type: "capital_measure", tone: 1, materiality: 2)
    earnings = story!(security, title: "Northwind Harbour reports synthetic results")
    label!(earnings.id, event_type: "earnings", tone: 0, materiality: 1)
    bare = story!(security, title: "Northwind Harbour named in a market wrap")

    %{
      security: security,
      capital: capital,
      capital_label: capital_label,
      earnings: earnings,
      bare: bare
    }
  end

  # User story (ADR-0056 §10; plan D-5, board 01):
  # As the operator reading a security's page,
  # I want a tab „Nachrichten“ after Research listing the security's
  # stories as the agent reads them — source, tier, time and the outside
  # model's label marked „maschinell“, its event type in words,
  # so that I see on the security what the agent sees, and which stories
  # are already in the research log.
  #
  # Acceptance criteria:
  # - The tab sits after Research and before Predictions; ?tab=news opens
  #   it and a click on it patches the address.
  # - Each row is a story news.list (fields=std) answers for the security,
  #   in its order: the title, the source's domain and tier, the time and
  #   the label (event type translated, never its code; the materiality;
  #   „machine-made“), or „no label“.
  # - A promoted story reads „kept“ instead of offering the write.
  # - A security without stories states it.
  test "the tab lists the security's stories as news.list answers them", %{conn: conn} do
    w = world()
    path = "/securities/#{w.security.id}"

    {:ok, view, _html} = live(conn, path)

    tabs =
      view
      |> render()
      |> LazyHTML.from_document()
      |> LazyHTML.query("[data-tab-level='2'] [role='tab'][phx-value-tab]")
      |> Enum.flat_map(&LazyHTML.attribute(&1, "phx-value-tab"))

    assert Enum.drop_while(tabs, &(&1 != "research")) |> Enum.take(3) ==
             ["research", "news", "predictions"]

    view |> element("[role='tab'][phx-value-tab='news']") |> render_click()
    assert_patch(view, path <> "?tab=news")
    assert has_element?(view, "#detail-tab-panel-news")

    {:ok, view, _html} = live(conn, path <> "?tab=news")

    rows = api("/api/v1/news/stories?security_id=#{w.security.id}&fields=std")["rows"]
    assert length(rows) == 3

    ids =
      view
      |> render()
      |> LazyHTML.from_document()
      |> LazyHTML.query("#security-stories-table tr[data-story]")
      |> Enum.flat_map(&LazyHTML.attribute(&1, "data-story"))

    assert ids == Enum.map(rows, &to_string(&1["id"]))

    for row <- rows do
      selector = "#security-stories-table tr[data-story='#{row["id"]}']"
      # The API cuts a list's title at 80 (closing act AG1), the tab at 160:
      # the tab shows what the API answers, and more of it.
      title = String.trim_trailing(row["title"], "…")
      assert has_element?(view, selector <> " [data-role='story-title']", title)
      assert has_element?(view, selector <> " [data-role='story-source']", row["domain"])
      assert has_element?(view, selector <> " [data-role='story-source']", row["tier"])
      assert has_element?(view, selector <> " [data-role='story-time']", cell_time(row["at"]))
    end

    capital = "#security-stories-table tr[data-story='#{w.capital.id}'] [data-role='story-label']"
    assert has_element?(view, capital, "Capital measure")
    assert has_element?(view, capital, "materiality 2")
    assert has_element?(view, capital, "machine-made")
    refute render(element(view, "#detail-tab-panel-news")) =~ "capital_measure"

    assert has_element?(
             view,
             "tr[data-story='#{w.earnings.id}'] [data-role='story-label']",
             "Earnings"
           )

    assert has_element?(
             view,
             "tr[data-story='#{w.bare.id}'] [data-role='story-label']",
             "no label"
           )

    for story <- [w.capital, w.earnings, w.bare] do
      assert has_element?(
               view,
               "tr[data-story='#{story.id}'] button[phx-click='open_promotion']",
               "To the research log"
             )
    end

    empty = security!("Quiet Harbour AG")
    {:ok, quiet, _html} = live(conn, "/securities/#{empty.id}?tab=news")
    assert has_element?(quiet, "#security-stories-empty")
    refute has_element?(quiet, "#security-stories-table")
  end

  # User story (ADR-0056 §8, A2; ADR-0044's amendment of 2026-11-06;
  # NFR-10; plan D-1, criterion 5):
  # As the operator who judged a story worth keeping,
  # I want „Ins Research-Log“ to open the note form pre-filled from the
  # story exactly as the agent's notes.append with cluster_id fills it,
  # and only my save to write,
  # so that nothing a machine proposed lands until I confirm it, and what I
  # confirm carries the story's provenance.
  #
  # Acceptance criteria:
  # - Opening the form writes nothing: no entry, no journal entry, the
  #   story not promoted.
  # - The form proposes kind evidence, the headline cut at 80 on a word
  #   boundary as N5 cuts it, the label's event type (in words) and tone,
  #   and states the story's as-of date, source link and source quality,
  #   which the write takes from the story.
  # - Cancel closes it and writes nothing.
  # - Saving with a body writes exactly one entry, through the write
  #   notes.append with cluster_id uses: the proposal as stored, the
  #   label's id kept as provenance, the author the operator, journaled
  #   under the UI actor; the story's members read promoted and name the
  #   note, and the row reads „kept“.
  test "the form is pre-filled as notes.append pre-fills it, and only its save writes",
       %{conn: conn} do
    w = world()
    {:ok, view, _html} = live(conn, "/securities/#{w.security.id}?tab=news")

    open = "tr[data-story='#{w.capital.id}'] button[phx-click='open_promotion']"
    view |> element(open) |> render_click()

    assert has_element?(view, "#story-promotion-form")
    assert Knowledge.list_notes(w.security.id) == []
    assert Journal.list_entries(resource_type: "security_note") == []
    assert Repo.get!(Item, w.capital.representative_item_id).status != :promoted

    headline = Reads.clip_spelled_words(@long_title, SecurityNote.headline_max())
    assert String.ends_with?(headline, "…")
    representative = Repo.get!(Item, w.capital.representative_item_id)

    assert has_element?(
             view,
             "#story-promotion-form input[name='promotion[headline]'][value='#{headline}']"
           )

    assert has_element?(
             view,
             "#story-promotion-form select[name='promotion[kind]'] option[selected][value='evidence']"
           )

    assert has_element?(
             view,
             "#story-promotion-form select[name='promotion[event_type]'] option[selected][value='capital_measure']",
             "Capital measure"
           )

    assert has_element?(
             view,
             "#story-promotion-form select[name='promotion[tone]'] option[selected][value='1']",
             "positive"
           )

    as_of = Portfolixir.Clock.local_date(representative.published_at)
    assert has_element?(view, "[data-role='promotion-as-of']", Format.date(as_of))

    assert has_element?(
             view,
             "[data-role='promotion-source'] a[href='#{representative.canonical_url}']"
           )

    assert has_element?(view, "[data-role='promotion-quality']", "Primary source")

    view |> element("#story-promotion-cancel") |> render_click()
    refute has_element?(view, "#story-promotion-form")
    assert Knowledge.list_notes(w.security.id) == []

    view |> element(open) |> render_click()

    view
    |> form("#story-promotion-form", %{
      "promotion" => %{"body" => "Kept: the raise funds the terminal."}
    })
    |> render_submit()

    assert [note] = Knowledge.list_notes(w.security.id)
    assert note.kind == :evidence
    assert note.author == :operator
    assert note.body == "Kept: the raise funds the terminal."
    assert note.headline == headline
    assert note.event_type == :capital_measure
    assert note.tone == 1
    assert note.as_of == as_of
    assert note.source_url == representative.canonical_url
    assert note.source_quality == :primary
    assert note.news_label_id == w.capital_label.id

    assert [entry] = Journal.list_entries(resource_type: "security_note")
    assert entry.actor_type == :owner_ui

    for item <- Repo.all(from(i in Item, where: i.cluster_id == ^w.capital.id)) do
      assert item.status == :promoted
      assert note.id in item.note_ids
    end

    refute has_element?(view, "#story-promotion-form")

    assert has_element?(
             view,
             "tr[data-story='#{w.capital.id}'] [data-role='story-kept']",
             "kept"
           )

    refute has_element?(view, open)

    api_row =
      api("/api/v1/news/stories?security_id=#{w.security.id}&fields=std")["rows"]
      |> Enum.find(&(&1["id"] == w.capital.id))

    assert api_row["note_ids"] == [note.id]
  end

  # User story (ADR-0056 §8; ADR-0044's amendment: "the writer may change
  # any of them before the write"; N5's finding: a title with an invisible
  # character makes the pre-filled headline invalid):
  # As the operator promoting a story whose title carries a character I
  # cannot see,
  # I want the form to name the headline's error and let me write my own,
  # so that the story still reaches the research log, without the hidden
  # character.
  #
  # Acceptance criteria:
  # - Saving the proposal writes nothing and names the headline's error at
  #   its field; the form stays open with what was typed.
  # - A headline the operator edits is the one stored; the event type and
  #   tone the operator changes are the ones stored.
  test "an invalid pre-filled headline is named at its field and can be edited", %{conn: conn} do
    security = security!("Hidden Character AG")

    story =
      story!(security,
        title: "Hidden" <> <<0x200B::utf8>> <> "Character AG wins a synthetic contract"
      )

    label!(story.id, event_type: "product", tone: 1, materiality: 2)

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=news")

    view
    |> element(
      "#security-stories-table button[phx-click='open_promotion'][phx-value-story='#{story.id}']"
    )
    |> render_click()

    view
    |> form("#story-promotion-form", %{"promotion" => %{"body" => "Worth keeping."}})
    |> render_submit()

    assert Knowledge.list_notes(security.id) == []
    assert has_element?(view, "#story-promotion-form [data-role='promotion-error-headline']")

    assert has_element?(
             view,
             "#story-promotion-form textarea[name='promotion[body]']",
             "Worth keeping."
           )

    view
    |> form("#story-promotion-form", %{
      "promotion" => %{
        "headline" => "Hidden Character AG wins a contract",
        "tone" => "0",
        "event_type" => "legal",
        "body" => "Worth keeping."
      }
    })
    |> render_submit()

    assert [note] = Knowledge.list_notes(security.id)
    assert note.headline == "Hidden Character AG wins a contract"
    assert note.tone == 0
    assert note.event_type == :legal
    assert Repo.get!(Cluster, story.id).id == story.id
  end

  # User story (ADR-0044's amendment: an event type is a fixed set; plan
  # N8, "event type shown as a translated label, never the raw code"):
  # As the operator reading the news page's digest,
  # I want its event types in words, as the security's tab names them,
  # so that I never read a code such as capital_measure.
  #
  # Acceptance criteria:
  # - The digest row of a story labelled capital_measure reads „Capital
  #   measure“ and nowhere the code.
  test "the news page's digest names the event type in words", %{conn: conn} do
    security = security!("Digest Words AG")

    {:ok, _} =
      Portfolixir.Catalog.update_security(Portfolixir.Actor.owner_ui(), security, %{
        news_watch: true
      })

    story = story!(security, title: "Digest Words AG plans a synthetic rights issue")
    label!(story.id, event_type: "capital_measure", materiality: 3)

    {:ok, view, _html} = live(conn, "/news")
    label = "#news-digest-table tr[data-security='#{security.id}'] [data-role='digest-label']"
    assert has_element?(view, label, "Capital measure")
    refute render(element(view, "#news-digest")) =~ "capital_measure"
  end
end
