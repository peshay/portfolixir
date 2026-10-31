defmodule Portfolixir.Invariants.CssSharedComponentsTest do
  use ExUnit.Case, async: true

  # Sprint 21 γ8, board ux-design-2026-10-09/08-shared-copy: the shared
  # components every page renders — a dialog's footer, the inline result's
  # slot and its dismiss. The rules are CSS, so the stylesheet is what these
  # tests read; the rendered structure each rule selects is pinned in
  # `test/portfolixir_web/components/inline_result_test.exs` and
  # `test/portfolixir_web/live/shared_components_live_test.exs`.

  @css File.read!("priv/static/app.css")

  # User story (#1138, Sprint 21 γ8; board 08, "#1138"):
  # As the operator closing the Manage-logo dialog with the keyboard,
  # I want its last button to stand inside the dialog's padding,
  # so that "Logo entfernen" does not touch the dialog's edge and its focus
  # ring is not cut by the dialog's overflow.
  #
  # Acceptance criteria:
  # - A footer that is the dialog's own child takes the body's 18 px padding
  #   (`.modal > .modal-footer:not(.modal-footer--band)`, `0 18px 18px`).
  # - A band footer keeps its own padding (`12px 18px`).
  # - The blocked-delete dialogs' scoped rule, which this one makes a
  #   duplicate, is gone: one rule for every dialog.
  test "a dialog's own footer takes the body's padding" do
    assert block(".modal > .modal-footer:not(.modal-footer--band)") =~
             ~r/padding:\s*0 18px 18px;/

    assert block(".modal-footer.modal-footer--band") =~ ~r/padding:\s*12px 18px;/

    refute @css =~ ~r/\n\.confirm-delete-blocked \.modal-footer \{/
  end

  # User story (#1160, Sprint 21 γ8; board 08, "#1160"):
  # As the operator reading Accounts, Securities and Snapshots before any
  # action,
  # I want an empty result slot to take no room,
  # so that the page looks as it does until an action answers — no 8 px band,
  # and on Accounts no second 16 px grid gap.
  #
  # Acceptance criteria:
  # - The component's region takes its 8 px margins only when it holds a
  #   result (`:has(> *)`): its regions always hold whitespace, so the old
  #   `:not(:empty)` always matched and is gone.
  # - In a section's grid every empty inline result leaves the flow, not only
  #   a page slot (`.workspace-section > .inline-result:not(…)`), so the grid
  #   adds no gap for it.
  # - A page slot keeps its own footprint: no margin at rest, 12 px above a
  #   result.
  test "an empty inline result takes no room at rest" do
    assert block(".inline-result__region:has(> *)") =~ ~r/margin:\s*8px 0;/
    refute @css =~ ~r/\.inline-result__region:not\(:empty\)/

    assert block(".workspace-section > .inline-result:not(:has(.inline-result__region > *))") =~
             ~r/position:\s*absolute;/

    assert block(".inline-result.inline-result--page > .inline-result__region") =~
             ~r/margin:\s*0;/

    assert block(".inline-result.inline-result--page > .inline-result__region:has(> *)") =~
             ~r/margin:\s*12px 0 0;/
  end

  defp block(selector) do
    case Regex.run(~r/\n#{Regex.escape(selector)} \{([^}]*)\}/, @css) do
      [_, body] -> body
      nil -> flunk("no top-level rule for #{inspect(selector)}")
    end
  end
end
