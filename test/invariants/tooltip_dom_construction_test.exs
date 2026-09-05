defmodule Portfolixir.Invariants.TooltipDomConstructionTest do
  # Issue #770: the inline client builds every tooltip through the DOM API
  # (createElement / textContent), never through innerHTML from concatenated
  # strings — the sink an unforeseen field would turn into markup injection.
  use ExUnit.Case, async: true

  @layout "lib/portfolixir_web/layout_view.ex"

  # User story:
  # As the operator,
  # I want no server-sent value assembled into HTML by string concatenation in the browser,
  # so that a field added tomorrow cannot become an injection today.
  #
  # Acceptance criteria:
  # - The inline client scripts contain no innerHTML assignment.
  test "the inline client never assigns innerHTML" do
    source = File.read!(@layout)

    refute source =~ ~r/\.innerHTML\s*=/,
           "layout_view.ex assigns innerHTML; build tooltips with createElement/textContent"
  end
end
