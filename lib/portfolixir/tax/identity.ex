defmodule Portfolixir.Tax.Identity do
  @moduledoc """
  Normalisation for the free-text identity columns of the tax context —
  `holder` and `institution` (ADR-0031 §3, story 19.2 §5a).

  Portfolixir has no institution entity, so three tables key off these strings:
  `tax_profiles`, `allowance_orders` and (story 19.3)
  `tax_statement_snapshots`. Story 19.4 joins across them. If `"comdirect"` and
  `"Comdirect"` landed as two rows, the consistency engine would report a
  missing Freistellungsauftrag that is not missing — a wrong advisory that looks
  like a real finding.

  The rule is therefore fixed here once: normalise on write (trim, collapse
  internal whitespace runs, reject empty), store **case-preserving** because the
  operator's capitalisation is theirs, and match **case-folded** — the unique
  indexes are on `lower(...)`, so lookups have to fold the same way.
  """

  @doc """
  Trims and collapses internal whitespace runs to a single space.

  Only ever called from `update_change/3`, which runs after a successful cast —
  a non-string never reaches here, it is already a changeset type error.
  """
  @spec normalize(String.t()) :: String.t()
  def normalize(value) when is_binary(value) do
    value |> String.split() |> Enum.join(" ")
  end

  @doc """
  The case-folded form used for matching. Mirrors the `lower(...)` expression
  in the unique indexes.
  """
  @spec fold(String.t()) :: String.t()
  def fold(value) when is_binary(value), do: value |> normalize() |> String.downcase()
end
