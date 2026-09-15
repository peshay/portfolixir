defmodule Portfolixir.Invariants.CssTopbarTitleTest do
  use ExUnit.Case, async: true

  @css File.read!("priv/static/app.css")

  # User story (#784, DESIGN.md → Amendment 2026-09-12 → Top bar title):
  # As the operator reading the page title on a 1× display,
  # I want "Übersicht" to render with its dots,
  # so that the top bar names the page and not a lookalike of it.
  #
  # Acceptance criteria:
  # - `.topbar-page h1` has a line box that clears a capital umlaut
  #   (line-height 1.3) and no `overflow: hidden` of its own.
  # - The ellipsis clip lives on the `.topbar-page` container as
  #   `overflow-x: clip`, so a long title still truncates on the phone.
  test "the title's line box clears its diacritics and the clip sits on the container" do
    heading = block(".topbar-page h1")
    assert heading =~ ~r/line-height:\s*1\.3\s*;/
    refute heading =~ ~r/overflow:\s*hidden/

    container = block(".topbar-page")
    assert container =~ ~r/overflow-x:\s*clip\s*;/
  end

  # The top-level rule for `selector` (the phone override is indented and
  # therefore not matched).
  defp block(selector) do
    case Regex.run(~r/\n#{Regex.escape(selector)} \{([^}]*)\}/, @css) do
      [_, body] -> body
      nil -> flunk("no top-level rule for #{selector}")
    end
  end
end
