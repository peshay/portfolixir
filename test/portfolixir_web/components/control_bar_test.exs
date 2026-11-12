defmodule PortfolixirWeb.Components.ControlBarTest do
  # `ControlBar.bar/1`, the one bar of labelled controls (issue 1435,
  # Sprint 29 L1; DESIGN.md, amendment of 2026-11-08 "Labelled controls
  # start on one edge", and the anatomy of the control bar; board
  # `ux-design-2026-11-12-sprint29/06-control-bar`, inventory §1 and §2).
  # The markup is pinned here, the rules it selects in `app.css` below, and
  # where the boxes land in `test/browser/control_bar_test.exs`; the stacked
  # chart's bar, its first user, in `stacked_chart_bar_test.exs`.
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest

  alias PortfolixirWeb.ControlBar

  @css File.read!("priv/static/app.css")

  defp rule(selector) do
    case Regex.run(~r/(?:^|\n)\s*#{Regex.escape(selector)} \{([^}]*)\}/, @css) do
      [_, body] -> body
      nil -> flunk("no rule for #{selector}")
    end
  end

  # Every container query at `width`, joined: the fold's and the floor's
  # may share a width in two blocks.
  defp container_block(width) do
    case Regex.scan(~r/@container control-bar \(max-width: #{width}px\) \{(.*?)\n\}/s, @css) do
      [] -> flunk("no container query at #{width} px")
      blocks -> Enum.map_join(blocks, "\n", fn [_, body] -> body end)
    end
  end

  defp query(html, selector), do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)

  defp count(html, selector), do: html |> query(selector) |> Enum.count()

  # User story (issue 1435, inventory §2):
  # As the developer building a bar of labelled controls,
  # I want one component that takes each control with its label,
  # so that every bar lays its controls out by the same rule and none is
  # built as a wrapping row of label and control pairs again.
  #
  # Acceptance criteria:
  # - The bar is `div.control-bar` with its fold and its floor as classes
  #   (`control-bar--fold-760 control-bar--floor-330` by default), the
  #   caller's attributes passed through.
  # - Each group is `.control-bar__group`: its label `.control-bar__label`
  #   first, then the caller's control, one element.
  # - A label for a select or a field is `<label for>`; a segmented
  #   control's or a chip family's label is a `span` with the id the control
  #   names in its `aria-labelledby`.
  # - A group can be a form (its id and `phx-change`), so a select's change
  #   reaches the LiveView with the label inside the form.
  # - A group without a label keeps its control in the control column
  #   (`.control-bar__group--bare`), as the journal's checkbox will (board
  #   06 ①).
  # - The head (the stacked chart's breadcrumb) stands before the controls,
  #   outside them.
  test "a group is its label, then its control; a select's label is a label for it" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <ControlBar.bar data-role="probe-bar">
        <:head><nav data-role="probe-head">Path</nav></:head>
        <:group label="Level" label_id="probe-level-label">
          <div class="segmented-control" role="group" aria-labelledby="probe-level-label">
            <button type="button" class="segmented-control__option">One</button>
          </div>
        </:group>
        <:group label="Tree" for="probe-tree" form={[id: "probe-form", "phx-change": "pick"]}>
          <select id="probe-tree" name="tree"><option value="1">A</option></select>
        </:group>
        <:group>
          <label><input type="checkbox" name="all" /> All</label>
        </:group>
      </ControlBar.bar>
      """)

    assert count(
             html,
             "div.control-bar.control-bar--fold-760.control-bar--floor-330[data-role='probe-bar']"
           ) == 1

    assert count(html, ".control-bar > nav[data-role='probe-head'] + .control-bar__controls") ==
             1

    assert count(html, ".control-bar__controls > .control-bar__group") == 3

    assert count(
             html,
             "span.control-bar__group > span.control-bar__label#probe-level-label:first-child + div.segmented-control"
           ) == 1

    assert count(
             html,
             "form#probe-form.control-bar__group[phx-change='pick'] > label.control-bar__label[for='probe-tree']:first-child + select#probe-tree"
           ) == 1

    assert count(html, ".control-bar__group.control-bar__group--bare > label > input") == 1
    assert count(html, ".control-bar__group--bare .control-bar__label") == 0
    assert html |> query(".control-bar__label") |> LazyHTML.text() =~ "Level"
  end

  # User story (issue 1435, inventory §2 "When the bar folds"):
  # As the developer moving a bar onto the component,
  # I want to say at which width the bar becomes a label column and at
  # which its labels move above their controls,
  # so that a bar whose families never fit one line folds always, and one
  # whose full-width control cannot stand beside a label column takes the
  # floor.
  #
  # Acceptance criteria:
  # - `fold` is one of 560, 760, 960 or `:always`; `floor` one of 330, 560
  #   or `:always`; each becomes the class `control-bar--fold-<w>` /
  #   `control-bar--floor-<w>`.
  # - A width outside these lists is refused when the bar renders, so no bar
  #   carries a class without a rule.
  test "the fold and the floor are named widths, each a class" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <ControlBar.bar fold={:always} floor={560}>
        <:group label="Account" label_id="probe-account-label">
          <div role="group" aria-labelledby="probe-account-label">chips</div>
        </:group>
      </ControlBar.bar>
      """)

    assert count(html, "div.control-bar.control-bar--fold-always.control-bar--floor-560") == 1

    assert_raise ArgumentError, ~r/fold/, fn ->
      rendered_to_string(~H"""
      <ControlBar.bar fold={700}>
        <:group label="Account">x</:group>
      </ControlBar.bar>
      """)
    end
  end

  # User story (issue 1435; DESIGN.md "Labelled controls start on one
  # edge"):
  # As the operator on any page with a bar of labelled controls,
  # I want the bar to be one line while it fits, a label column when it
  # wraps (A) and every label above its control where that does not fit
  # (B),
  # so that controls under one another always start on one edge.
  #
  # Acceptance criteria:
  # - The bar is the container `control-bar` and, at rest, one wrapping line:
  #   each group an inline row of its label (600, 2 px to its right) and its
  #   control.
  # - A (the label column): a container query per fold width, and the
  #   always-folded bar without one, turn the controls into a two-column
  #   grid (`max-content` labels, controls from the second column's edge,
  #   10 px apart, the groups `display: contents`).
  # - B (labels above): a container query per floor width, and the
  #   always-floored bar, make it one column, 4 px between label and
  #   control, 6 px under each control; B comes after A, so where both
  #   match B wins.
  # - Every control starts at its column's start (`justify-self: start`),
  #   a select at its own width in A and B; a bare group's control stands in
  #   the control column.
  # - The stacked chart's `.stack-bar*` rules are gone: its bar is this
  #   component.
  test "app.css lays the bar out as one line, then a label column, then labels above" do
    assert rule(".control-bar") =~ ~r/container:\s*control-bar \/ inline-size;/
    assert rule(".control-bar__controls") =~ ~r/display:\s*var\(--control-bar-display, flex\);/
    assert rule(".control-bar__group") =~ ~r/display:\s*var\(--control-bar-group, inline-flex\);/

    assert rule(".control-bar__label") =~
             ~r/margin-right:\s*var\(--control-bar-label-margin, 2px\);/

    assert rule(".control-bar__group > :not(.control-bar__label)") =~ ~r/justify-self:\s*start;/

    assert rule(".control-bar__group > select") =~
             ~r/width:\s*var\(--control-bar-select-width, 100%\);/

    assert rule(".control-bar__group--bare > *") =~ ~r/grid-column:\s*-2 \/ -1;/

    column =
      ~r/--control-bar-display:\s*grid;.*--control-bar-columns:\s*max-content minmax\(0, 1fr\);.*--control-bar-group:\s*contents;/s

    above =
      ~r/--control-bar-display:\s*grid;.*--control-bar-columns:\s*minmax\(0, 1fr\);.*--control-bar-control-margin:\s*6px;/s

    for width <- [560, 760, 960] do
      assert container_block(width) =~ ".control-bar--fold-#{width} > .control-bar__controls"
    end

    assert rule(".control-bar--fold-always > .control-bar__controls") =~ column
    assert container_block(760) =~ column

    for width <- [330, 560] do
      assert container_block(width) =~ ".control-bar--floor-#{width} > .control-bar__controls"
    end

    assert rule(".control-bar--floor-always > .control-bar__controls") =~ above
    assert container_block(330) =~ above

    # B after A: the floor's rules come later in the file than the fold's.
    [{fold_at, _}] = Regex.run(~r/\.control-bar--fold-always > /, @css, return: :index)
    [{floor_at, _}] = Regex.run(~r/\.control-bar--floor-always > /, @css, return: :index)
    assert floor_at > fold_at

    refute @css =~ ~r/\.stack-bar/
  end
end
