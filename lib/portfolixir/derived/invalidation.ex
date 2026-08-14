defmodule Portfolixir.Derived.Invalidation do
  @moduledoc """
  The seam every write calls to bump the data version of the derived-value
  bases it invalidates (ADR-0032 §3.4, carried forward into ADR-0039's single
  mechanism, whose I5 makes the bump non-bypassable).

  It exists as its own module so the write paths depend on **one narrow
  function**, not on the derived layer's internals or on the resolver.
  `Portfolixir.Journal` in particular is a low-level module that has no
  business knowing how a series is materialized; it knows only that a
  committed write must announce itself here.

  The bump is **a row update inside the writing transaction** (the journaled
  path passes its own `repo`), not a broadcast: a read after a committed write
  always composes the post-write version into its key, so it can never be
  served a pre-write value as current. A rolled-back transaction rolls its
  bump back with it.

  This is the **only** contact a write path may have with the derived layer:
  writes announce, they never read (I7,
  `test/invariants/derived_never_a_write_source_test.exs`).
  """

  alias Portfolixir.Derived.BlastRadius
  alias Portfolixir.Derived.DataVersion
  alias Portfolixir.Repo

  @doc """
  Bumps the bases of every portfolio a journaled write can affect, on the
  writing transaction's `repo`.

  `resource_type` and `record` come straight from `Journal.record/3`, so a new
  journaled resource type needs no change here — it simply resolves to `:all`
  until someone teaches `BlastRadius` a narrower answer.
  """
  @spec after_write(Ecto.Repo.t(), String.t(), map()) :: :ok
  def after_write(repo, resource_type, record) when is_binary(resource_type) do
    DataVersion.bump(BlastRadius.for_write(resource_type, record), repo)
  end

  def after_write(repo, _resource_type, _record), do: DataVersion.bump(:all, repo)

  @doc """
  Bumps after a quote write. Quotes are allowlisted out of the audit journal
  (market data, ADR-0017), so they cannot ride the journal seam and announce
  themselves here directly.
  """
  @spec after_quote_write(integer()) :: :ok
  def after_quote_write(security_id),
    do: DataVersion.bump(BlastRadius.for_quote(security_id), Repo)

  @doc """
  Bumps after an exchange-rate write. Allowlisted out of the journal for the
  same reason as quotes.
  """
  @spec after_exchange_rate_write() :: :ok
  def after_exchange_rate_write, do: DataVersion.bump(BlastRadius.for_exchange_rate(), Repo)
end
