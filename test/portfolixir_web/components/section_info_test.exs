defmodule PortfolixirWeb.Components.SectionInfoTest do
  # `AppShell.section_info/1`, the section's ⓘ of board
  # `ux-design-2026-11-01-sprint22/01-i1` ① (I1, #1351): a section's method
  # sentences leave the page and sit in one ⓘ beside its heading.
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

  # User story (#1351, board 01 ①):
  # As the operator reading a section,
  # I want its method sentences behind one ⓘ beside its heading,
  # so that the section reads as its figures and its basis, and the method
  # is one tap away.
  #
  # Acceptance criteria:
  # - The ⓘ is the house `details.metric-tooltip`, inline, with the section
  #   modifier: a summary "ⓘ" named "About this section" and one
  #   `p[role="tooltip"]` holding one method sentence per line (`<br>`
  #   between lines, none before the first).
  # - `.section-title` keeps the heading a pure heading beside its ⓘ (a
  #   flex row); the section's panel is 26 rem wide, still 1 rem inside a
  #   phone screen.
  test "a section's ⓘ holds its method sentences, one per line" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <AppShell.section_info>
        <:line>Contribution = end value − start value</:line>
        <:line>start value: the close of the day before the period</:line>
      </AppShell.section_info>
      """)

    tip =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(
        "details.metric-tooltip.metric-tooltip--inline.metric-tooltip--section[data-role='section-info']"
      )

    assert Enum.count(tip) == 1

    assert tip |> LazyHTML.query("summary[aria-label='About this section']") |> LazyHTML.text() ==
             "ⓘ"

    panel = LazyHTML.query(tip, "p[role='tooltip']")
    assert Enum.count(LazyHTML.query(panel, "br")) == 1

    # The <br> is the line break; text() joins the lines without one.
    assert panel |> LazyHTML.text() |> String.replace(~r/\s+/u, " ") |> String.trim() ==
             "Contribution = end value − start valuestart value: the close of the day before the period"

    assert rule(".section-title") =~ ~r/display:\s*flex;/
    assert rule(".metric-tooltip--section p") =~ ~r/width:\s*26rem;/
    assert rule(".metric-tooltip--section p") =~ ~r/max-width:\s*calc\(100vw - 2rem\);/
  end
end
