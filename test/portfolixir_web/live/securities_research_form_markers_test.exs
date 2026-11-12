defmodule PortfolixirWeb.SecuritiesResearchFormMarkersTest do
  # Sprint 29, N4 (board ux-design-2026-11-12-sprint29/03, frames ⑦ to ⑪,
  # recommendation A; ADR-0054 §4; ADR-0056 §8, D6, E2): the Research
  # tab's form „Append an entry“ takes a headline, an event type and a
  # tone on an evidence or event-result entry, with notes.append's
  # validation; until now the operator could set them only by keeping a
  # story, while an agent could write them on any entry. And the story's
  # „To the research log“ form, its twin, shows its source link's domain,
  # never the link in full. Synthetic names and hosts only.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest
  import Portfolixir.NewsFixtures, only: [security!: 1, story!: 2]

  alias Portfolixir.Knowledge
  alias Portfolixir.Knowledge.SecurityNote

  @form "#research-entry-form"
  @marker_fields ~w(headline event_type tone)

  defp api_notes(security) do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
    |> get("/api/v1/securities/#{security.id}/notes")
    |> json_response(200)
    |> get_in(["data", "entries"])
  end

  defp field?(view, name), do: has_element?(view, "#{@form} [name='note[#{name}]']")

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

  # The form's field names in document order, as the operator tabs through.
  defp field_order(view) do
    view
    |> element(@form)
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("[name]")
    |> LazyHTML.attribute("name")
  end

  # User story (Sprint 29 N4; board 03 ⑧ A):
  # As the operator appending a finding to a security's research log,
  # I want to give it a headline, an event type and a tone in the form,
  # as the agent can over notes.append,
  # so that my own entry is drawn on the chart and reads as N3 draws it.
  #
  # Acceptance criteria:
  # - With the kind Evidence the form offers „Headline“ with its hint,
  #   „Event type“ (first „— not stated —“, then the eight types in words)
  #   and „Tone“ (first „— not stated —“, then positive · neutral ·
  #   negative), after „Supersedes“ and before „Entry“.
  # - Submitting them appends an entry by the operator that reads the
  #   headline behind the pin's glyph and „Earnings · positive“ under it;
  #   the API answers what was typed, with no news label.
  # - The form is empty again after the save.
  test "the operator writes a headline, an event type and a tone on an evidence entry",
       %{conn: conn} do
    security = security!("Formfield Harbour AG")
    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=research")

    assert has_element?(
             view,
             "#{@form} select[name='note[kind]'] option[selected][value='evidence']"
           )

    assert Enum.all?(@marker_fields, &field?(view, &1))

    order = field_order(view)

    assert Enum.drop_while(order, &(&1 != "note[supersedes_id]")) |> Enum.take(5) ==
             ~w(note[supersedes_id] note[headline] note[event_type] note[tone] note[body])

    assert has_element?(
             view,
             "#{@form} input[type='text'][name='note[headline]'][aria-describedby='research-headline-hint']"
           )

    refute has_element?(view, "#{@form} input[name='note[headline]'][maxlength]")

    assert has_element?(
             view,
             "#{@form} #research-headline-hint",
             "At most 80 characters, one line. Only an entry with a headline is drawn as a pin on the chart."
           )

    assert view
           |> element(@form)
           |> render()
           |> LazyHTML.from_fragment()
           |> LazyHTML.query("select[name='note[event_type]'] option")
           |> LazyHTML.attribute("value") == ["" | SecurityNote.event_types()]

    assert has_element?(
             view,
             "#{@form} select[name='note[event_type]'] option[value='']",
             "— not stated —"
           )

    assert has_element?(
             view,
             "#{@form} select[name='note[event_type]'] option[value='m_and_a']",
             "M&A"
           )

    assert view
           |> element(@form)
           |> render()
           |> LazyHTML.from_fragment()
           |> LazyHTML.query("select[name='note[tone]'] option")
           |> LazyHTML.attribute("value") == ["", "1", "0", "-1"]

    assert has_element?(view, "#{@form} select[name='note[tone]'] option[value='-1']", "negative")

    typed = %{
      kind: "evidence",
      headline: "Quarterly report: revenue above its own outlook",
      event_type: "earnings",
      tone: "1",
      body: "Revenue came in above the July outlook.",
      source_quality: "primary",
      as_of: "2026-10-30",
      source_url: "https://ir.example/reports/q3-2026"
    }

    view |> form(@form, note: typed) |> render_submit()

    assert render(view) =~ "Entry appended."
    [note] = Knowledge.list_notes(security.id)
    assert note.author == :operator
    assert is_nil(note.news_label_id)

    [api] = api_notes(security)
    assert api["id"] == note.id
    assert api["author"] == "operator"
    assert api["headline"] == typed.headline
    assert api["event_type"] == typed.event_type
    assert api["tone"] == 1
    assert api["body"] == typed.body
    assert api["news_label_id"] == nil

    node = entry(view, note)
    assert text(node, ".research-entry__headline") == typed.headline

    assert node |> LazyHTML.query(".research-entry__headline .note-glyph--pos") |> Enum.count() ==
             1

    assert text(node, ".research-entry__label") == "Earnings · positive"

    # The form is empty again, the kind back to Evidence.
    refute has_element?(view, "#{@form} input[name='note[headline]'][value]")

    refute has_element?(
             view,
             "#{@form} select[name='note[event_type]'] option[selected][value='earnings']"
           )

    refute has_element?(view, "#{@form} select[name='note[tone]'] option[selected][value='1']")
  end

  # User story (Sprint 29 N4; board 03 ⑧ A, the thesis frame):
  # As the operator choosing the kind of an entry,
  # I want the three fields only on the kinds that carry them,
  # so that a thesis, a risk or a decision is never offered a pin.
  #
  # Acceptance criteria:
  # - Switching the kind to Thesis removes the three fields and shows the
  #   thesis fields; a thesis saved then carries none of the three.
  # - Switching to Event result shows them again; an event result with a
  #   headline and a negative tone is saved and reads them.
  # - Every other kind (invalidation check, risk, retraction, decision)
  #   shows none of them.
  test "the three fields show on evidence and event result only", %{conn: conn} do
    security = security!("Kindswitch Logistics AG")
    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=research")

    view |> form(@form, note: %{kind: "thesis"}) |> render_change()
    refute Enum.any?(@marker_fields, &field?(view, &1))
    refute has_element?(view, "#research-headline-hint")
    refute has_element?(view, "#{@form} [data-role='research-marker-fields']")
    assert field?(view, "conviction")

    view
    |> form(@form,
      note: %{
        kind: "thesis",
        body: "Holds while margins hold.",
        source_quality: "primary",
        as_of: "2026-10-01"
      }
    )
    |> render_submit()

    [thesis] = api_notes(security)
    assert thesis["kind"] == "thesis"
    assert {thesis["headline"], thesis["event_type"], thesis["tone"]} == {nil, nil, nil}

    for kind <- SecurityNote.kinds() -- SecurityNote.marker_kinds() do
      view |> form(@form, note: %{kind: kind}) |> render_change()
      refute Enum.any?(@marker_fields, &field?(view, &1)), "#{kind} offers a marker field"
    end

    view |> form(@form, note: %{kind: "event_result"}) |> render_change()
    assert Enum.all?(@marker_fields, &field?(view, &1))

    view
    |> form(@form,
      note: %{
        kind: "event_result",
        headline: "Guidance cut after the strike",
        event_type: "guidance",
        tone: "-1",
        body: "The outlook was lowered.",
        source_quality: "primary",
        as_of: "2026-10-02"
      }
    )
    |> render_submit()

    result = Enum.find(api_notes(security), &(&1["kind"] == "event_result"))

    assert {result["headline"], result["event_type"], result["tone"]} ==
             {"Guidance cut after the strike", "guidance", -1}

    note = Enum.find(Knowledge.list_notes(security.id), &(&1.id == result["id"]))
    assert text(entry(view, note), ".research-entry__label") == "Guidance · negative"
  end

  # User story (Sprint 29 N4; board 03 ⑨ A; ADR-0054 §4):
  # As the operator whose headline is one character too long,
  # I want it refused in the form's error list in my language, the field
  # marked invalid and what I typed kept,
  # so that I shorten it rather than type the entry again.
  #
  # Acceptance criteria:
  # - An 81-character headline is refused with „Überschrift: darf
  #   höchstens 80 Zeichen lang sein“; the input carries
  #   aria-invalid="true"; nothing is appended.
  # - The headline, the event type, the tone and the body stay as typed.
  # - Shortened to 80 characters, the same entry is saved and the field
  #   is no longer marked.
  test "an 81-character headline is refused, named, marked and kept", %{conn: conn} do
    security = security!("Lengthcheck AG")
    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=research&locale=de")

    assert has_element?(view, "#{@form} label", "Überschrift")
    assert has_element?(view, "#{@form} label", "Ereignisart")
    assert has_element?(view, "#{@form} label", "Tonalität")

    assert has_element?(
             view,
             "#research-headline-hint",
             "Höchstens 80 Zeichen, eine Zeile. Nur ein Eintrag mit Überschrift steht als Nadel im Diagramm."
           )

    assert has_element?(
             view,
             "#{@form} select[name='note[tone]'] option[value='']",
             "— nicht angegeben —"
           )

    long = String.duplicate("ä", 81)

    typed = %{
      kind: "evidence",
      headline: long,
      event_type: "earnings",
      tone: "0",
      body: "Synthetic finding kept while the headline is shortened.",
      source_quality: "primary",
      as_of: "2026-10-30"
    }

    view |> form(@form, note: typed) |> render_submit()

    errors = view |> element(".research-entry-form__errors") |> render()
    assert errors =~ "Überschrift: darf höchstens 80 Zeichen lang sein"
    assert Knowledge.list_notes(security.id) == []

    assert has_element?(
             view,
             "#{@form} input[name='note[headline]'][aria-invalid='true'][value='#{long}']"
           )

    refute has_element?(view, "#{@form} textarea[aria-invalid]")

    assert has_element?(
             view,
             "#{@form} select[name='note[event_type]'] option[selected][value='earnings']"
           )

    assert has_element?(view, "#{@form} select[name='note[tone]'] option[selected][value='0']")
    assert has_element?(view, "#{@form} textarea[name='note[body]']", typed.body)

    view |> form(@form, note: %{typed | headline: String.slice(long, 0, 80)}) |> render_submit()

    assert [%{"headline" => headline, "tone" => 0}] = api_notes(security)
    assert headline == String.duplicate("ä", 80)
    refute has_element?(view, "#{@form} [aria-invalid]")
    refute has_element?(view, ".research-entry-form__errors")
  end

  # User story (Sprint 29 N4; board 03 ⑨: the grid's border rule won over
  # the general one, in both forms):
  # As the operator whose field is refused,
  # I want its border red, in the research form and in „To the research
  # log“ alike,
  # so that the refused field is seen, not only read in the list.
  #
  # Acceptance criteria:
  # - app.css carries `.research-entry-form__grid [aria-invalid="true"]`
  #   with the danger colour's border, after the grid's own border rule
  #   (whose specificity it outranks).
  test "a refused field's border is red inside the form's grid" do
    css = File.read!("priv/static/app.css")

    assert [rule] =
             Regex.run(
               ~r/\.research-entry-form__grid \[aria-invalid="true"\] \{[^}]*\}/s,
               css
             )

    assert rule =~ "border-color: var(--color-danger);"

    {grid_rule, _} = :binary.match(css, ".research-entry-form__grid textarea {\n  min-width: 0;")
    {invalid_rule, _} = :binary.match(css, rule)
    assert invalid_rule > grid_rule
  end

  # User story (Sprint 29 N4, N3's S3 finding; ADR-0056 E2):
  # As the operator keeping a story with an aggregator's long link,
  # I want „To the research log“ to show the link's domain and open the
  # link,
  # so that a 2,048-character link does not fill the form.
  #
  # Acceptance criteria:
  # - The form's source fact reads the link's host; its href
  #   is the full link the entry will store; the link is printed nowhere
  #   in the form.
  test "„To the research log“ shows the source link's domain", %{conn: conn} do
    security = security!("Linkfact Shipping AG")
    path = String.duplicate("segment-abcdef0123456789/", 60)
    link = "https://news.aggregator.example/articles/" <> path <> "end"

    story = story!(security, title: "Linkfact Shipping AG wins a synthetic tender", link: link)

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=news")

    view
    |> element(
      "#security-stories-table button[phx-click='open_promotion'][phx-value-story='#{story.id}']"
    )
    |> render_click()

    node =
      view
      |> element("#story-promotion-form")
      |> render()
      |> LazyHTML.from_fragment()

    anchor = LazyHTML.query(node, "[data-role='promotion-source'] a")
    [href] = LazyHTML.attribute(anchor, "href")
    assert String.length(href) > 1_000
    assert String.ends_with?(href, "segment-abcdef0123456789/end")
    assert anchor |> LazyHTML.text() |> String.trim() == "news.aggregator.example"
    refute LazyHTML.text(node) =~ "segment-abcdef"
  end
end
