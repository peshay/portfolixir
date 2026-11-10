defmodule PortfolixirWeb.SecurityStoriesNLensTest do
  # Sprint 28 plan D-8, Lane N's closing act (the correctness and security
  # lenses on N8): the security's tab „Nachrichten“ and its note form,
  # whose save is the operator's confirmation of a story's entry (ADR-0056
  # §8; NFR-10; ADR-0044's amendment of 2026-11-06, "the writer may change
  # any of them before the write"). The cases were tagged `:n_lens_red`
  # while they showed a defect the lenses found; the closing act's fixes
  # (NL1, ND1, ND2) made them pass. Synthetic names and hosts only.
  use PortfolixirWeb.ConnCase

  import Ecto.Query, only: [from: 2]
  import Phoenix.LiveViewTest
  import Portfolixir.NewsFixtures, only: [label!: 2, security!: 1, story!: 2]

  alias Portfolixir.Knowledge
  alias Portfolixir.News.Item
  alias Portfolixir.Repo

  defp open_form(conn, security, story) do
    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=news")
    view |> element("#open-promotion-#{story.id}") |> render_click()
    assert has_element?(view, "#story-promotion-form")
    view
  end

  defp save(view, params) do
    view
    |> form("#story-promotion-form", %{"promotion" => params})
    |> render_submit()
  end

  # User story (ADR-0044's amendment: the writer may change any of the
  # pre-filled fields; the form offers „— not stated —“ for the event type
  # and the tone, and an empty headline):
  # As the operator keeping a story without the outside model's reading,
  # I want the event type, the tone and the headline I cleared to stay
  # cleared,
  # so that the entry states only what I confirmed, and no pin is drawn
  # for an entry I gave no headline.
  #
  # Acceptance criteria:
  # - Saving with the headline emptied and the event type and tone set to
  #   „— not stated —“ stores an entry without a headline, an event type
  #   or a tone, and without the label's id as provenance.
  test "a field the operator cleared is stored cleared, not re-filled from the story",
       %{conn: conn} do
    security = security!("Cleared Fields Synthetic AG")
    story = story!(security, title: "Cleared Fields Synthetic AG wins a contract")
    label!(story.id, event_type: "product", tone: 1, materiality: 2)

    view = open_form(conn, security, story)

    save(view, %{
      "headline" => "",
      "event_type" => "",
      "tone" => "",
      "body" => "Kept without the model's reading."
    })

    assert [note] = Knowledge.list_notes(security.id)
    assert note.body == "Kept without the model's reading."
    assert note.headline == nil
    assert note.event_type == nil
    assert note.tone == nil
    assert note.news_label_id == nil
  end

  # User story (NFR-10: the save is the confirmation):
  # As the operator whose first save was refused,
  # I want what I changed before it to be what the second save stores,
  # so that a refusal never turns my change back into the proposal.
  #
  # Acceptance criteria:
  # - The tone changed from the label's positive to neutral, saved once
  #   with an empty entry text (refused naming the body) and again with a
  #   text, is stored neutral.
  test "a change survives a refused save", %{conn: conn} do
    security = security!("Refused Save Synthetic AG")
    story = story!(security, title: "Refused Save Synthetic AG wins a contract")
    label!(story.id, event_type: "product", tone: 1, materiality: 2)

    view = open_form(conn, security, story)

    save(view, %{"tone" => "0", "body" => ""})
    assert Knowledge.list_notes(security.id) == []
    assert has_element?(view, "#story-promotion-form [data-role='promotion-error-body']")

    save(view, %{"tone" => "0", "body" => "Kept, read as neutral."})

    assert [note] = Knowledge.list_notes(security.id)
    assert note.tone == 0
  end

  # User story (NFR-10: the save is the confirmation of what was shown;
  # ADR-0044's amendment: the entry keeps the label's id as provenance):
  # As the operator saving a story's entry while the outside model labels
  # the story again,
  # I want the entry to store what the form showed me, and to name a label
  # only while that label says what the entry says,
  # so that nothing I did not see lands in the research log.
  #
  # Acceptance criteria:
  # - A second model's label written after the form opened is not stored:
  #   the entry keeps the shown event type and tone and the shown label's
  #   id.
  # - The shown label rewritten in place to another reading: the entry
  #   keeps the shown values and names no label.
  test "a label written after the form opened is not stored unseen", %{conn: conn} do
    security = security!("Stale Label Synthetic AG")
    story = story!(security, title: "Stale Label Synthetic AG wins a contract")
    shown = label!(story.id, event_type: "product", tone: 1, materiality: 2)

    view = open_form(conn, security, story)
    _newer = label!(story.id, model: "synthetic-model-2", event_type: "earnings", tone: -1)
    save(view, %{"body" => "Kept as shown."})

    assert [note] = Knowledge.list_notes(security.id)
    assert {note.event_type, note.tone, note.news_label_id} == {:product, 1, shown.id}

    other = security!("Rewritten Label Synthetic AG")
    story = story!(other, title: "Rewritten Label Synthetic AG wins a contract")
    shown = label!(story.id, event_type: "product", tone: 1, materiality: 2)

    view = open_form(conn, other, story)
    rewritten = label!(story.id, event_type: "earnings", tone: -1)
    assert rewritten.id == shown.id
    save(view, %{"body" => "Kept as shown."})

    assert [note] = Knowledge.list_notes(other.id)
    assert {note.event_type, note.tone, note.news_label_id} == {:product, 1, nil}
  end

  # User story (NFR-10; ADR-0056 §8: the date, the source link and the
  # source quality are the story's, shown, not offered):
  # As the operator saving an entry whose story changed after I opened
  # the form,
  # I want nothing written and the form to show the story as it is now,
  # so that I never confirm a date or a source I did not see.
  #
  # Acceptance criteria:
  # - The story's date moved after the form opened: the save writes
  #   nothing, the form shows the new date and a line saying the story
  #   changed, and keeps what was typed; saving again writes the entry.
  test "a story that changed after the form opened is shown anew, nothing written",
       %{conn: conn} do
    security = security!("Changed Story Synthetic AG")
    story = story!(security, title: "Changed Story Synthetic AG wins a contract")

    view = open_form(conn, security, story)

    Repo.update_all(from(i in Item, where: i.cluster_id == ^story.id),
      set: [
        published_at: ~U[2026-10-01 09:00:00.000000Z],
        published_at_claimed: ~U[2026-10-01 09:00:00.000000Z]
      ]
    )

    save(view, %{"body" => "Typed before the change."})

    assert Knowledge.list_notes(security.id) == []
    assert has_element?(view, "[data-role='promotion-story-changed']")
    assert has_element?(view, "[data-role='promotion-as-of']", "2026")
    assert render(view) =~ "Typed before the change."

    save(view, %{"body" => "Typed before the change."})
    assert [note] = Knowledge.list_notes(security.id)
    assert note.as_of == ~D[2026-10-01]
  end

  # --- closing act, ND1 begin ---

  # User story (board 01; the research form's errors read in the page's
  # language, E25 S6):
  # As the operator on a German page saving a story's entry,
  # I want the headline's refusal in German,
  # so that I read what to change without the API's English.
  #
  # Acceptance criteria:
  # - On the German page, a pre-filled headline carrying U+200B saved as
  #   proposed names the error at the headline in German, naming U+200B.
  test "the form's field errors read in the page's language", %{conn: conn} do
    security = security!("German Error Synthetic AG")

    story =
      story!(security,
        title: "German" <> <<0x200B::utf8>> <> "Error Synthetic AG wins a contract"
      )

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=news&locale=de")
    view |> element("#open-promotion-#{story.id}") |> render_click()
    save(view, %{"body" => "Behalten."})

    assert Knowledge.list_notes(security.id) == []

    assert view
           |> element("[data-role='promotion-error-headline']")
           |> render() =~ "darf keine unsichtbaren Zeichen enthalten (U+200B)"
  end

  # --- closing act, ND1 end ---

  # --- closing act, ND2 begin ---

  # User story (board 01; ADR-0054 §4: an invisible character is spelled
  # where the operator sees it):
  # As the operator promoting a story whose title carries a character I
  # cannot see,
  # I want the pre-filled headline to show it spelled, and the note saying
  # so across the form's width,
  # so that I see what to retype instead of mirrored text.
  #
  # Acceptance criteria:
  # - A title carrying U+202E pre-fills the headline as „[U+202E]“, never
  #   the raw character.
  # - The invisible-text note spans the form's grid (its full row).
  # - Saved as proposed, the entry is still refused naming the headline;
  #   retyped, it is stored as typed.
  test "a headline with an invisible character is pre-filled spelled, its note across the form",
       %{conn: conn} do
    security = security!("Mirrored Title Synthetic AG")

    story =
      story!(security,
        title: "Mirrored" <> <<0x202E::utf8>> <> "Title Synthetic AG wins a contract"
      )

    view = open_form(conn, security, story)

    input = view |> element("#story-promotion-form input[name='promotion[headline]']") |> render()
    assert input =~ "Mirrored[U+202E]Title Synthetic AG wins a contract"
    refute input =~ <<0x202E::utf8>>

    assert has_element?(
             view,
             "#story-promotion-form .research-entry-form__full [data-role='invisible-text-note']"
           )

    save(view, %{"body" => "Kept."})
    assert Knowledge.list_notes(security.id) == []
    assert has_element?(view, "[data-role='promotion-error-headline']")

    save(view, %{"headline" => "Mirrored Title Synthetic AG wins a contract", "body" => "Kept."})
    assert [note] = Knowledge.list_notes(security.id)
    assert note.headline == "Mirrored Title Synthetic AG wins a contract"
  end

  # --- closing act, ND2 end ---

  # --- closing act, board 01 below the cut begin ---

  # User story (board 01; DESIGN.md: one primary action a form, the house
  # empty state, times named in their zone as the news page names them):
  # As the operator on the security's tab „Nachrichten“,
  # I want the save to read as the form's primary action, the tab to say
  # its times are UTC, and an empty tab in the house's empty-state box,
  # so that the tab reads like the rest of the page.
  #
  # Acceptance criteria:
  # - The German tab says „Zeiten in UTC“; an empty tab's line is an
  #   `.empty-state`.
  # - The form's „Ins Research-Log speichern“ is a `.button-primary`.
  test "the tab names its times UTC, its empty state is the house's, its save the primary action",
       %{conn: conn} do
    quiet = security!("Quiet Tab Synthetic AG")
    {:ok, view, _html} = live(conn, "/securities/#{quiet.id}?tab=news&locale=de")
    assert has_element?(view, "[data-role='stories-basis']", "Zeiten in UTC")
    assert has_element?(view, "#security-stories-empty.empty-state")

    security = security!("Primary Save Synthetic AG")
    story = story!(security, title: "Primary Save Synthetic AG wins a contract")
    view = open_form(conn, security, story)

    assert has_element?(
             view,
             "#story-promotion-form button[type='submit'].button-primary",
             "Save to the research log"
           )
  end

  # --- closing act, board 01 below the cut end ---
end
