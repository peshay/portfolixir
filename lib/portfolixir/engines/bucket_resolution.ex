defmodule Portfolixir.Engines.BucketResolution do
  @moduledoc """
  Pure bucket/view resolution for tag-based wealth scoping (ADR-0018, FR-4).

  This is an **engine** (architecture D2/P3): pure functions over injected data
  only — no `Repo`, no clock, no config. The `Portfolixir.Buckets` context loads
  the assignments and views from the database and passes plain data here; the
  results feed valuation/allocation/performance/risk scoping in later stories
  (#444). Keeping the algebra pure makes the single-count invariant testable in
  isolation.

  ## Effective buckets

  A security position resolves to its **own override** when one exists, otherwise
  to its **depot's default** set. "explicit-empty" (a deliberate "no buckets"
  override) is a first-class state, distinct from "inherit":

    * `:inherit` — no override; use the depot default set.
    * `:explicit_empty` — an override that deliberately assigns no buckets.
    * `{:explicit, ids}` — an override assigning a specific set.

  ## Views

  A view is `%{include: :all | [bucket_id], exclude: [bucket_id]}`. A holding
  matches when it is included (always, under `:all`; otherwise it carries at
  least one included bucket) **and** carries no excluded bucket. **Exclude always
  wins**, so a bucket present in both sets excludes the holding.

  ## Single-count guard

  `holdings_matching_view/2` returns a **subset** of the holding universe with no
  duplication — the single-count total is never exceeded. Per-bucket breakdowns
  (`group_by_bucket/1`) may overlap (a holding with two buckets appears under
  both) and must therefore never be summed as a partition.
  """

  @type bucket_id :: term()
  @type override :: :inherit | :explicit_empty | {:explicit, [bucket_id()]}
  @type view :: %{required(:include) => :all | [bucket_id()], required(:exclude) => [bucket_id()]}

  @doc """
  The effective bucket ids for a position, given its `override` and the depot's
  `default_bucket_ids`.
  """
  @spec effective_position_buckets(override(), [bucket_id()]) :: [bucket_id()]
  def effective_position_buckets(:inherit, default_bucket_ids), do: default_bucket_ids
  def effective_position_buckets(:explicit_empty, _default_bucket_ids), do: []
  def effective_position_buckets({:explicit, ids}, _default_bucket_ids) when is_list(ids), do: ids

  @doc """
  Filters `holdings` to those matching `view`. Each holding is a map carrying a
  `:buckets` list of bucket ids (its effective buckets); other fields are opaque
  and preserved. Input order is preserved. Exclude wins.
  """
  @spec holdings_matching_view(view(), [map()]) :: [map()]
  def holdings_matching_view(view, holdings) when is_list(holdings) do
    include = normalize_include(Map.get(view, :include, :all))
    exclude = MapSet.new(Map.get(view, :exclude) || [])

    Enum.filter(holdings, fn holding ->
      effective = MapSet.new(Map.get(holding, :buckets) || [])
      included?(include, effective) and MapSet.disjoint?(effective, exclude)
    end)
  end

  @doc """
  Groups `holdings` by each of their buckets. A holding appears under **every**
  bucket it carries, so the groups overlap and their sizes must never be summed
  as a partition of the single-count universe.
  """
  @spec group_by_bucket([map()]) :: %{bucket_id() => [map()]}
  def group_by_bucket(holdings) when is_list(holdings) do
    Enum.reduce(holdings, %{}, fn holding, acc ->
      holding
      |> Map.get(:buckets)
      |> List.wrap()
      |> Enum.reduce(acc, fn bucket_id, inner ->
        Map.update(inner, bucket_id, [holding], &(&1 ++ [holding]))
      end)
    end)
  end

  defp normalize_include(:all), do: :all
  defp normalize_include(ids) when is_list(ids), do: MapSet.new(ids)

  defp included?(:all, _effective), do: true
  defp included?(%MapSet{} = include, effective), do: not MapSet.disjoint?(include, effective)
end
