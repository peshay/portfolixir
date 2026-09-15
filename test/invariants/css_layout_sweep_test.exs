defmodule Portfolixir.Invariants.CssLayoutSweepTest do
  use ExUnit.Case, async: true

  @css File.read!("priv/static/app.css")

  # User story (#790, the review's D8–D10 and the two lines after its table;
  # EXPERIENCE.md → Amendment 2026-09-12 → App shell; DESIGN.md → D6):
  # As a local portfolio maintainer,
  # I want the import button centred under its sentence, every control row
  # and section with a phone gutter of at least 16 px, the tab row with its
  # right-edge fade, and a labelled ⓘ that shows its whole label,
  # so that the layout reads as one composition.
  test "the import button is centred in the drop zone" do
    assert block(".import-drop-zone > .button-primary") =~ ~r/justify-self:\s*center/
  end

  test "sections and control rows keep a side gutter of at least 16 px" do
    assert block(".workspace-section") =~ ~r/padding:[^;]*clamp\(16px,/
    assert block(".workspace-section--controls") =~ ~r/padding-block:\s*0/
  end

  test "the area tab row carries a 40 px one-sided right-edge fade" do
    assert block(".area-tabs") =~
             ~r/mask-image:\s*linear-gradient\(to right, black calc\(100% - 40px\)/
  end

  test "a labelled tooltip summary grows with its label" do
    assert block(".metric-tooltip--labelled summary") =~ ~r/width:\s*auto/
  end

  defp block(selector) do
    case Regex.run(~r/\n#{Regex.escape(selector)} \{([^}]*)\}/, @css) do
      [_, body] -> body
      nil -> flunk("no top-level rule for #{selector}")
    end
  end
end
