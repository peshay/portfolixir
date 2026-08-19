defmodule Portfolixir.Invariants.PhxValueValueTest do
  use ExUnit.Case, async: true

  # User story (Sprint 7 UAT walkthrough, pr-review-checklist section G):
  # As a maintainer whose LiveView tests all pass,
  # I want a meta-test that fails when a clickable element carries
  # `phx-value-value`,
  # so that a control which works in every test and does nothing in a browser
  # cannot ship again.
  #
  # Why this is a rule and not a preference: LiveView's client collects the
  # `phx-value-*` attributes into the event payload and THEN runs
  #
  #     if(el.value !== undefined && !(el instanceof HTMLFormElement)){
  #       meta.value = el.value
  #     }
  #
  # (phoenix_live_view.esm.js, `extractMeta`). Every element with a `value`
  # property -- a <button> above all -- therefore has its `phx-value-value`
  # overwritten by its own DOM value, which for a button without a `value`
  # attribute is the empty string. The event still fires, the handler still
  # matches, and the parameter is silently blank.
  #
  # `render_click/1` cannot catch this: LiveViewTest reads the attributes off
  # the markup and never simulates the DOM property, so the test passes on a
  # control that is dead in the browser. That is exactly what happened to the
  # transaction history's filter chips, and only a walkthrough in a real
  # browser found it.
  #
  # Acceptance criteria:
  # - No `phx-value-value` in any web template or LiveView.
  # - The check names the substitute (any other suffix, e.g.
  #   `phx-value-option`) so the fix is obvious from the failure.

  @roots ["lib/portfolixir_web"]

  test "no clickable element carries the clobbered phx-value-value" do
    offenders =
      @roots
      |> Enum.flat_map(&Path.wildcard(Path.join(&1, "/**/*.{ex,heex}")))
      |> Enum.flat_map(fn path ->
        path
        |> File.read!()
        |> String.split("\n")
        |> Enum.with_index(1)
        # The attribute, not the name in prose: the two call sites that
        # explain WHY the name is unusable must not trip the check that
        # enforces it.
        |> Enum.filter(fn {line, _n} -> String.contains?(line, "phx-value-value=") end)
        |> Enum.map(fn {_line, n} -> "#{path}:#{n}" end)
      end)

    assert offenders == [],
           """
           `phx-value-value` is overwritten by the element's own DOM `value`
           before the event is sent, so the parameter arrives empty. Rename the
           attribute (e.g. `phx-value-option`) and match the new key in the
           handler:

           #{Enum.join(offenders, "\n")}
           """
  end
end
