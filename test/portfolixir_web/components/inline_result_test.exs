defmodule PortfolixirWeb.Components.InlineResultTest do
  # `AppShell.inline_result/1` ({components.inline-result}) is rendered by
  # every page that answers an action in flow; these tests pin its markup,
  # the structure the stylesheet rules of
  # `test/invariants/css_shared_components_test.exs` select.
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias PortfolixirWeb.AppShell

  defp render_slot(assigns), do: render_component(&AppShell.inline_result/1, assigns)

  # The element children of one region (whitespace is not a child).
  defp region_children(html, region) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#slot-#{region} > *")
    |> Enum.count()
  end

  # User story (#1160, Sprint 21 γ8; board 08, "#1160"):
  # As the operator reading a page before any action,
  # I want an empty result slot to render nothing in its regions,
  # so that the stylesheet's `:has(> *)` takes no room for it at rest.
  #
  # Acceptance criteria:
  # - At rest both live regions exist (the announcement is never lost) and
  #   hold no element: whitespace only, which `:has(> *)` does not match.
  # - A note lands in the status region, a problem in the alert region, each
  #   as one element child.
  test "an empty slot's regions hold no element; a result is one child" do
    html = render_slot(%{id: "slot", result: nil})
    assert html =~ ~s(id="slot-status" role="status")
    assert html =~ ~s(id="slot-alert" role="alert")
    assert region_children(html, "status") == 0
    assert region_children(html, "alert") == 0

    note = render_slot(%{id: "slot", result: {:note, "Saved"}})
    assert region_children(note, "status") == 1
    assert region_children(note, "alert") == 0

    problem = render_slot(%{id: "slot", result: {:problem, "Refused"}})
    assert region_children(problem, "status") == 0
    assert region_children(problem, "alert") == 1
  end
end
