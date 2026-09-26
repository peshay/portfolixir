defmodule PortfolixirWeb.DesignConformanceCssTest do
  use ExUnit.Case, async: true

  @app_css "priv/static/app.css"

  # User story (#833, DESIGN.md → Components → data-table.cell; board
  # ux-design-2026-09-20/04-num-and-focus, "after"):
  # As a local portfolio maintainer reading any table in the app,
  # I want every numeric column right-aligned with tabular numerals,
  # so that I can compare figures down a column without the digits wandering.
  #
  # Acceptance criteria:
  # - One generic rule backs `class="num"` on a table cell: right-aligned and
  #   tabular numerals, whatever table it sits in.
  # - The header cell `th.num` wins over `.data-table thead th`'s
  #   `text-align: left`, so the header sits over its right-aligned figures.
  test "a numeric cell is right-aligned with tabular numerals in any table" do
    app_css = File.read!(@app_css)

    generic = generic_num_rule(app_css)

    assert generic =~ "text-align: right"
    assert generic =~ "font-variant-numeric: tabular-nums"

    # Several tables reset their cells to `text-align: left` at the same
    # specificity as `th.num` (`.perf-data-table th`, `.drift-table th`, …);
    # the generic rule must come after every one of them, or source order
    # hands the tie back to the left-aligned reset.
    {generic_at, _} = :binary.match(app_css, String.trim_leading(generic))

    left_aligned_cell_resets =
      ~r/\n([^{}\n]*\b(?:th|td)(?:,\s*[^{}]*)?) \{[^}]*text-align: left/s
      |> Regex.scan(app_css, return: :index)
      |> Enum.map(fn [{at, _} | _] -> at end)

    assert left_aligned_cell_resets != []
    assert Enum.all?(left_aligned_cell_resets, &(&1 < generic_at))
  end

  # User story (#869, numeric half; DESIGN.md → Numeric inputs; board
  # ux-design-2026-09-24/05-numeric-inputs, "after"):
  # As the operator typing figures into a form,
  # I want a decimal field to stand right-aligned in tabular digits like the
  # column it will end up in,
  # so that an amount and a rate typed one under the other end on one edge.
  #
  # Acceptance criteria:
  # - `input.num` joins the generic `.num` rule, which sits last in the file,
  #   so it outranks the bare `input` rule by specificity and any scoped
  #   `… input` rule of equal specificity by source order.
  # - No rule after it sets an input's `text-align`.
  test "a decimal input is right-aligned with tabular numerals" do
    app_css = File.read!(@app_css)
    generic = generic_num_rule(app_css)

    assert generic =~ ~r/\ninput\.num \{/
    {generic_at, generic_size} = :binary.match(app_css, String.trim_leading(generic))
    rule_end = generic_at + generic_size
    after_rule = binary_part(app_css, rule_end, byte_size(app_css) - rule_end)
    refute after_rule =~ ~r/\binput[^{}]*\{[^}]*text-align/
  end

  defp generic_num_rule(app_css) do
    [generic] =
      Regex.run(
        ~r/\nth\.num,\s*td\.num,\s*\.data-table thead th\.num(?:,\s*input\.num)? \{[^}]*\}/s,
        app_css
      )

    generic
  end

  # User story (#834, DESIGN.md → Do's and Don'ts, EXPERIENCE.md → the
  # coarse-pointer table; board ux-design-2026-09-20/04-num-and-focus, "after"):
  # As a local portfolio maintainer working a table by keyboard or on a phone,
  # I want the row kebab and its menu items to show a real focus ring and the
  # kebab to be a thumb-sized target,
  # so that I can see where focus is and hit the row menu without zooming.
  #
  # Acceptance criteria:
  # - `.row-actions__kebab:focus-visible` and `.row-context-menu__item:focus-visible`
  #   carry the 2px accent outline with a 2px offset, as
  #   `.filter-sheet-toggle:focus-visible` does.
  # - No rule on either class substitutes `outline: none` for the ring.
  # - Under `@media (pointer: coarse)` the kebab is at least 44 x 44 px.
  test "the row kebab and its menu items carry the shared focus ring and a coarse floor" do
    app_css = File.read!(@app_css)

    for class <- ["row-actions__kebab", "row-context-menu__item"] do
      [ring] = Regex.run(~r/\n\.#{class}:focus-visible \{[^}]*\}/s, app_css)
      assert ring =~ "outline: 2px solid var(--color-accent)"
      assert ring =~ "outline-offset: 2px"

      for [rule] <- Regex.scan(~r/\.#{class}[^{}]*\{[^}]*\}/s, app_css) do
        refute rule =~ "outline: none", "#{class} still substitutes outline: none:\n#{rule}"
      end
    end

    assert app_css =~
             ~r/@media \(pointer: coarse\) \{\s*\.row-actions__kebab \{[^}]*min-width: 44px;[^}]*min-height: 44px/s
  end

  # User story (#842, board ux-design-2026-09-20/02-bucket-overflow-chip, E2-A):
  # As a local portfolio maintainer expanding a bucket cell by keyboard or thumb,
  # I want the "+N" overflow control to show focus and be thumb-sized,
  # so that the disclosure is as reachable as the chips it reveals.
  #
  # Acceptance criteria:
  # - `.bucket-chip--overflow:focus-visible` carries the 2px accent outline.
  # - Under `@media (pointer: coarse)` it takes the 44px floor.
  test "the bucket overflow disclosure carries the focus ring and the coarse floor" do
    app_css = File.read!(@app_css)

    [ring] = Regex.run(~r/\n\.bucket-chip--overflow:focus-visible \{[^}]*\}/s, app_css)
    assert ring =~ "outline: 2px solid var(--color-accent)"
    assert ring =~ "outline-offset: 2px"

    assert app_css =~
             ~r/@media \(pointer: coarse\) \{[^@]*\.bucket-chip--overflow \{\s*min-height: 44px/s
  end

  # Acceptance criteria (#842, closing-act UAT finding — the chip was
  # unreachable at 390 and 1200 px):
  # - The accounts table fits its (non-scrolling) wrapper instead of taking
  #   the scrolling tables' `min-width: max-content`, so the chip group can
  #   wrap and the overflow chip stays on screen.
  test "the accounts table fits its wrapper so the bucket chips wrap" do
    app_css = File.read!(@app_css)

    [rule] =
      Regex.run(~r/\n\.data-table-wrapper > \.accounts-table \{[^}]*\}/s, app_css)

    assert rule =~ "min-width: 0"
    assert rule =~ "width: 100%"
  end

  # User story (#837, board ux-design-2026-09-20/05-detail-tablist, E4-A):
  # As a local portfolio maintainer walking the detail tab row by keyboard,
  # I want the focused tab to show the accent ring,
  # so that the arrow keys visibly move something.
  #
  # Acceptance criteria:
  # - `.detail-pane-tab:focus-visible` carries the 2px accent outline, inset
  #   because the scrolling row clips anything drawn outside a tab.
  test "the detail pane tab carries the inset accent focus ring" do
    app_css = File.read!(@app_css)

    [ring] = Regex.run(~r/\n\.detail-pane-tab:focus-visible \{[^}]*\}/s, app_css)
    assert ring =~ "outline: 2px solid var(--color-accent)"
    assert ring =~ ~r/outline-offset: -\d+px/
  end

  # User story (#854, DESIGN.md → Data as table — one disclosure; board
  # ux-design-2026-09-23/04-tab-row-and-disclosure, "after"):
  # As a local portfolio maintainer opening a table behind a disclosure,
  # I want exactly one marker on the summary — the chevron that turns when it
  # opens —
  # so that the row does not read "▸ ›" with two arrows pointing at nothing.
  #
  # Acceptance criteria:
  # - No `.disclosure-summary::before` rule draws a triangle in app.css.
  # - Every `<summary class="disclosure-summary">` in the templates renders the
  #   chevron icon, so dropping the triangle leaves none of them without a
  #   marker. The one exception is a picker trigger whose own icon names it
  #   (the Wealth holdings "Columns" picker, converted to `.popover` by #850).
  test "a disclosure summary carries exactly one marker, the chevron" do
    app_css = File.read!(@app_css)
    refute app_css =~ ~r/\.disclosure-summary::before\s*\{/

    summaries =
      for path <- Path.wildcard("lib/portfolixir_web/**/*.ex"),
          source = File.read!(path),
          [block] <-
            Regex.scan(
              ~r/<summary class="disclosure-summary">.*?<\/summary>/s,
              source
            ),
          not (block =~ "gettext(\"Columns\")"),
          do: {path, block}

    assert summaries != []

    missing = for {path, block} <- summaries, not (block =~ "disclosure-chevron"), do: path
    assert missing == [], "disclosure summaries without the chevron: #{inspect(missing)}"
  end

  # The last rule of `selector` in app.css (its block's text).
  defp rule(app_css, selector) do
    ~r/\n#{Regex.escape(selector)} \{([^}]*)\}/
    |> Regex.scan(app_css, capture: :all_but_first)
    |> List.last()
    |> case do
      [body] -> body
      nil -> flunk("no rule for #{selector}")
    end
  end

  # User story (the closing act, UAT-1 / DC-1; board
  # ux-design-2026-09-24/02-merge-preview, step 1; DESIGN G2-B, G3-A):
  # As the operator choosing where a merge's history goes,
  # I want a selectable target drawn in the text colour and the ones that
  # cannot take it muted,
  # so that the list tells the two apart by more than a background tint.
  #
  # Acceptance criteria:
  # - `.merge-target__name` and `.merge-target__balance` name the text colour
  #   and weight 400 themselves — a target is a <label> of <span>s, and the
  #   form-label rule `label span` (muted, 680) would otherwise apply.
  # - The meta line (`small`) is muted at 400; the reason line is 400.
  # - The disabled row keeps its muted name and balance.
  test "a selectable merge target is drawn in the text colour, a disabled one muted" do
    app_css = File.read!(@app_css)

    assert rule(app_css, "label span") =~ "color: var(--color-text-muted)"

    for selector <- [".merge-target__name", ".merge-target__balance"] do
      body = rule(app_css, selector)
      assert body =~ "color: var(--color-text)", selector
      assert body =~ "font-weight: 400", selector
    end

    small = rule(app_css, ".merge-target__name small")
    assert small =~ "color: var(--color-text-muted)"
    assert small =~ "font-weight: 400"
    assert rule(app_css, ".merge-target__why") =~ "font-weight: 400"

    assert app_css =~
             ~r/\.merge-target\.is-off \.merge-target__name b,\s*\.merge-target\.is-off \.merge-target__balance \{[^}]*color: var\(--color-text-muted\)/
  end

  # Acceptance criteria (the closing act, DC-7): the merge figures outside a
  # table — a target's balance, the sum's terms and its alternative line,
  # the two-line figures under 720 px — use tabular numerals, so decimals
  # line up across rows (DESIGN: money uses tabular-nums).
  test "the merge figures use tabular numerals" do
    app_css = File.read!(@app_css)

    for selector <- [
          ".merge-target__balance",
          ".merge-identity__term b",
          ".merge-identity__alt",
          ".merge-lines__figure"
        ] do
      assert rule(app_css, selector) =~ "font-variant-numeric: tabular-nums", selector
    end
  end

  # Acceptance criteria (the closing act, DC-11): a merge target or option
  # card whose radio has keyboard focus carries the shared 2 px accent ring
  # with a 2 px offset, as the kebab and the rule names do.
  test "a merge target or option card shows keyboard focus with the shared ring" do
    app_css = File.read!(@app_css)

    [ring] =
      Regex.run(
        ~r/\n\.merge-target:has\(input:focus-visible\),\s*\.merge-option:has\(input:focus-visible\) \{[^}]*\}/s,
        app_css
      )

    assert ring =~ "outline: 2px solid var(--color-accent)"
    assert ring =~ "outline-offset: 2px"
  end

  # Acceptance criteria (the closing act, UAT-3; board 13-l5a-merged-from):
  # the "merged from" and "former" lines under an account's name wrap inside
  # their cell — the accounts table sets nowrap on its cells, so without
  # this a long source name ran under the row's kebab at 390 px.
  test "an account's merged-from and former lines wrap inside their cell" do
    app_css = File.read!(@app_css)
    body = rule(app_css, ".account-sub--former,\n.account-sub--merged")

    assert body =~ "white-space: normal"
    assert body =~ "max-width: 100%"
    assert body =~ "overflow-wrap: anywhere"
  end

  # Acceptance criteria (the closing act, UAT-2; board 02 at 390 px): where
  # the sum becomes a list under 720 px, its + and = stay as the labels'
  # prefixes ("+ Tagesgeld", "= Tagesgeld danach"); wider, the operators
  # stand between the terms and the prefixes are hidden.
  test "the merge sum keeps its operators at 390 px" do
    app_css = File.read!(@app_css)

    assert rule(app_css, ".merge-identity__sign") =~ "display: none"

    assert app_css =~
             ~r/@media \(max-width: 720px\) \{[^@]*\.merge-identity__op \{\s*display: none;\s*\}\s*\.merge-identity__sign \{\s*display: inline;/s
  end
end
