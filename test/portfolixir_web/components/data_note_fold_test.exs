defmodule PortfolixirWeb.Components.DataNoteFoldTest do
  # The folded notes of board `ux-design-2026-11-01-sprint22/01-i1` ④ (I1,
  # #1351): two or more attention or note items in one block fold into one
  # line with their counts, at the highest folded severity. Problems and
  # notes that name rows left out of a total are never passed to it (Q1,
  # correction 1); the page decides which notes fold.
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest

  alias PortfolixirWeb.AppShell

  @css File.read!("priv/static/app.css")

  defp rule(selector) do
    case Regex.run(~r/(?:^|\n)#{Regex.escape(selector)} \{([^}]*)\}/, @css) do
      [_, body] -> body
      nil -> flunk("no rule for #{selector}")
    end
  end

  defp query(html, selector), do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)

  defp squish(nodes),
    do: nodes |> LazyHTML.text() |> String.replace(~r/\s+/u, " ") |> String.trim()

  defp fold(attention, note) do
    assigns = %{attention: attention, note: note}

    rendered_to_string(~H"""
    <AppShell.data_note_fold id="dq-folded" attention={@attention} note={@note}>
      <AppShell.data_note :if={@note > 0} severity={:note} data-role="n1">A note.</AppShell.data_note>
      <AppShell.data_note :for={i <- 1..@attention//1} severity={:attention} data-role={"a#{i}"}>
        An attention.
      </AppShell.data_note>
    </AppShell.data_note_fold>
    """)
  end

  # User story (#1351, board 01 ④):
  # As the operator reading a block of data notes,
  # I want the notes that only qualify a figure folded into one line with
  # their counts,
  # so that the problems and the excluded rows lead and the rest is one tap
  # away.
  #
  # Acceptance criteria:
  # - Two or more items fold: one `details.data-note-group` at the highest
  #   folded severity (`--attention` when any attention item is in it), with
  #   the DisclosureState hook so a patch keeps it open; its summary reads
  #   "1 Attention · 1 Note — Show details", each count with its glyph
  #   (aria-hidden) and word; the notes sit in `.data-note-group__body`.
  # - Notes only: the group is `--note` and the count reads "2 Notes".
  # - One item does not fold: the note renders on its own.
  # - The stylesheet draws the fold line in the attention note's tokens.
  test "two or more notes fold into one line with their counts" do
    html = fold(1, 1)

    group =
      query(
        html,
        "details#dq-folded.data-note-group.data-note-group--attention[data-role='folded-notes'][phx-hook='DisclosureState']"
      )

    assert Enum.count(group) == 1
    assert squish(LazyHTML.query(group, "summary")) == "1 Attention · 1 Note — Show details"

    assert Enum.count(
             LazyHTML.query(
               group,
               "summary .data-note-group__count--attention [aria-hidden='true'] svg"
             )
           ) == 1

    assert Enum.count(LazyHTML.query(group, ".data-note-group__body > .data-note")) == 2

    assigns = %{}

    two_notes =
      rendered_to_string(~H"""
      <AppShell.data_note_fold id="f" note={2}>
        <AppShell.data_note severity={:note}>One.</AppShell.data_note>
        <AppShell.data_note severity={:note}>Two.</AppShell.data_note>
      </AppShell.data_note_fold>
      """)

    note_group = query(two_notes, "details.data-note-group.data-note-group--note")
    assert squish(LazyHTML.query(note_group, "summary")) == "2 Notes — Show details"

    single = fold(1, 0)
    assert Enum.empty?(query(single, "details"))
    assert Enum.count(query(single, ".data-note--attention")) == 1

    assert rule(".data-note-group--attention") =~ ~r/background:\s*var\(--color-warning-soft\);/
    assert rule(".data-note-group > summary") =~ ~r/list-style:\s*none;/
  end

  # User story (#1351 closing act, S3):
  # As the operator who opened a fold of notes,
  # I want its line to read "— Hide details" while it is open,
  # so that the line says what a tap on it does now.
  #
  # Acceptance criteria:
  # - The toggle carries the open label for the stylesheet,
  #   `data-hide="Hide details"` (German „Details ausblenden“), beside its
  #   "Show details" span; no script is needed.
  # - The stylesheet hides "Show details" under `[open]` and writes the
  #   open label in its place.
  test "an open fold reads Hide details" do
    html = fold(1, 1)

    toggle = query(html, "summary .data-note-group__toggle[data-hide='Hide details']")
    assert Enum.count(toggle) == 1
    assert squish(LazyHTML.query(toggle, ".data-note-group__show")) == "Show details"

    assert rule(".data-note-group[open] .data-note-group__show") =~ ~r/display:\s*none;/

    assert rule(".data-note-group[open] .data-note-group__toggle::after") =~
             ~r/content:\s*attr\(data-hide\);/

    Gettext.with_locale(PortfolixirWeb.Gettext, "de", fn ->
      de = fold(1, 1)

      assert Enum.count(
               query(de, "summary .data-note-group__toggle[data-hide='Details ausblenden']")
             ) == 1
    end)
  end
end
