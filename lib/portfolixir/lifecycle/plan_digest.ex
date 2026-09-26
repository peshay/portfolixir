defmodule Portfolixir.Lifecycle.PlanDigest do
  @moduledoc """
  The digest a merge preview hands out and its apply checks (ADR-0050 §10).

  A preview is a read; the operator's consent is to exactly what it showed.
  The digest is a SHA-256 over a **canonical** rendering of the plan — both
  rows and their `updated_at`, the sorted row ids per action with each row's
  `updated_at` and economic fields, the key-equal pairs as a set of their
  own, every figure the preview shows and the guard results — so the apply,
  which recomputes the plan under its locks, finds the same digest exactly
  when nothing the operator saw has changed. The operator's choices are not
  an input: one pair has one digest, whatever will be chosen.

  Canonical means independent of term order and representation: a map is
  its entries sorted by key, a `Decimal` its normalized string, a date or
  timestamp its ISO 8601 form, an atom its name. The rendering is JSON, so
  the digest does not depend on the VM's external term format.
  """

  @doc "The digest of `plan`, as `\"sha256:<hex>\"`."
  @spec compute(term()) :: String.t()
  def compute(plan) do
    hex =
      plan
      |> canonical()
      |> Jason.encode!()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    "sha256:" <> hex
  end

  @doc "`plan` as nested lists, maps sorted by key, scalars as JSON values."
  @spec canonical(term()) :: term()
  def canonical(%Decimal{} = decimal),
    do: decimal |> Decimal.normalize() |> Decimal.to_string(:normal)

  def canonical(%Date{} = date), do: Date.to_iso8601(date)
  def canonical(%NaiveDateTime{} = timestamp), do: NaiveDateTime.to_iso8601(timestamp)
  def canonical(%DateTime{} = timestamp), do: DateTime.to_iso8601(timestamp)

  def canonical(%_struct{} = struct),
    do: raise(ArgumentError, "a plan digest takes plain data, got #{inspect(struct.__struct__)}")

  def canonical(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> [canonical_key(key), canonical(value)] end)
    |> Enum.sort()
  end

  def canonical(list) when is_list(list), do: Enum.map(list, &canonical/1)
  def canonical(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> canonical()
  def canonical(value) when is_boolean(value) or is_nil(value), do: value
  def canonical(atom) when is_atom(atom), do: Atom.to_string(atom)
  def canonical(value) when is_binary(value) or is_number(value), do: value

  defp canonical_key(key) when is_binary(key), do: key
  defp canonical_key(key) when is_atom(key), do: Atom.to_string(key)
  defp canonical_key(key), do: key |> canonical() |> Jason.encode!()
end
