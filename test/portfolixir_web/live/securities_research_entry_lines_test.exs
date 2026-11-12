defmodule PortfolixirWeb.SecuritiesResearchEntryLinesTest do
  # Sprint 29, N3 (the Sprint 28 close-out's two-way coverage finding;
  # board ux-design-2026-11-12-sprint29/03, variant A; plan D-6; ADR-0056
  # D6, D8 and E2; ADR-0044's amendment of 2026-11-06): the Research tab
  # shows what the agent reads. An entry's headline is its first line
  # behind the chart pin's glyph, „event type · tone“ in words under it
  # (the pin's tooltip, the same two lines), „machine-made“ only where the
  # entry took them from a news label, a superseded entry saying it is not
  # on the chart; its link shows the link's domain and opens the link.
  # Synthetic names and hosts only.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest
  import Portfolixir.NewsFixtures, only: [label!: 2, security!: 1, story!: 2]
  import Portfolixir.WorldFixtures, only: [put_quotes!: 2]
  import PortfolixirWeb.PreferenceCookieHelpers, only: [put_preference_cookie: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Clock
  alias Portfolixir.Knowledge
  alias PortfolixirWeb.EventTypeLabel
  alias PortfolixirWeb.Format

  @long_link "https://news.aggregator.example/articles/redirect?" <>
               String.duplicate("token=abcdef0123456789&", 20) <> "end=1"

  defp day(offset), do: Date.add(Clock.today(), offset)

  defp note!(security, offset, attrs, opts \\ []) do
    {:ok, note} =
      Knowledge.append_note(
        Actor.owner_ui(),
        Map.merge(
          %{
            "security_id" => security.id,
            "author" => "agent",
            "kind" => "evidence",
            "body" => "Synthetic finding.",
            "source_quality" => "primary",
            "as_of" => Date.to_iso8601(day(offset))
          },
          attrs
        ),
        opts
      )

    note
  end

  # A security with closes over the last 60 days and five entries: all
  # four fields with a long link (-50), a headline only (-40), an older
  # entry without them (-30), a superseded entry with a headline (-20) and
  # the entry that supersedes it (-10).
  defp world do
    security = security!("Northwind Harbour Logistics AG")
    put_quotes!(security, for(n <- 60..1//-1, do: {day(-n), "#{100 + rem(n, 5)}"}))

    full =
      note!(
        security,
        -50,
        %{
          "headline" => "Quarterly report: revenue above its own outlook",
          "event_type" => "earnings",
          "tone" => 1,
          "source_url" => @long_link
        },
        news_label_id: 7
      )

    headline_only = note!(security, -40, %{"headline" => "Board meets on the outlook"})

    older =
      note!(security, -30, %{
        "author" => "operator",
        "body" => "AGM approved the dividend as proposed.",
        "source_url" => "https://ir.example/agm-2026"
      })

    superseded =
      note!(
        security,
        -20,
        %{
          "headline" => "Report expects a profit warning",
          "event_type" => "guidance",
          "tone" => -1,
          "source_quality" => "unverified"
        },
        news_label_id: 8
      )

    superseding =
      note!(security, -10, %{
        "headline" => "Board confirms the outlook",
        "event_type" => "guidance",
        "tone" => 0,
        "supersedes_id" => superseded.id
      })

    %{
      security: security,
      full: full,
      headline_only: headline_only,
      older: older,
      superseded: superseded,
      superseding: superseding
    }
  end

  defp entry(view, note) do
    view
    |> render()
    |> LazyHTML.from_document()
    |> LazyHTML.query("#research-entry-#{note.id}")
  end

  defp text(node, selector) do
    node
    |> LazyHTML.query(selector)
    |> LazyHTML.text()
    |> String.split()
    |> Enum.join(" ")
  end

  defp count(node, selector), do: node |> LazyHTML.query(selector) |> Enum.count()

  defp api_notes(security) do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
    |> get("/api/v1/securities/#{security.id}/notes")
    |> json_response(200)
    |> get_in(["data", "entries"])
    |> Map.new(&{&1["id"], &1})
  end

  # User story (Sprint 29 N3; board 03 A; ADR-0056 D8):
  # As the operator reading a security's research log,
  # I want an entry's headline first, behind the chart pin's glyph, with
  # its event type and tone in words under it, and „machine-made“ where
  # they came from a news label,
  # so that I read on the log what the agent reads and the chart draws.
  #
  # Acceptance criteria:
  # - An entry with all four fields reads its headline behind a glyph of
  #   its tone (the pin's plus), „Earnings · positive“ under it and a
  #   „machine-made“ badge whose title says where they came from; the
  #   headline and the words are the API's answer for the same entry, and
  #   the chart pin's tooltip reads the same two lines (with the date).
  # - An entry with only a headline reads it behind the neutral glyph
  #   (none inside) and has no second line.
  # - An older entry without them has no headline and no second line.
  # - An entry without `news_label_id` carries no „machine-made“; a local
  #   model's proposal keeps its own „machine-generated proposal“.
  test "an entry's headline, its event type and tone, and „machine-made“ read as the API and the pin",
       %{conn: conn} do
    w = world()
    {:ok, view, _html} = live(conn, "/securities/#{w.security.id}?tab=research")
    api = api_notes(w.security)

    full = entry(view, w.full)
    api_full = api[w.full.id]
    assert api_full["news_label_id"] == 7

    assert text(full, ".research-entry__headline") == api_full["headline"]
    assert count(full, ".research-entry__headline .note-glyph--pos path") == 1

    label =
      "#{EventTypeLabel.event_type(api_full["event_type"])} · #{EventTypeLabel.tone(api_full["tone"])}"

    assert label == "Earnings · positive"
    assert text(full, ".research-entry__label") == label <> " machine-made"

    assert full
           |> LazyHTML.query(".research-entry__label .badge")
           |> LazyHTML.attribute("title") ==
             [
               "Event type and tone taken from a model's labelling of the story; confirmed by the write"
             ]

    {:ok, chart, _html} = live(conn, "/securities/#{w.security.id}?tab=chart")

    pin_title =
      chart
      |> render()
      |> LazyHTML.from_document()
      |> LazyHTML.query("g.note-pin[data-date='#{Date.to_iso8601(day(-50))}'] title")
      |> LazyHTML.text()

    assert pin_title == api_full["headline"] <> "\n" <> label <> " · " <> Format.date(day(-50))

    only = entry(view, w.headline_only)
    assert text(only, ".research-entry__headline") == "Board meets on the outlook"
    assert count(only, ".research-entry__headline .note-glyph--neu") == 1
    assert count(only, ".research-entry__headline .note-glyph path") == 0
    assert count(only, ".research-entry__label") == 0
    assert api[w.headline_only.id]["news_label_id"] == nil

    older = entry(view, w.older)
    assert count(older, ".research-entry__headline") == 0
    assert count(older, ".research-entry__label") == 0
    assert count(older, ".note-glyph") == 0
    assert text(older, ".research-entry__body") == "AGM approved the dividend as proposed."

    superseding = entry(view, w.superseding)
    assert text(superseding, ".research-entry__label") == "Guidance · neutral"
    refute LazyHTML.text(superseding) =~ "machine-made"

    proposal =
      note!(w.security, -5, %{
        "author" => "local_model",
        "machine_generated" => true,
        "source_quality" => "unverified",
        "source_url" => "https://filings.example/extract",
        "body" => "extracted: dividend raised"
      })

    {:ok, view, _html} = live(conn, "/securities/#{w.security.id}?tab=research")
    proposal_entry = entry(view, proposal)
    assert LazyHTML.text(proposal_entry) =~ "machine-generated proposal"
    refute LazyHTML.text(proposal_entry) =~ "machine-made"
  end

  # User story (Sprint 29 N3; ADR-0056 D8: a superseded entry is not drawn):
  # As the operator reading an entry another one superseded,
  # I want it to say it is not on the chart,
  # so that I do not look for its pin.
  #
  # Acceptance criteria:
  # - A superseded entry with a headline adds „not on the chart, as it is
  #   superseded“ to its second line, and the chart draws no pin at its
  #   day while it draws the superseding entry's; the API answers it
  #   superseded.
  # - A superseded entry without a headline (never a pin) does not say it.
  test "a superseded entry with a headline says it is not on the chart", %{conn: conn} do
    w = world()
    {:ok, view, _html} = live(conn, "/securities/#{w.security.id}?tab=research")

    assert api_notes(w.security)[w.superseded.id]["superseded"] == true

    superseded = entry(view, w.superseded)

    assert text(superseded, ".research-entry__label") ==
             "Guidance · negative machine-made · not on the chart, as it is superseded"

    assert text(superseded, ".research-entry__headline") == "Report expects a profit warning"

    {:ok, chart, _html} = live(conn, "/securities/#{w.security.id}?tab=chart")
    refute has_element?(chart, "g.note-pin[data-date='#{Date.to_iso8601(day(-20))}']")
    assert has_element?(chart, "g.note-pin[data-date='#{Date.to_iso8601(day(-10))}']")

    plain = note!(w.security, -8, %{"body" => "An unheaded finding."})
    note!(w.security, -6, %{"body" => "It is replaced.", "supersedes_id" => plain.id})
    {:ok, view, _html} = live(conn, "/securities/#{w.security.id}?tab=research")
    refute LazyHTML.text(entry(view, plain)) =~ "not on the chart"
    assert count(entry(view, plain), ".research-entry__label") == 0
  end

  # User story (Sprint 29 N3; ADR-0056 E2):
  # As the operator reading an entry kept from an aggregator's story,
  # I want its link shown as the link's domain and opening the link,
  # so that a 400-character redirect does not fill the entry.
  #
  # Acceptance criteria:
  # - The link's text is its host; its href is the full link, the API's
  #   `source_url` for the same entry; the full link is printed nowhere in
  #   the entry. An older entry's link reads its domain too, lower-cased;
  #   a link without a host reads „link“.
  test "an entry's link shows its domain and opens the full link", %{conn: conn} do
    w = world()
    {:ok, view, _html} = live(conn, "/securities/#{w.security.id}?tab=research")
    api = api_notes(w.security)

    full = entry(view, w.full)
    link = LazyHTML.query(full, ".research-entry__facts a")
    assert LazyHTML.attribute(link, "href") == [api[w.full.id]["source_url"]]
    assert api[w.full.id]["source_url"] == @long_link
    assert LazyHTML.text(link) |> String.trim() == "news.aggregator.example"
    refute LazyHTML.text(full) =~ "redirect?"

    older = entry(view, w.older)
    older_link = LazyHTML.query(older, ".research-entry__facts a")
    assert LazyHTML.attribute(older_link, "href") == ["https://ir.example/agm-2026"]
    assert LazyHTML.text(older_link) |> String.trim() == "ir.example"

    upper = note!(w.security, -4, %{"source_url" => "https://IR.Example/Report"})
    hostless = note!(w.security, -3, %{"source_url" => "https:///filing"})
    {:ok, view, _html} = live(conn, "/securities/#{w.security.id}?tab=research")

    for {note, href, shown} <- [
          {upper, "https://IR.Example/Report", "ir.example"},
          {hostless, "https:///filing", "link"}
        ] do
      link = view |> entry(note) |> LazyHTML.query(".research-entry__facts a")
      assert LazyHTML.attribute(link, "href") == [href]
      assert LazyHTML.text(link) |> String.trim() == shown
    end
  end

  # User story (Sprint 29 N3; ADR-0056 D8: the privacy mode keeps the pins):
  # As the operator showing the screen to someone with the privacy mode on,
  # I want the entry's lines kept, in my language,
  # so that the log reads the same: they name no amount.
  #
  # Acceptance criteria:
  # - With the privacy mode on and German chosen, the entry reads its
  #   headline, „Zahlen · positiv“ and „maschinell“, and the superseded one
  #   „nicht im Diagramm, weil ersetzt“.
  test "the privacy mode keeps the entry's lines", %{conn: _conn} do
    w = world()

    masked =
      build_conn()
      |> put_preference_cookie("portfolixir_privacy", "on")
      |> put_preference_cookie("portfolixir_locale", "de")

    {:ok, view, _html} = live(masked, "/securities/#{w.security.id}?tab=research")

    full = entry(view, w.full)

    assert text(full, ".research-entry__headline") ==
             "Quarterly report: revenue above its own outlook"

    assert text(full, ".research-entry__label") == "Zahlen · positiv maschinell"

    assert text(entry(view, w.superseded), ".research-entry__label") ==
             "Ausblick · negativ maschinell · nicht im Diagramm, weil ersetzt"
  end

  # User story (Sprint 29 N3, end to end; ADR-0056 D6, D8):
  # As the operator who keeps a labelled story from the tab „Nachrichten“,
  # I want the entry it writes to read on the Research tab as the pin it
  # draws,
  # so that what I kept reads the same in the log and on the chart.
  #
  # Acceptance criteria:
  # - Saving „Ins Research-Log“ for a story labelled product, positive,
  #   writes an entry that the Research tab shows with the story's title
  #   as its headline, „Product · positive“ and „machine-made“.
  test "a story kept from the tab reads its headline and label on the Research tab",
       %{conn: conn} do
    security = security!("Kept Story AG")
    put_quotes!(security, for(n <- 30..1//-1, do: {day(-n), "50"}))

    story =
      story!(security,
        title: "Kept Story AG wins a synthetic tender",
        at: DateTime.new!(day(-5), ~T[12:00:00.000000], "Etc/UTC")
      )

    label!(story.id, event_type: "product", tone: 1, materiality: 2)

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=news")

    view
    |> element(
      "#security-stories-table button[phx-click='open_promotion'][phx-value-story='#{story.id}']"
    )
    |> render_click()

    view
    |> form("#story-promotion-form", %{"promotion" => %{"body" => "Kept."}})
    |> render_submit()

    view |> element("[role='tab'][phx-value-tab='research']") |> render_click()

    [kept] = Knowledge.list_notes(security.id)
    assert is_integer(kept.news_label_id)
    node = entry(view, kept)
    assert text(node, ".research-entry__headline") == "Kept Story AG wins a synthetic tender"
    assert count(node, ".research-entry__headline .note-glyph--pos") == 1
    assert text(node, ".research-entry__label") == "Product · positive machine-made"
  end
end
