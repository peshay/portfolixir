defmodule PortfolixirWeb.Components.DataNoteClampTest do
  # The clamped data note of board `ux-design-2026-11-01-sprint22/01-i1` ③
  # (I1, #1351, pick Q1): a note's text clamps to two lines (three under
  # 560 px) with „mehr“ only where the text is cut, and its remedy control
  # stays visible under the clamp. LiveViewTest runs no client script, so
  # the measuring hook is pinned on its source.
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest

  alias PortfolixirWeb.AppShell

  @css File.read!("priv/static/app.css")

  defp rule(selector) do
    case Regex.run(~r/(?:^|\n)\s*#{Regex.escape(selector)} \{([^}]*)\}/, @css) do
      [_, body] -> body
      nil -> flunk("no rule for #{selector}")
    end
  end

  defp hook_source(name) do
    "lib/portfolixir_web/layout_view.ex"
    |> File.read!()
    |> String.split("Hooks.#{name} = ")
    |> Enum.at(1, "")
    |> String.split("Hooks.")
    |> hd()
  end

  defp query(html, selector), do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)

  # User story (#1351, board 01 ③; Q1 corrections 1 and 2):
  # As the operator reading a page's data notes,
  # I want each note cut to two lines with "more" where it is cut, and its
  # remedy button still in view,
  # so that the notes stop filling the page while what they count and what
  # fixes them stay visible.
  #
  # Acceptance criteria:
  # - A clamped note (`clamp`) carries `data-note--clamped` and the
  #   `NoteClamp` hook (so it needs its `id`); its text sits in
  #   `.data-note__text#<id>-text`, its remedy (`:actions`) in
  #   `.data-note__actions` after the text, never inside the clamp.
  # - The "more" button follows the body: `button.link-button.data-note__more`,
  #   `hidden` until the client measures a cut, `aria-expanded="false"`,
  #   `aria-controls` naming the text, with "more" and "less" for the hook to
  #   write as its label (the server renders the button empty).
  # - A note without `clamp` renders as before: no text wrapper, no button.
  # - The stylesheet clamps the text to two lines, three under 560 px, and
  #   an expanded note (`[data-expanded]`) shows it whole.
  # - The hook shows "more" only where the text is cut (scrollHeight beyond
  #   clientHeight), toggles `data-expanded`, `aria-expanded` and the label
  #   on its click, re-measures when a fold around it opens or its box
  #   changes size (a window resize, the page's scrollbar appearing), and
  #   re-applies its state after every patch.
  test "a clamped note cuts its text, keeps its remedy visible and offers more" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <AppShell.data_note severity={:attention} id="dq-missing-fx" data-role="dq-missing-fx" clamp>
        Two held positions are missing from the totals: Alpha Inc (33.00 USD).
        <:actions><button type="button" phx-click="sync_rates">Sync exchange rates</button></:actions>
      </AppShell.data_note>
      """)

    note =
      "div#dq-missing-fx.data-note.data-note--attention.data-note--clamped[phx-hook='NoteClamp']"

    assert Enum.count(query(html, note)) == 1

    text = query(html, note <> " > .data-note__body > .data-note__text#dq-missing-fx-text")
    assert LazyHTML.text(text) =~ "missing from the totals: Alpha Inc"
    assert Enum.empty?(LazyHTML.query(text, "button"))

    assert html
           |> query(
             note <> " > .data-note__body > .data-note__text + .data-note__actions > button"
           )
           |> LazyHTML.text() ==
             "Sync exchange rates"

    more =
      query(
        html,
        note <>
          " > .data-note__body + button.link-button.data-note__more[type='button'][hidden][aria-expanded='false'][aria-controls='dq-missing-fx-text'][data-more='more'][data-less='less']"
      )

    # The hook writes the label; the server's button is empty, so the
    # note's text is its sentence alone.
    assert Enum.count(more) == 1
    assert more |> LazyHTML.text() |> String.trim() == ""

    plain =
      rendered_to_string(~H"""
      <AppShell.data_note severity={:note}>A plain note.</AppShell.data_note>
      """)

    assert Enum.empty?(query(plain, ".data-note__text, .data-note__more, [phx-hook]"))

    clamp = rule(".data-note--clamped .data-note__text")
    assert clamp =~ ~r/-webkit-line-clamp:\s*2;/
    assert clamp =~ ~r/overflow:\s*hidden;/

    assert @css =~
             ~r/@media \(max-width: 560px\) \{\s*\.data-note--clamped \.data-note__text \{\s*-webkit-line-clamp:\s*3;/

    assert rule(".data-note--clamped[data-expanded] .data-note__text") =~ ~r/display:\s*block;/
    # "more" reads in the note's ink, not the link-button's accent.
    assert rule(".data-note > .data-note__more") =~ ~r/color:\s*inherit;/

    js = hook_source("NoteClamp")
    assert js =~ "text.scrollHeight > text.clientHeight + 1"
    assert js =~ ~s|setAttribute("aria-expanded"|
    assert js =~ ~s|setAttribute("data-expanded", "")|
    assert js =~ ~s|this.expanded ? "data-less" : "data-more"|
    assert js =~ ~s|document.addEventListener("toggle", this.onToggle, true)|
    assert js =~ ~s|this.resizeObserver.observe(this.el)|
    assert js =~ ~r/updated: function \(\) \{\s*this\.apply\(\);/
  end
end
