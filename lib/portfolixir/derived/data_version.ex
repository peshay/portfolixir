defmodule Portfolixir.Derived.DataVersion do
  @moduledoc """
  The durable per-basis data-version counter (ADR-0039 §5, I5).

  A basis is a named scope of ledger data a derived value depends on:
  `"portfolio:<id>"` for one portfolio's series, `"global"` for anything that
  depends on every portfolio (the cross-portfolio view walk, #577). Every
  ledger write bumps the counter of each basis it can affect — inside the
  writing transaction, through `Portfolixir.Derived.Invalidation` — so a read
  after a committed write can never compose a pre-write version into its key.

  The counter is **persistent** because the durable tier is: a memo entry dies
  with the process, but a stored row must still be provably stale after a
  restart. It is stored as **append-only version events**, and a basis's
  version is the highest event id recorded for it (`0` before the first bump —
  strictly monotonic, though not gapless, since the id sequence is shared
  across bases). Appending instead of incrementing a counter row is
  deliberate: an `UPDATE ... version + 1` would hold a row lock for the whole
  writing transaction and serialize every concurrent financial write on the
  shared `"global"` row; inserts never contend.

  Targeted invalidation (ADR-0032 §3, owner decision, carried forward): a
  narrow bump lists portfolio ids; `:all` widens to **every** portfolio — the
  set is enumerable from the portfolios table, so widening can never miss a
  basis that has no event row yet. Every bump also bumps `"global"`.
  """

  import Ecto.Query

  alias Portfolixir.Repo

  @global "global"
  @table "derived_data_version_events"
  @ready_key {__MODULE__, :schema_ready}

  @doc "The basis key of one portfolio's derived values."
  @spec portfolio_basis(integer()) :: String.t()
  def portfolio_basis(portfolio_id) when is_integer(portfolio_id),
    do: "portfolio:#{portfolio_id}"

  @doc "The basis key of derived values depending on every portfolio."
  @spec global_basis() :: String.t()
  def global_basis, do: @global

  @doc "The current version of a basis; `0` before its first bump."
  @spec current(String.t(), Ecto.Repo.t()) :: non_neg_integer()
  def current(basis, repo \\ Repo) when is_binary(basis) do
    from(e in @table, where: e.basis == ^basis, select: max(e.id))
    |> repo.one() || 0
  end

  @doc """
  Bumps the version of the given portfolios' bases — plus, always, the global
  basis — or of **every** portfolio for `:all`. Runs on the given repo so a
  journaled write bumps inside its own transaction.

  `:all` is not an emergency lever: it is the ordinary result of a write whose
  blast radius cannot be proven narrower (ADR-0032 §3.3, carried forward).
  """
  @spec bump(:all | [integer()], Ecto.Repo.t()) :: :ok
  def bump(target, repo \\ Repo)

  def bump(:all, repo) do
    bump(repo.all(from(p in Portfolixir.Portfolios.Portfolio, select: p.id)), repo)
  end

  def bump(portfolio_ids, repo) when is_list(portfolio_ids) do
    if schema_ready?(repo) do
      bases =
        portfolio_ids
        |> Enum.uniq()
        |> Enum.map(&portfolio_basis/1)
        |> Enum.concat([@global])

      repo.insert_all(@table, Enum.map(bases, &%{basis: &1}))
    end

    :ok
  end

  @doc """
  Compacts the event log to one row per basis (the newest, so every version
  stays exactly what it was). Part of drop-and-rebuild — never required for
  correctness, only for tidiness.
  """
  @spec compact(Ecto.Repo.t()) :: :ok
  def compact(repo \\ Repo) do
    newest = from(e in @table, group_by: e.basis, select: max(e.id))
    repo.delete_all(from(e in @table, where: e.id not in subquery(newest)))
    :ok
  end

  # Journaled writes happen during data migrations that run BEFORE this
  # module's own migration on a fresh database (the bucket-scope and journal
  # seeds). A bump attempt there would abort the seed's transaction; skipping
  # it is sound, because with no derived tables there is nothing that could go
  # stale. Once the table is seen the answer is cached process-wide — the gate
  # never weakens after bootstrap.
  defp schema_ready?(repo) do
    :persistent_term.get(@ready_key, false) ||
      case repo.query!("SELECT to_regclass($1)", ["public." <> @table]).rows do
        [[nil]] ->
          false

        _found ->
          :persistent_term.put(@ready_key, true)
          true
      end
  end
end
