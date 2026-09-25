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
  # - Esc closes the menu and returns the focus to the kebab that opened it —
  #   the phone row's own kebab too, not the hidden desktop one.
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
    # The phone rows open the menu from their own kebab while `data-trigger`
    # names the desktop one, hidden below 720 px (closing act, F24): the hook
    # remembers the element that had the focus when the menu opened and
    # returns to it while it is still on the page and visible.
    assert hook =~ "this.opener = document.activeElement"
    assert hook =~ ~r/opener\.isConnected && opener\.offsetParent !== null/
  end

  # User story (#870; WCAG 2.4.6, 4.1.2):
  # As an operator using a screen reader,
  # I want every row's kebab named for its row,
  # so that a list of buttons is not the same name dozens of times — and the
  # surfaces cannot drift apart again, because there is only one kebab.
  #
  # Acceptance criteria:
  # - No module in the web layer draws a kebab of its own: the
  #   `row-actions__kebab` markup lives only in `AppShell.row_kebab/1`, whose
  #   `row` is required and whose name is "Actions for <row>".
  # - The generic "Open actions menu" name is gone from the web layer.
  test "every row kebab is the shared trigger, named for its row" do
    shell = "lib/portfolixir_web/components/app_shell.ex"

    own_kebabs =
      "lib/portfolixir_web/**/*.ex"
      |> Path.wildcard()
      |> Enum.reject(&(&1 == shell))
      |> Enum.filter(&(File.read!(&1) =~ "row-actions__kebab"))

    assert own_kebabs == [], "kebabs drawn outside AppShell.row_kebab/1: #{inspect(own_kebabs)}"

    source = File.read!(shell)
    assert source =~ ~S|attr(:row, :string, required: true|
    assert source =~ ~S|aria-label={gettext("Actions for %{row}", row: @row)}|

    generic =
      "lib/portfolixir_web/**/*.ex"
      |> Path.wildcard()
      |> Enum.filter(&(File.read!(&1) =~ "Open actions menu"))

    assert generic == []
  end
end
