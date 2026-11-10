defmodule PortfolixirWeb.SecurityStoriesNLensTest do
  # Sprint 28 plan D-8, Lane N's closing act (the correctness and security
  # lenses on N8): the security's tab „Nachrichten“ and its note form,
  # whose save is the operator's confirmation of a story's entry (ADR-0056
  # §8; NFR-10; ADR-0044's amendment of 2026-11-06, "the writer may change
  # any of them before the write"). Cases tagged `:n_lens_red` show a
  # defect the lenses found and fail until it is fixed. Synthetic names and
  # hosts only.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest
  import Portfolixir.NewsFixtures, only: [label!: 2, security!: 1, story!: 2]

  alias Portfolixir.Knowledge

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
  @tag :n_lens_red
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
  @tag :n_lens_red
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
end
