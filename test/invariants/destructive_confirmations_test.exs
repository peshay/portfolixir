defmodule Portfolixir.Invariants.DestructiveConfirmationsTest do
  # Issue #765: every destructive click in the UI carries a confirmation, the
  # way the seven that already had one do. Pinned at the source so a new
  # destructive control without one fails the build.
  use ExUnit.Case, async: true

  @sites [
    {"lib/portfolixir_web/live/securities/row_context_menu.ex", ~s(phx-value-action="delete")},
    {"lib/portfolixir_web/live/tax_live.ex", ~s(phx-click="delete_allowance_order")},
    {"lib/portfolixir_web/live/securities/logo_override_dialog.ex",
     ~s(phx-click="remove_logo_override")},
    {"lib/portfolixir_web/live/classifications_live.ex", "data-unassign-selected"}
  ]

  # User story:
  # As the operator,
  # I want a delete, a bulk unassign or a logo removal to ask once before it happens,
  # so that a mis-click on an unauthenticated screen cannot remove a record silently.
  #
  # Acceptance criteria:
  # - Each of the four formerly bare controls carries data-confirm on the same element.
  test "the four formerly bare destructive controls carry data-confirm" do
    for {file, marker} <- @sites do
      source = File.read!(file)
      assert source =~ marker, "#{file} no longer contains #{marker}"

      element =
        source
        |> String.split("<button")
        |> Enum.find(&String.contains?(&1, marker))

      assert element, "#{file}: #{marker} is not on a <button>"
      assert element =~ "data-confirm=", "#{file}: #{marker} has no data-confirm"
    end
  end

  # User story:
  # As the operator,
  # I want data-confirm to be honoured on a phx-click, not just present,
  # so that the attribute is a prompt and not a decoration.
  #
  # Acceptance criteria:
  # - The page loads no phoenix_html script, so the root layout's own script
  #   carries one capture-phase click listener that asks before any
  #   [data-confirm] and cancels the click on "cancel".
  # - No hook keeps a second prompt of its own for the same control.
  test "the root layout honours data-confirm ahead of LiveView" do
    layout = File.read!("lib/portfolixir_web/layout_view.ex")
    refute layout =~ "phoenix_html.js"

    [_, listener] = String.split(layout, ~s|closest("[data-confirm]")|, parts: 2)
    assert listener =~ "window.confirm(target.getAttribute(\"data-confirm\"))"
    assert listener =~ "event.preventDefault();"
    assert listener =~ "event.stopImmediatePropagation();"
    assert String.slice(listener, 0, 400) =~ "}, true);"

    # The classifications hook no longer prompts by itself.
    assert length(String.split(layout, "window.confirm(")) == 2
  end
end
