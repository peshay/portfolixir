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

  @doc """
  The part of a digest one stored booking contributes: its id and
  `updated_at`, and every economic and foreign-key field a merge moves, pairs
  or folds — so an edit of any of them between the preview and the apply
  changes the digest (§10). Whether the row carries a content hash is part
  of it (a hash is retired when the row goes); the hash itself is not.
  """
  @spec transaction_fingerprint(map()) :: list()
  def transaction_fingerprint(row) do
    [
      row.id,
      row.updated_at,
      row.portfolio_id,
      row.type,
      row.date,
      row.currency_code,
      row.gross_amount,
      row.fees,
      row.taxes,
      row.quantity,
      row.price,
      row.security_amount,
      row.settlement_amount,
      row.split_ratio_numerator,
      row.split_ratio_denominator,
      row.cash_account_id,
      row.counter_cash_account_id,
      row.securities_account_id,
      row.counter_securities_account_id,
      row.security_id,
      row.import_hash != nil
    ]
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
