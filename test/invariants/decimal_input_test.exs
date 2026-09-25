defmodule Portfolixir.Invariants.DecimalInputTest do
  use ExUnit.Case, async: true

  # User story (#869, numeric half; DESIGN.md → Numeric inputs; board
  # ux-design-2026-09-24/05-numeric-inputs, "Die Regel dahinter"):
  # As a maintainer adding a figure to a form,
  # I want the one decimal-input rule to be the only one the web layer has,
  # so that the next form cannot bring back a fifth way of reading a comma or
  # a field left-aligned in proportional digits.
  #
  # Acceptance criteria:
  # - Every text input with `inputmode="decimal"` in a template carries
  #   `class="num"`. Browser number inputs (`type="number"`) are outside the
  #   rule: their value carries a point whatever the page's language.
  # - No web module other than `PortfolixirWeb.DecimalInput` turns a comma
  #   into a point by hand.

  @web "lib/portfolixir_web/**/*.ex"

  test "every decimal text input carries class num" do
    inputs =
      for path <- Path.wildcard(@web),
          [tag] <- Regex.scan(~r/<input\b[^>]*?\/?>/s, File.read!(path)),
          tag =~ ~s(inputmode="decimal"),
          not (tag =~ ~s(type="number")),
          do: {path, tag}

    assert length(inputs) >= 12, "expected the twelve decimal text inputs of board 05"

    missing =
      for {path, tag} <- inputs,
          not Regex.match?(~r/class="(?:[^"]*\s)?num(?:\s[^"]*)?"/, tag),
          do: "#{path}: #{String.replace(tag, ~r/\s+/, " ")}"

    assert missing == [], "decimal inputs without class num:\n" <> Enum.join(missing, "\n")
  end

  test "only the shared helper reads a decimal comma" do
    offenders =
      for path <- Path.wildcard(@web),
          path != "lib/portfolixir_web/decimal_input.ex",
          File.read!(path) =~ ~r/String\.replace\([^()]*"\s*,\s*"\s*,\s*"\."\s*\)/,
          do: path

    assert offenders == []
  end
end
