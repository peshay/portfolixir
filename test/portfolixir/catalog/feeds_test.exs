defmodule Portfolixir.Catalog.FeedsTest do
  use ExUnit.Case, async: true

  alias Portfolixir.Catalog.Feeds

  # User story:
  # As a local portfolio maintainer choosing a quote feed for a security,
  # I want the feed dropdown to offer only known, serviceable feed codes with
  # readable labels,
  # so that I cannot save a feed string none of the adapters can fetch.
  #
  # Acceptance criteria:
  # - codes/0 lists the closed set of known feed identifiers.
  # - options/0 returns {label, code} pairs for every code, with non-empty
  #   labels.
  # - supported?/1 accepts nil and "" (unset), the known codes, and rejects
  #   anything else.
  # - label/1 maps each known code to a non-empty string, nil to "", and an
  #   unknown value to its string form.

  test "codes/0 is the closed set of known feeds" do
    assert Feeds.codes() == ~w(NONE MANUAL PORTFOLIO_PERFORMANCE COINGECKO)
  end

  test "options/0 pairs every code with a non-empty label" do
    options = Feeds.options()

    assert Enum.map(options, &elem(&1, 1)) == Feeds.codes()

    for {label, _code} <- options do
      assert is_binary(label)
      assert label != ""
    end
  end

  test "supported?/1 accepts unset and known codes, rejects the rest" do
    assert Feeds.supported?(nil)
    assert Feeds.supported?("")

    for code <- Feeds.codes() do
      assert Feeds.supported?(code)
    end

    refute Feeds.supported?("UNKNOWN")
    refute Feeds.supported?(:not_a_string)
  end

  test "label/1 maps codes to non-empty strings, nil to empty, unknown to string" do
    for code <- Feeds.codes() do
      label = Feeds.label(code)
      assert is_binary(label)
      assert label != ""
    end

    assert Feeds.label(nil) == ""
    assert Feeds.label("WEIRD") == "WEIRD"
  end
end
