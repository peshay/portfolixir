defmodule Portfolixir.Invariants.NativeDialogTest do
  use ExUnit.Case, async: true

  # User story:
  # As a keyboard and screen-reader user opening any modal,
  # I want modals to be native <dialog> elements opened with showModal(),
  # so that focus containment, background inertness and Esc handling are
  # real instead of asserted (UX-DR9, issue 646 — aria-modal on a plain div
  # confines the screen reader's virtual cursor while Tab keeps walking the
  # page behind it).
  #
  # Acceptance criteria:
  # - No `aria-modal` attribute ships in the web layer: a native dialog
  #   opened modally is implicitly modal, and a non-dialog must not claim
  #   modality.
  # - Every `<dialog` carries the ModalDialog hook, so it actually opens
  #   with showModal() instead of staying hidden.

  @web_glob "lib/portfolixir_web/**/*.ex"

  test "no aria-modal attributes remain in the web layer" do
    offenders =
      @web_glob
      |> Path.wildcard()
      |> Enum.flat_map(fn path ->
        path
        |> File.read!()
        |> String.split("\n")
        |> Enum.with_index(1)
        |> Enum.filter(fn {line, _} -> String.contains?(line, "aria-modal") end)
        |> Enum.map(fn {_, lineno} -> "#{path}:#{lineno}" end)
      end)

    assert offenders == [], """
    aria-modal without native containment is worse than omitting it — use a
    native <dialog> with the ModalDialog hook (UX-DR9):
    #{Enum.join(offenders, "\n")}
    """
  end

  test "every <dialog> is opened by the ModalDialog hook" do
    for path <- Path.wildcard(@web_glob) do
      content = File.read!(path)
      dialogs = length(Regex.scan(~r/<dialog\b/, content))
      hooks = length(Regex.scan(~r/phx-hook="ModalDialog"/, content))

      assert dialogs == hooks, """
      #{path} renders #{dialogs} <dialog> element(s) but #{hooks} ModalDialog
      hook(s). A <dialog> without the hook never opens (no showModal() call).
      """
    end
  end

  test "the ModalDialog hook re-asserts the open state on server patches" do
    # morphdom strips the client-set `open` attribute on every patch (the
    # template never renders it); without an updated() re-assert the dialog
    # silently hides on the first in-dialog form change.
    hook =
      "lib/portfolixir_web/layout_view.ex"
      |> File.read!()
      |> String.split("Hooks.ModalDialog")
      |> Enum.at(1)
      |> String.split("Hooks.")
      |> hd()

    assert hook =~ "updated:"
    assert hook =~ "showModal"
  end
end
