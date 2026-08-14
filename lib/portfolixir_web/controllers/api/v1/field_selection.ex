defmodule PortfolixirWeb.Api.V1.FieldSelection do
  @moduledoc """
  Sparse fieldsets for the heavy list reads (FR-37, issue #665).

  `fields=` is a comma-separated selection resolved against a **per-endpoint
  whitelist**: a precomputed string-to-atom map built from the serializer's
  own field list. Requested names are looked up in that map — no atom is ever
  created from input (stricter than `String.to_existing_atom/1` at the
  boundary, which the requirement demands as the minimum), and nothing is
  passed through to a query builder. An unknown name or an empty item in a
  non-empty selection is a validation error, never a silent fallback; an
  absent or empty `fields=` parameter means the full projection, the same
  as not asking (review finding: the doc claimed empty was an error while
  the code treated it as absent — the code's behavior is the contract).
  """

  @doc "Builds the string=>atom whitelist map from a serializer field list."
  def whitelist(fields) when is_list(fields) do
    Map.new(fields, fn field -> {Atom.to_string(field), field} end)
  end

  @doc """
  Parses the `fields` param against a whitelist map.

  Returns `{:ok, nil}` when absent (full projection), `{:ok, fields}` with
  the selected atoms in request order, or `{:error, :fields}`.
  """
  def parse(params, whitelist) do
    case Map.get(params, "fields") do
      nil -> {:ok, nil}
      "" -> {:ok, nil}
      value when is_binary(value) -> resolve(value, whitelist)
      _other -> {:error, :fields}
    end
  end

  defp resolve(value, whitelist) do
    names = value |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

    resolved =
      Enum.reduce_while(names, [], fn name, acc ->
        case Map.fetch(whitelist, name) do
          {:ok, field} -> {:cont, [field | acc]}
          :error -> {:halt, :error}
        end
      end)

    case {names, resolved} do
      {[], _} -> {:error, :fields}
      {_, :error} -> {:error, :fields}
      {_, fields} -> {:ok, fields |> Enum.reverse() |> Enum.uniq()}
    end
  end

  @doc "Applies a parsed selection to a serialized row; `nil` keeps all fields."
  def take(row, nil), do: row
  def take(row, fields) when is_list(fields), do: Map.take(row, fields)
end
