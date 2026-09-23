defmodule Portfolixir.Invariants.RowMenuKeyboardTest do
  use ExUnit.Case, async: true

  # User story (#858, board 05 of the 2026-09-23 pass):
  # As the operator working a list by keyboard,
  # I want a row menu opened with Enter to take the focus and answer the
  # arrow keys,
  # so that its actions are reachable without a mouse — the focus ring on
  # the items has been correct since #834, and nobody could reach it.
  #
  # Acceptance criteria (WAI-ARIA menu pattern, DESIGN.md → Do's and Don'ts):
  # - Opening moves the focus to the first enabled item.
  # - ↑/↓ move between the enabled items and wrap; Home/End jump.
  # - Esc closes the menu and returns the focus to the kebab that opened it.
  # - Tab closes the menu onto the kebab.
  # - The behaviour lives in the one hook every row menu mounts, so
  #   /portfolios, /securities, /transactions and /buckets cannot diverge:
  #   no `role="menu"` in the web layer lacks it.
  test "every row menu mounts the shared hook and names the kebab that opened it" do
    menus =
      "lib/portfolixir_web/**/*.ex"
      |> Path.wildcard()
      |> Enum.flat_map(fn path ->
        ~r/<div\s[^>]*role="menu"[^>]*>/s
        |> Regex.scan(File.read!(path))
        |> Enum.map(fn [tag] -> {path, tag} end)
      end)

    refute Enum.empty?(menus)

    for {path, tag} <- menus do
      assert tag =~ ~s(phx-hook="PositionedMenu"), "#{path}: a row menu without the shared hook"
      assert tag =~ "data-trigger=", "#{path}: a row menu that does not name its kebab"
    end
  end

  test "the shared menu hook carries the keyboard pattern" do
    hook =
      "lib/portfolixir_web/layout_view.ex"
      |> File.read!()
      |> String.split("Hooks.PositionedMenu")
      |> Enum.at(1)
      |> String.split("Hooks.")
      |> hd()

    for key <- ~w(ArrowDown ArrowUp Home End Tab) do
      assert hook =~ ~s("#{key}"), "the row menu hook does not handle #{key}"
    end

    # Opening focuses the first enabled item.
    assert hook =~ ~s{[role="menuitem"]:not([disabled])}
    assert hook =~ "focus()"
    # Tab closes through the same event Escape and click-away send, onto the
    # kebab rather than past the whole list the menu is rendered after.
    assert hook =~ ~s{pushEvent("close_row_menu"}
    # Closing hands the focus back to the kebab.
    assert hook =~ "dataset.trigger"
    assert hook =~ "focusTrigger()"
    assert hook =~ "destroyed"
  end
end
