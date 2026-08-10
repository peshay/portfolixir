defmodule Portfolixir.Invariants.CssMotionGateTest do
  use ExUnit.Case, async: true

  # User story:
  # As a maintainer holding the motion rules (UX-DR5) against the stylesheet,
  # I want a meta-test that fails when an animation ships outside the opt-in
  # `prefers-reduced-motion: no-preference` gate,
  # so that a forgotten gate degrades to "no motion" instead of shipping an
  # unguarded animation (issues 638 and 647 — the build had the opt-out form
  # everywhere and one looping animation with no gate at all).
  #
  # Acceptance criteria:
  # - Every `animation:` declaration in app.css sits inside a
  #   `prefers-reduced-motion: no-preference` media block.
  # - Sanctioned exception: an indicator that must survive `reduce` as a
  #   static shape (the spinner family) animates by default and is cancelled
  #   under `reduce`, because the opt-in form would remove the shape with the
  #   motion.
  # - `animation: none` cancellations are always allowed.

  @css_path "priv/static/app.css"

  # The must-survive indicators (DESIGN.md → Motion, sanctioned exception).
  @exempt_selectors ~r/\.spinner|\.import-spinner/

  test "animations are opt-in behind prefers-reduced-motion: no-preference" do
    {offenders, _stack} =
      @css_path
      |> File.read!()
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.reduce({[], []}, fn {line, lineno}, {offenders, stack} ->
        trimmed = String.trim(line)

        cond do
          # One-line blocks (keyframe steps) leave the stack unchanged.
          String.contains?(trimmed, "{") and String.contains?(trimmed, "}") ->
            {offenders, stack}

          String.ends_with?(trimmed, "{") ->
            kind = if String.starts_with?(trimmed, "@media"), do: :media, else: :rule
            {offenders, [{kind, trimmed} | stack]}

          trimmed == "}" and stack != [] ->
            {offenders, tl(stack)}

          String.match?(trimmed, ~r/^animation:/) and
              not String.contains?(trimmed, "animation: none") ->
            gated? =
              Enum.any?(stack, fn
                {:media, condition} -> String.contains?(condition, "no-preference")
                _ -> false
              end)

            selector =
              Enum.find_value(stack, "", fn
                {:rule, sel} -> sel
                _ -> nil
              end)

            if gated? or Regex.match?(@exempt_selectors, selector) do
              {offenders, stack}
            else
              {["#{@css_path}:#{lineno}: #{selector} #{trimmed}" | offenders], stack}
            end

          true ->
            {offenders, stack}
        end
      end)

    assert offenders == [], """
    Animations outside the `prefers-reduced-motion: no-preference` gate (and
    not a sanctioned must-survive indicator):
    #{offenders |> Enum.reverse() |> Enum.join("\n")}
    Move the `animation:` declaration into a no-preference block, or — only
    for an indicator that must survive `reduce` as a static shape — add the
    selector to the sanctioned list in this test together with a `reduce`
    cancellation in app.css.
    """
  end
end
