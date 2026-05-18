defmodule Portfolixir.Imports.Mapping do
  @moduledoc """
  Helpers to derive an initial UI mapping from a parsed `Preview` and
  to translate the LiveView form params into the shape
  `Portfolixir.Imports.Applier.apply/2` expects in its mapping-driven
  path.

  Two responsibilities only — anything more belongs in the LiveView.
  """

  alias Portfolixir.Imports.Preview

  @doc """
  Returns the set of unique PP cash account names referenced anywhere
  in the preview (parent + companion entries).
  """
  def unique_cash_pp_names(%Preview{entries: entries}) do
    entries
    |> flatten_entries()
    |> Enum.flat_map(fn e ->
      [e.pp_account_name, e.pp_counter_account_name]
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Returns the set of unique PP depot ("portfolio") names referenced
  anywhere in the preview (parent + companion + counter side).
  """
  def unique_depot_pp_names(%Preview{entries: entries}) do
    entries
    |> flatten_entries()
    |> Enum.flat_map(fn e ->
      [e.pp_portfolio_name, e.pp_counter_portfolio_name]
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  For each PP depot name, returns the most common PP cash account name
  seen on entries that mention that depot — used to pre-fill the
  "linked cash" dropdown when the user picks "create new" for the
  depot.
  """
  def default_cash_for_depot(%Preview{entries: entries}, depot_pp_name) do
    entries
    |> flatten_entries()
    |> Enum.filter(fn e ->
      e.pp_portfolio_name == depot_pp_name or e.pp_counter_portfolio_name == depot_pp_name
    end)
    |> Enum.map(& &1.pp_account_name)
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies()
    |> Enum.max_by(fn {_name, count} -> count end, fn -> {nil, 0} end)
    |> elem(0)
  end

  defp flatten_entries(entries) do
    Enum.flat_map(entries, fn e -> [e | e.companion_entries || []] end)
  end
end
