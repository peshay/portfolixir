defmodule Portfolixir.Invariants.CssTextSizeAdjustTest do
  use ExUnit.Case, async: true

  # User story (Andi, 2026-07-16):
  # As a portfolio maintainer reading the allocation plan on a mobile browser,
  # I want every table row to render at its designed font size regardless of
  # how long a security name is,
  # so that the drift drill-down (and every other surface) looks consistent
  # instead of showing some rows bigger and some smaller.
  #
  # Root cause: the stylesheet never disabled mobile text inflation
  # ("font boosting" in Android Chrome, text auto-sizing in iOS Safari).
  # Without `text-size-adjust: 100%`, those browsers inflate text inside wide
  # blocks — such as the drift table's expanded position rows — by an amount
  # that depends on the content, so long security names change the rendered
  # font size. No app code sizes fonts by content length; the browser does.
  #
  # Acceptance criteria:
  # - The base `html` rule pins text-size-adjust to 100% (standard property
  #   plus the -webkit- prefix that iOS Safari still requires).
  test "the html rule disables mobile text inflation via text-size-adjust" do
    css = File.read!("priv/static/app.css")

    [html_rule] =
      Regex.run(~r/(?<![-\w.#])html\s*\{[^}]*\}/s, css)

    assert html_rule =~ ~r/-webkit-text-size-adjust:\s*100%;/,
           "expected the html rule to set -webkit-text-size-adjust: 100%"

    assert html_rule =~ ~r/(?<!-)text-size-adjust:\s*100%;/,
           "expected the html rule to set the standard text-size-adjust: 100%"
  end
end
