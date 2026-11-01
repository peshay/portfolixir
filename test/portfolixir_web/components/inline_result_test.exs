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

  # User story (#1166, Sprint 21 γ8; board 08, N13 = A):
  # As the operator dismissing an action's answer with the keyboard,
  # I want the focus to go back to the control that produced it, else to the
  # section's heading,
  # so that the next Tab continues where I was, not at the top of the page.
  #
  # Acceptance criteria:
  # - The slot is served by the `InlineResult` hook and carries its targets:
  #   `data-focus-return` (a trigger the page names, optional) and
  #   `data-focus-fallback` (the section's heading, else the toolbar's first
  #   control); a slot that names neither carries neither attribute.
  # - The dismiss keeps its accessible name ("Dismiss") and is the one
  #   control the hook answers (`data-role="result-dismiss"`).
  test "the slot carries the dismiss's focus targets for its hook" do
    html =
      render_slot(%{
        id: "slot",
        result: {:note, "Saved"},
        focus_return: "#save-button",
        focus_fallback: "#section-heading"
      })

    slot = html |> LazyHTML.from_fragment() |> LazyHTML.query("#slot")
    assert LazyHTML.attribute(slot, "phx-hook") == ["InlineResult"]
    assert LazyHTML.attribute(slot, "data-focus-return") == ["#save-button"]
    assert LazyHTML.attribute(slot, "data-focus-fallback") == ["#section-heading"]

    dismiss =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#slot-status button[data-role='result-dismiss']")

    assert LazyHTML.attribute(dismiss, "aria-label") == ["Dismiss"]
    assert LazyHTML.attribute(dismiss, "type") == ["button"]

    bare = render_slot(%{id: "slot", result: nil})
    refute bare =~ "data-focus-return"
    refute bare =~ "data-focus-fallback"
    assert bare =~ ~s(phx-hook="InlineResult")
  end

  # Acceptance criteria (the hook, `Hooks.InlineResult` in the layout):
  # - Only the dismiss moves the focus, and it moves it on the click, before
  #   the server removes the note and the focused button with it.
  # - The target is the first on the page and visible of: the page's named
  #   return, the control that had the focus when the result arrived (or the
  #   control last activated, when the focus sat on the slot or <body>); else
  #   the fallback. Never <body> (WCAG 2.4.3).
  test "the InlineResult hook gives the focus back on a dismiss" do
    hook =
      "lib/portfolixir_web/layout_view.ex"
      |> File.read!()
      |> String.split("Hooks.InlineResult = {")
      |> Enum.at(1, "")
      |> String.split("\n            };\n")
      |> hd()

    assert hook =~ ~s{getAttribute("data-focus-return")}
    assert hook =~ ~s{getAttribute("data-focus-fallback")}
    assert hook =~ ~s{[data-role='result-dismiss']}
    assert hook =~ "document.activeElement"
    assert hook =~ "getClientRects().length"
    assert hook =~ "isConnected"
    assert hook =~ ".focus("
  end

  # Acceptance criteria (the review of γ8, S1: a result that replaces another):
  # - A result that replaces another — a second role change on Accounts
  #   answering the first — names its own trigger, not the first one's: the
  #   hook notes the trigger whenever the result on show differs from the one
  #   before (`noteNeeded(previous, current)`, over a snapshot of the slot's
  #   text), not only when the slot goes from empty to a result.
  # - A busy line or an empty slot is no result (`snapshot()` is null), so a
  #   result arriving after its busy line is noted too.
  # - ExUnit cannot drive the hook; the closing act's browser pass checks the
  #   replacement on Accounts (two role changes, Enter on the ×).
  test "the InlineResult hook re-notes the trigger when a result replaces another" do
    hook =
      "lib/portfolixir_web/layout_view.ex"
      |> File.read!()
      |> String.split("Hooks.InlineResult = {")
      |> Enum.at(1, "")
      |> String.split("\n            };\n")
      |> hd()

    assert hook =~ "if (this.noteNeeded(this.shown, shown)) this.noteTrigger();"
    assert hook =~ "return current !== null && current !== previous;"
    assert hook =~ ~s{if (!this.el.querySelector("[data-role='result-dismiss']")) return null;}
    refute hook =~ "shown && !this.shown"
  end

  # Acceptance criteria (the γ closing act, G1: an answer with the same text):
  # - A second answer with the same text as the one on show — every role
  #   change on Accounts answers "Cash account updated" — leaves the slot's
  #   markup byte-identical, so LiveView sends no patch and `updated` never
  #   runs. The hook therefore names the trigger on the activation itself:
  #   a control activated outside the slot while a result is on show is
  #   answered by that slot (a replacement or a clear), so it becomes the
  #   trigger at once (`answersShown(control)`); the sequence change A,
  #   answer, change B, dismiss gives the focus to B, not A.
  # - An activation inside an open dialog does not rename the trigger: the
  #   dialog's opener, activated before, stays the trigger, since the
  #   dialog's own controls leave the page with it.
  test "the InlineResult hook names the trigger on an activation a shown result answers" do
    hook =
      "lib/portfolixir_web/layout_view.ex"
      |> File.read!()
      |> String.split("Hooks.InlineResult = {")
      |> Enum.at(1, "")
      |> String.split("\n            };\n")
      |> hd()

    assert hook =~ "if (self.answersShown(control)) self.trigger = control;"
    assert hook =~ "answersShown: function (control) {"
    assert hook =~ ~s{return this.shown !== null && !control.closest("dialog, [role='dialog']");}
  end

  # Acceptance criteria (the γ closing act's re-check, board 08 / #1166: an
  # answer from a row menu):
  # - "ISIN kopieren" from one row's kebab, then from another's, answers with
  #   the same text twice, so the second menu item is the trigger at its
  #   click (G1 above). The item leaves the page with its menu, so it is not
  #   usable at the dismiss, and the focus fell through to the page's
  #   fallback, the search field, rather than to the second row's kebab,
  #   which held the focus after the menu closed.
  # - A control inside a row menu (`[role='menu'][data-trigger]`, the
  #   PositionedMenu hook's markup) is therefore anchored to the menu's
  #   opener: the hook records the element the menu's `data-trigger` names,
  #   on the activation and as the last action alike, so the dismiss gives
  #   the focus to the kebab that opened the menu.
  # - ExUnit cannot drive the hook; the re-check's browser pass is the
  #   sequence kebab 3, "ISIN kopieren", kebab 12, "ISIN kopieren", Enter on
  #   the ×, expecting kebab 12.
  test "the InlineResult hook anchors an answer from a row menu to the menu's opener" do
    hook =
      "lib/portfolixir_web/layout_view.ex"
      |> File.read!()
      |> String.split("Hooks.InlineResult = {")
      |> Enum.at(1, "")
      |> String.split("\n            };\n")
      |> hd()

    assert hook =~ "anchor: function (control) {"
    assert hook =~ ~s{control.closest("[role='menu'][data-trigger]")}
    assert hook =~ ~s{document.getElementById(menu.getAttribute("data-trigger"))}
    assert hook =~ "control = self.anchor(control);"
  end
end
