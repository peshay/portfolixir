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
  def default_cash_for_depot(%Preview{} = preview, depot_pp_name) do
    Map.get(default_cash_by_depot(preview), depot_pp_name)
  end

  @doc """
  `default_cash_for_depot/2` for every PP depot name of the preview at once,
  in one pass over the entries (E25 S5, F35): `%{depot_name => cash_name}`,
  a depot whose entries name no cash account absent.
  """
  def default_cash_by_depot(%Preview{entries: entries}) do
    entries
    |> flatten_entries()
    |> Enum.reduce(%{}, fn e, acc ->
      [e.pp_portfolio_name, e.pp_counter_portfolio_name]
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.reduce(acc, &count_cash(&2, &1, e.pp_account_name))
    end)
    |> Map.new(fn {depot, frequencies} ->
      {depot, frequencies |> Enum.max_by(fn {_name, count} -> count end) |> elem(0)}
    end)
  end

  defp count_cash(acc, _depot, nil), do: acc

  defp count_cash(acc, depot, cash) do
    Map.update(acc, depot, %{cash => 1}, &Map.update(&1, cash, 1, fn n -> n + 1 end))
  end

  defp flatten_entries(entries) do
    Enum.flat_map(entries, fn e -> [e | e.companion_entries || []] end)
  end
end
