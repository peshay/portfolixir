defmodule Portfolixir.Imports.DedupKey do
  @moduledoc """
  The #533 economic key of a booking: a formatting-tolerant identity over the
  **resolved** database fields — same portfolio, security and account ids,
  kind, date, and `Decimal`-normalized amounts.

  Two callers read it, and it is one function so they cannot drift apart:

    * the importer's pre-import economic layer (`Portfolixir.Imports.Applier`),
      which skips a re-imported row whose content hash drifted (PP-export
      precision) but whose resolved booking already exists;
    * the lifecycle merge (ADR-0050 §8), which pairs a source row with a
      target row when the source row's key, **rewritten onto the target**,
      equals the target row's — the pairs the operator decides to collapse
      or keep. Because the importer compares the same key, a moved or kept
      row is what a drifted re-import of it finds (obligation O3).

  Computed identically from import `attrs` and from a stored
  `%Transaction{}`, so equal economic bookings collapse to the same key
  regardless of how Portfolio Performance serialized the numbers.
  `Map.get/2` tolerates the kind-specific attrs that omit fields.
  """

  @type t :: tuple()

  @doc "The #533 key of a booking, from its attrs or its stored row."
  @spec of(map()) :: t()
  def of(record) when is_map(record) do
    {
      Map.get(record, :portfolio_id),
      Map.get(record, :type),
      Map.get(record, :date),
      Map.get(record, :security_id),
      Map.get(record, :securities_account_id),
      Map.get(record, :counter_securities_account_id),
      Map.get(record, :cash_account_id),
      Map.get(record, :counter_cash_account_id),
      Map.get(record, :currency_code),
      # Round to each column's stored NUMERIC scale (quantity 12, money 6) BEFORE
      # normalizing, so a full-precision incoming entry collapses onto the value
      # Postgres actually persisted — otherwise a price/quantity with more places
      # than the column holds would round on storage and never match its re-import.
      norm_decimal(Map.get(record, :quantity), 12),
      norm_decimal(Map.get(record, :price), 6),
      norm_decimal(Map.get(record, :gross_amount), 6),
      norm_decimal(Map.get(record, :fees), 6),
      norm_decimal(Map.get(record, :taxes), 6)
    }
  end

  defp norm_decimal(nil, _scale), do: nil

  defp norm_decimal(%Decimal{} = d, scale) do
    d |> Decimal.round(scale) |> Decimal.normalize() |> Decimal.to_string(:normal)
  end
end
