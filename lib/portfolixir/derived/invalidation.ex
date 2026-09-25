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

  `resource_type`, `record` and `before` come straight from
  `Journal.record/3`, so a new journaled resource type needs no change here —
  it simply resolves to `:all` until someone teaches `BlastRadius` a narrower
  answer.

  **The radius is the union of both images** (#851). An update that moves a
  record — a transaction to another security, a buy to another portfolio —
  affects what the record used to touch as much as what it touches now; the
  after-image alone left the old portfolio's walk and the old security's
  metrics memoised as current. `before` is `nil` for a create; for a delete
  it is the same row as `record`, and the union changes nothing. Either
  image widening to `:all` widens the whole bump.
  """
  @spec after_write(Ecto.Repo.t(), String.t(), map(), map() | nil) :: :ok
  def after_write(repo, resource_type, record, before \\ nil)

  def after_write(repo, resource_type, record, before) when is_binary(resource_type) do
    DataVersion.bump(
      union(
        BlastRadius.for_write(resource_type, record),
        before_radius(&BlastRadius.for_write/2, resource_type, before)
      ),
      repo,
      union(
        BlastRadius.securities_for_write(resource_type, record),
        before_radius(&BlastRadius.securities_for_write/2, resource_type, before)
      )
    )
  end

  def after_write(repo, _resource_type, _record, _before), do: DataVersion.bump(:all, repo, :all)

  # No before-image (a create) contributes nothing; anything else resolves
  # through the same allowlist as the after-image, so it widens the same way.
  defp before_radius(_resolver, _resource_type, nil), do: []
  defp before_radius(resolver, resource_type, before), do: resolver.(resource_type, before)

  defp union(:all, _other), do: :all
  defp union(_one, :all), do: :all
  defp union(one, other), do: (one ++ other) |> Enum.uniq() |> Enum.sort()

  @doc """
  Bumps after a quote sync write. The sync's quotes are allowlisted out of
  the audit journal (market data, ADR-0017), so they cannot ride the journal
  seam and announce themselves here directly; an authored quote write is
  journaled and bumps the same radius through `after_write/4` (T-9).

  Two radii, one insert: every portfolio that ever transacted the security
  (plus the global basis), and the security's own basis (#825). The second
  is what makes a quote write for a security **no portfolio ever held** — a
  benchmark, a watch-only candidate — bump a counter that exists, where the
  portfolio radius alone is the empty list.
  """
  @spec after_quote_write(integer()) :: :ok
  def after_quote_write(security_id),
    do:
      DataVersion.bump(
        BlastRadius.for_quote(security_id),
        Repo,
        BlastRadius.securities_for_quote(security_id)
      )

  @doc """
  Bumps one portfolio's **rules counter** after a policy-rule write
  (ADR-0049 §5), on the writing transaction's `repo`.

  A rule write rides the journal seam like every write, and `BlastRadius`
  answers it with no portfolio: a standard over figures moves no figure. The
  one derived value that reads rules — the findings read — keys on this
  counter beside the portfolio basis, and this is where it is bumped.
  """
  @spec after_rule_write(integer(), Ecto.Repo.t()) :: :ok
  def after_rule_write(portfolio_id, repo \\ Repo) when is_integer(portfolio_id),
    do: DataVersion.bump_rules(portfolio_id, repo)

  @doc """
  Bumps after a view definition changes (its `include_all` flag or its bucket
  filter). View definitions are not journaled (ADR-0018 §5), so they cannot
  ride the journal seam; every value computed under a view reads its filter,
  and which portfolios a view reaches is itself what changed — so the radius
  is everything. View edits are rare, and a stale "ok" is the failure this
  prevents (the Sprint 15 closing act found the policy findings served from
  the memo after a view was narrowed).
  """
  @spec after_view_write() :: :ok
  def after_view_write, do: DataVersion.bump(:all, Repo, :all)

  @doc """
  Bumps after an exchange-rate write. Allowlisted out of the journal for the
  same reason as quotes. No security basis is bumped: a security's own data is
  its row, its quotes and its splits in its own currency, and no value keyed
  under a security basis reads an exchange rate (ADR-0047 §1).
  """
  @spec after_exchange_rate_write() :: :ok
  def after_exchange_rate_write, do: DataVersion.bump(BlastRadius.for_exchange_rate(), Repo)
end
