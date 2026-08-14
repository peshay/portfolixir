defmodule PortfolixirWeb.FormsAlignmentTest do
  use ExUnit.Case, async: true

  # User story (#412, DESIGN.md → Components → forms and inputs / UX-DR14):
  # As a local portfolio maintainer entering data anywhere in the app,
  # I want every entry surface to share one control height, one label voice
  # and spacing from the 4px scale,
  # so that forms look intentional and aligned instead of each carrying its
  # own heights and ad-hoc gaps.
  #
  # Acceptance criteria:
  # - Inputs, selects, textareas and buttons share the 34px control height,
  #   so a flex form row aligns on one bottom edge.
  # - The form layout primitives (.form-grid, label, .inline-form) space
  #   themselves with 4px-scale tokens, not ad-hoc px/rem values.
  # - The .mono identifier treatment stays backed by a real rule.
  test "form primitives share the control height and the spacing scale" do
    app_css = File.read!("priv/static/app.css")

    # One control height across every entry control (the alignment anchor).
    assert app_css =~ ~r/input,\s*select,\s*textarea \{[^}]*min-height: 34px/s
    assert app_css =~ ~r/\nbutton \{[^}]*min-height: 34px/s

    # Layout primitives on the 4px scale (UX-DR14).
    assert app_css =~ ~r/\.form-grid \{[^}]*gap: var\(--space-/s
    assert app_css =~ ~r/\nlabel \{[^}]*gap: var\(--space-/s
    assert app_css =~ ~r/\.inline-form \{[^}]*gap: var\(--space-/s

    # No dead identifier class: .mono is a real monospace rule (issue 412).
    assert app_css =~ ~r/\.mono \{[^}]*font-family: var\(--font-mono\)/s
  end
end
