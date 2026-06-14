defmodule Portfolixir.Journal.Allowlist do
  @moduledoc """
  The closed set of write paths that are deliberately **not** journaled
  (ADR-0015, FR-28).

  Market-data ingestion (quote sync, FX-rate sync) writes operational, machine-
  refreshed data — not financial records a human or agent authored — so it is
  exempt from the audit journal and its tables are never armed with the
  actor-guard trigger.

  This list is governed by a meta-test so the exception set can only **shrink**,
  never grow silently. The `idempotency_keys` table (future) is operational
  state, not a journaled table, so it does not belong here — the allowlist
  governs only writers of *journaled* tables that are intentionally exempted.
  """

  @non_journaled_tables ~w(security_quotes exchange_rates)

  @doc "Table names whose writes are intentionally exempt from journaling."
  @spec non_journaled_tables() :: [String.t()]
  def non_journaled_tables, do: @non_journaled_tables

  @doc "Whether writes to `table` are exempt from journaling."
  @spec non_journaled?(String.t()) :: boolean()
  def non_journaled?(table) when is_binary(table), do: table in @non_journaled_tables
end
