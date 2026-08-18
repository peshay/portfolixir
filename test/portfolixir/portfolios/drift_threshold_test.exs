defmodule Portfolixir.Portfolios.DriftThresholdTest do
  use ExUnit.Case, async: true

  alias Portfolixir.Portfolios.Allocation

  # User story (Sprint 7 closing act, two-way coverage rule for FR-37 #665):
  # As a local portfolio maintainer,
  # I want the drift threshold the agent already has as `min_drift=` to select
  # exactly the same categories when I use it on screen,
  # so that "the categories drifting more than 5 pp" means one set of rows, not
  # two that quietly disagree.
  #
  # Acceptance criteria:
  # - The predicate is ONE function, shared by the JSON serializer and the
  #   allocation page.
  # - No threshold keeps every row.
  # - The comparison is on the ABSOLUTE drift, so an underweight category is
  #   selected as readily as an overweight one.
  # - Exactly meeting the threshold is kept ("more than 5 pp" is inclusive at
  #   the boundary, as the API has always been).
  # - A category without a target carries no drift and is never selected — it
  #   has nothing to deviate from.

  defp row(drift), do: %{drift_weight: drift}

  test "no threshold keeps every row, including targetless ones" do
    assert Allocation.drift_at_least?(row(Decimal.new("0.0001")), nil)
    assert Allocation.drift_at_least?(row(nil), nil)
  end

  test "selects on absolute drift, in both directions" do
    threshold = Decimal.new("0.05")

    assert Allocation.drift_at_least?(row(Decimal.new("0.09")), threshold)
    assert Allocation.drift_at_least?(row(Decimal.new("-0.09")), threshold)
    refute Allocation.drift_at_least?(row(Decimal.new("0.01")), threshold)
    refute Allocation.drift_at_least?(row(Decimal.new("-0.01")), threshold)
  end

  test "the boundary is inclusive, on either side of zero" do
    threshold = Decimal.new("0.05")

    assert Allocation.drift_at_least?(row(Decimal.new("0.05")), threshold)
    assert Allocation.drift_at_least?(row(Decimal.new("-0.050")), threshold)
  end

  test "a targetless category is never selected by a threshold" do
    refute Allocation.drift_at_least?(row(nil), Decimal.new("0"))
  end
end
