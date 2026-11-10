defmodule PortfolixirWeb.SecurityNoteMarkersTest do
  # ADR-0056 A2 and ADR-0044's amendment of 2026-11-06 (Sprint 28, N9;
  # board ux-design-2026-11-08-sprint28/01, „Marker A — Nadeln am oberen
  # Rand“; plan D-5, D-1 criterion 5): the security chart draws each
  # research note with a headline as a pin at the chart's top edge at its
  # as_of, coloured by its tone, never a raw item or a story; „Notizen“
  # beside „Transaktionen“ toggles them, on the Diagramm tab and under the
  # Übersicht's small chart. Synthetic names and hosts only.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest
  import Portfolixir.NewsFixtures, only: [label!: 2, security!: 1, story!: 2]
  import Portfolixir.WorldFixtures, only: [put_quotes!: 2]
  import PortfolixirWeb.PreferenceCookieHelpers, only: [put_preference_cookie: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Clock
  alias Portfolixir.Knowledge
  alias PortfolixirWeb.Format

  defp day(offset), do: Date.add(Clock.today(), offset)

  defp note!(security, offset, attrs) do
    {:ok, note} =
      Knowledge.append_note(
        Actor.owner_ui(),
        Map.merge(
          %{
            "security_id" => security.id,
            "author" => "operator",
            "kind" => "evidence",
            "body" => "Synthetic finding.",
            "source_quality" => "primary",
            "as_of" => Date.to_iso8601(day(offset))
          },
          attrs
        )
      )

    note
  end

  # A security with closes over the last 100 days, three notes with a
  # headline on three days (positive, negative, none stated), two more on
  # one day, one note without a headline, and a story with its item on a
  # day no note names.
  defp world do
    security = security!("Northwind Harbour Logistics AG")
    put_quotes!(security, for(n <- 100..1//-1, do: {day(-n), "#{100 + rem(n, 7)}"}))

    raise_note =
      note!(security, -80, %{
        "headline" => "Capital raise funds the terminal",
        "event_type" => "capital_measure",
        "tone" => 1
      })

    lawsuit =
      note!(security, -60, %{"headline" => "Suit filed", "event_type" => "legal", "tone" => -1})

    plain = note!(security, -40, %{"headline" => "Plain headline"})
    note!(security, -30, %{"headline" => "Outlook kept", "event_type" => "guidance", "tone" => 0})

    note!(security, -30, %{
      "headline" => "New product line",
      "event_type" => "product",
      "tone" => 1
    })

    note!(security, -20, %{})
    story!(security, title: "Northwind Harbour named in a market wrap", at: day_time(-10))

    %{security: security, raise_note: raise_note, lawsuit: lawsuit, plain: plain}
  end

  defp day_time(offset), do: DateTime.new!(day(offset), ~T[12:00:00.000000], "Etc/UTC")

  defp pins(view, scope) do
    view
    |> render()
    |> LazyHTML.from_document()
    |> LazyHTML.query(scope <> " g.note-pin")
  end

  defp attr(node, name), do: node |> LazyHTML.attribute(name) |> List.first()

  # User story (ADR-0056 A2; ADR-0044's amendment; plan D-5, marker A):
  # As the operator reading a security's chart,
  # I want each research note with a headline drawn as a pin at the top
  # edge at its date, coloured by its tone, its tooltip the headline, the
  # event type, the tone and the date,
  # so that I see when something judged worth keeping became public,
  # without the pins covering the trades or the price.
  #
  # Acceptance criteria:
  # - One pin per day with notes with a headline, at the plot's top edge,
  #   for every such day in the window: 4 pins here (-80, -60, -40, -30).
  # - A note without a headline draws nothing, and a story and its item on
  #   a day no note names draw nothing (never a raw item or a story).
  # - The pin's class names its tone (pos, neg, neu); a day whose notes
  #   differ in tone is mixed and carries their count; the tone is also a
  #   glyph, never colour alone: a plus, a minus, a ± for a mixed day
  #   (closing act, ND3), none for a neutral one.
  # - Its title, and the payload's tooltip lines, read the headline, the
  #   event type in words, the tone in words and the date, every headline
  #   of the day.
  test "the Diagramm tab draws a pin per day with headline notes, never a story", %{conn: conn} do
    w = world()
    {:ok, view, _html} = live(conn, "/securities/#{w.security.id}?tab=chart")

    pins = pins(view, "#detail-tab-panel-chart")

    assert Enum.map(pins, &attr(&1, "data-date")) ==
             Enum.map([-80, -60, -40, -30], &Date.to_iso8601(day(&1)))

    refute Enum.any?(
             pins,
             &(attr(&1, "data-date") in [Date.to_iso8601(day(-20)), Date.to_iso8601(day(-10))])
           )

    tones = Map.new(pins, &{attr(&1, "data-date"), attr(&1, "class")})
    assert tones[Date.to_iso8601(day(-80))] =~ "note-pin--pos"
    assert tones[Date.to_iso8601(day(-60))] =~ "note-pin--neg"
    assert tones[Date.to_iso8601(day(-40))] =~ "note-pin--neu"
    assert tones[Date.to_iso8601(day(-30))] =~ "note-pin--mixed"

    assert has_element?(view, "g.note-pin--pos path.note-pin__glyph")
    assert has_element?(view, "g.note-pin--neg path.note-pin__glyph")
    # Closing act of Sprint 28, ND3: a mixed day has its own glyph (±), so
    # it does not read as a neutral one.
    assert has_element?(view, "g.note-pin--mixed path.note-pin__glyph")
    refute has_element?(view, "g.note-pin--neu path.note-pin__glyph")

    assert has_element?(
             view,
             "g.note-pin[data-date='#{Date.to_iso8601(day(-30))}'] .note-pin__count",
             "2"
           )

    raise_title = "g.note-pin[data-date='#{Date.to_iso8601(day(-80))}'] title"
    assert has_element?(view, raise_title, "Capital raise funds the terminal")

    assert has_element?(
             view,
             raise_title,
             "Capital measure · positive · #{Format.date(day(-80))}"
           )

    both = "g.note-pin[data-date='#{Date.to_iso8601(day(-30))}'] title"
    assert has_element?(view, both, "Outlook kept")
    assert has_element?(view, both, "New product line")
    assert has_element?(view, both, "Guidance · neutral")

    plain = "g.note-pin[data-date='#{Date.to_iso8601(day(-40))}'] title"
    assert has_element?(view, plain, "Plain headline")
    assert has_element?(view, plain, Format.date(day(-40)))

    payload =
      view
      |> render()
      |> LazyHTML.from_document()
      |> LazyHTML.query("#detail-tab-panel-chart script[data-chart-payload]")
      |> LazyHTML.text()
      |> Jason.decode!()

    assert length(payload["notes"]) == 4
    raise = Enum.find(payload["notes"], &(&1["date"] == Date.to_iso8601(day(-80))))

    assert raise["lines"] == [
             [
               "Capital raise funds the terminal",
               "Capital measure · positive · #{Format.date(day(-80))}"
             ]
           ]
  end

  # User story (board 01 A: „Abschaltbar („Notizen“)“; plan N9):
  # As the operator who wants the price alone for a moment,
  # I want a „Notizen“ toggle beside „Transaktionen“ on the Diagramm tab
  # and under the Übersicht's small chart,
  # so that I can hide the pins and bring them back.
  #
  # Acceptance criteria:
  # - The Diagramm tab's toolbar has „Show notes“ after „Show
  #   transactions“, pressed by default; a click hides every pin and
  #   unpresses it; a second click brings them back.
  # - The Übersicht's small chart draws the same pins under its own
  #   toggle, which hides them there.
  # - The privacy mode keeps the pins and their titles: they name no
  #   amount.
  test "„Notizen“ toggles the pins on the Diagramm tab and the Übersicht", %{conn: conn} do
    w = world()
    {:ok, view, _html} = live(conn, "/securities/#{w.security.id}?tab=chart")

    toolbar =
      view
      |> render()
      |> LazyHTML.from_document()
      |> LazyHTML.query("#detail-tab-panel-chart .chart-toggles button")
      |> Enum.map(&attr(&1, "id"))

    assert Enum.drop_while(toolbar, &(&1 != "toggle-transactions")) |> Enum.take(2) ==
             ["toggle-transactions", "toggle-notes"]

    assert has_element?(view, "#toggle-notes[aria-pressed='true']", "Show notes")
    view |> element("#toggle-notes") |> render_click()
    assert has_element?(view, "#toggle-notes[aria-pressed='false']")
    assert pins(view, "#detail-tab-panel-chart") |> Enum.to_list() == []
    view |> element("#toggle-notes") |> render_click()
    assert length(Enum.to_list(pins(view, "#detail-tab-panel-chart"))) == 4

    {:ok, overview, _html} = live(conn, "/securities/#{w.security.id}")
    assert length(Enum.to_list(pins(overview, ".overview-chart"))) == 4
    assert has_element?(overview, "#toggle-notes-overview[aria-pressed='true']")
    overview |> element("#toggle-notes-overview") |> render_click()
    assert pins(overview, ".overview-chart") |> Enum.to_list() == []

    masked =
      build_conn()
      |> put_preference_cookie("portfolixir_privacy", "on")
      |> put_preference_cookie("portfolixir_locale", "de")

    {:ok, private, _html} = live(masked, "/securities/#{w.security.id}?tab=chart")
    assert length(Enum.to_list(pins(private, "#detail-tab-panel-chart"))) == 4

    assert has_element?(
             private,
             "g.note-pin[data-date='#{Date.to_iso8601(day(-80))}'] title",
             "Kapitalmaßnahme · positiv"
           )

    assert has_element?(private, "#toggle-notes", "Notizen")
  end

  # User story (plan D-1, criterion 5, end to end; ADR-0056 §8, A2):
  # As the operator who keeps a story,
  # I want the note I save from the tab „Nachrichten“ drawn on the chart at
  # the story's day, and nothing before I save,
  # so that the chart shows what I judged worth keeping, and only that.
  #
  # Acceptance criteria:
  # - With a story and no note, the chart draws no pin.
  # - Opening „Ins Research-Log“ draws none; saving it draws one pin at
  #   the story's day with its pre-filled headline.
  test "a story kept from the tab is drawn on the chart, and only once kept", %{conn: conn} do
    security = security!("Kept Story AG")
    put_quotes!(security, for(n <- 30..1//-1, do: {day(-n), "50"}))
    story = story!(security, title: "Kept Story AG wins a synthetic tender", at: day_time(-5))
    label!(story.id, event_type: "product", tone: 1, materiality: 2)
    path = "/securities/#{security.id}"

    {:ok, view, _html} = live(conn, path <> "?tab=chart")
    assert pins(view, "#detail-tab-panel-chart") |> Enum.to_list() == []

    view |> element("[role='tab'][phx-value-tab='news']") |> render_click()

    view
    |> element(
      "#security-stories-table button[phx-click='open_promotion'][phx-value-story='#{story.id}']"
    )
    |> render_click()

    view |> element("[role='tab'][phx-value-tab='chart']") |> render_click()
    assert pins(view, "#detail-tab-panel-chart") |> Enum.to_list() == []

    view |> element("[role='tab'][phx-value-tab='news']") |> render_click()

    view
    |> element(
      "#security-stories-table button[phx-click='open_promotion'][phx-value-story='#{story.id}']"
    )
    |> render_click()

    view
    |> form("#story-promotion-form", %{"promotion" => %{"body" => "Kept."}})
    |> render_submit()

    view |> element("[role='tab'][phx-value-tab='chart']") |> render_click()
    assert [pin] = Enum.to_list(pins(view, "#detail-tab-panel-chart"))
    assert attr(pin, "data-date") == Date.to_iso8601(day(-5))
    assert attr(pin, "class") =~ "note-pin--pos"

    assert has_element?(
             view,
             "g.note-pin title",
             "Kept Story AG wins a synthetic tender"
           )
  end
end
