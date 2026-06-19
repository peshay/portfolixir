defmodule Portfolixir.Engines.BucketResolutionTest do
  # Pure engine — no DB, no Repo. Plain ExUnit (ADR-0018, architecture D2/P3).
  use ExUnit.Case, async: true

  alias Portfolixir.Engines.BucketResolution

  # User story:
  # As a local portfolio maintainer,
  # I want a position's effective buckets to come from its own override when set
  # and otherwise from its depot's default set, with "explicit-empty" distinct
  # from "inherit",
  # so that tag assignment is predictable and an empty override is never confused
  # with inheriting the depot defaults (ADR-0018).
  describe "effective_position_buckets/2" do
    test "inherit uses the depot default set" do
      assert BucketResolution.effective_position_buckets(:inherit, [1, 2]) == [1, 2]
    end

    test "explicit-empty yields no buckets, ignoring the depot default" do
      assert BucketResolution.effective_position_buckets(:explicit_empty, [1, 2]) == []
    end

    test "an explicit override replaces the depot default" do
      assert BucketResolution.effective_position_buckets({:explicit, [3]}, [1, 2]) == [3]
    end
  end

  # User story:
  # As a local portfolio maintainer,
  # I want a view to select holdings by an include set (or all) minus an exclude
  # set, with exclude always winning,
  # so that I can scope analytics to a slice of my wealth without ever
  # double-counting the single holding universe (ADR-0018).
  describe "holdings_matching_view/2" do
    setup do
      holdings = [
        %{ref: :a, buckets: [1]},
        %{ref: :b, buckets: [2]},
        %{ref: :c, buckets: [1, 2]},
        %{ref: :d, buckets: []}
      ]

      {:ok, holdings: holdings}
    end

    test "include :all returns every holding (untagged included)", %{holdings: holdings} do
      result = BucketResolution.holdings_matching_view(%{include: :all, exclude: []}, holdings)
      assert Enum.map(result, & &1.ref) == [:a, :b, :c, :d]
    end

    test "an include set keeps only holdings carrying one of those buckets", %{holdings: holdings} do
      result = BucketResolution.holdings_matching_view(%{include: [1], exclude: []}, holdings)
      assert Enum.map(result, & &1.ref) == [:a, :c]
    end

    test "untagged holdings are excluded by a specific include set", %{holdings: holdings} do
      result = BucketResolution.holdings_matching_view(%{include: [2], exclude: []}, holdings)
      refute Enum.any?(result, &(&1.ref == :d))
    end

    test "exclude wins over include for the same bucket", %{holdings: holdings} do
      # bucket 1 is both included and excluded -> excluded
      result = BucketResolution.holdings_matching_view(%{include: [1], exclude: [1]}, holdings)
      assert result == []
    end

    test "exclude removes holdings even under include :all", %{holdings: holdings} do
      result = BucketResolution.holdings_matching_view(%{include: :all, exclude: [2]}, holdings)
      # :b (only 2) and :c (1 and 2) are excluded; :a and :d remain
      assert Enum.map(result, & &1.ref) == [:a, :d]
    end

    test "the result is always a subset of the universe and never duplicated", %{
      holdings: holdings
    } do
      for include <- [:all, [1], [2], [1, 2], []],
          exclude <- [[], [1], [2], [1, 2]] do
        result =
          BucketResolution.holdings_matching_view(%{include: include, exclude: exclude}, holdings)

        refs = Enum.map(result, & &1.ref)

        # subset of the universe
        assert Enum.all?(refs, &(&1 in [:a, :b, :c, :d]))
        # never exceeds the single-count total
        assert length(result) <= length(holdings)
        # no holding appears twice (single-count guarantee)
        assert Enum.uniq(refs) == refs
      end
    end
  end

  # User story:
  # As a local portfolio maintainer reading a per-bucket breakdown,
  # I want overlapping buckets to be representable as overlapping groups that are
  # never summed as a partition,
  # so that a holding carrying two buckets is shown under both without inflating
  # the single-count total (ADR-0018 double-count guard).
  describe "group_by_bucket/1 (overlap is allowed, summing is not a partition)" do
    test "a multi-bucket holding appears under each of its buckets" do
      holdings = [%{ref: :c, buckets: [1, 2]}, %{ref: :a, buckets: [1]}]
      groups = BucketResolution.group_by_bucket(holdings)

      assert Enum.sort(Enum.map(groups[1], & &1.ref)) == [:a, :c]
      assert Enum.map(groups[2], & &1.ref) == [:c]

      # The sum of per-bucket group sizes (3) exceeds the single-count total (2):
      # breakdowns overlap and must never be summed as a partition.
      total_in_groups = groups |> Map.values() |> Enum.map(&length/1) |> Enum.sum()
      assert total_in_groups > length(holdings)
    end
  end
end
