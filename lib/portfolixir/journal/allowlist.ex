defmodule Portfolixir.Journal.Allowlist do
  @moduledoc """
  The closed set of write paths that are deliberately **not** journaled
  (ADR-0017, FR-28).

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

  # ADR-0018 §5: view definitions, bucket assignments and the snapshot markers
  # (ADR-0027) are *scope* — which accounts and positions a view reads — not
  # financial records. Their writes are actor-first and, where they cascade
  # into armed tables (deleting a view drops its plans), journaled, but the
  # tables themselves are deliberately not guard-armed. Recorded here (#767,
  # E21) so the exemption is a closed list under the same meta-test as the
  # market-data set instead of a comment in a migration.
  # `settings` holds the operator's default view (a preference, scope again),
  # written by PUT /api/v1/settings/default_view without an actor.
  @unarmed_scope_tables ~w(views view_include_buckets view_exclude_buckets
                           securities_account_buckets cash_account_buckets
                           position_bucket_overrides depot_snapshots settings)

  @doc "Table names whose writes are intentionally exempt from journaling."
  @spec non_journaled_tables() :: [String.t()]
  def non_journaled_tables, do: @non_journaled_tables

  @doc "Scope tables deliberately left without the journal-actor guard (ADR-0018 §5)."
  @spec unarmed_scope_tables() :: [String.t()]
  def unarmed_scope_tables, do: @unarmed_scope_tables

  @doc "Whether writes to `table` are exempt from journaling."
  @spec non_journaled?(String.t()) :: boolean()
  def non_journaled?(table) when is_binary(table), do: table in @non_journaled_tables
end
