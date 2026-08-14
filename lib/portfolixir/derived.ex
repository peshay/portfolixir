defmodule Portfolixir.Derived do
  @moduledoc """
  Durable derived values (ADR-0039): **one mechanism, three lifetimes**.

  A derived value is a pure function value over a versioned, named basis.
  Everything else is a question of how long the result is kept:

  | Lifetime   | Mechanism                                              |
  |------------|--------------------------------------------------------|
  | `:none`    | recompute on every call                                |
  | `:request` | in-memory memo, dies with the process (ADR-0032, absorbed) |
  | `:durable` | row in `derived_values` carrying `as_of` and `data_version` |

  Every read composes the basis's **current data version** and the analytic's
  **computation version** into the key, so no return path can claim freshness
  without checking the counter (I4). `fetch/4` always serves a fresh value —
  stale means recompute (ADR-0032 §4) — and `peek/3` is the non-computing read
  a surface uses to render the superseded value, labelled, while the fresh one
  computes (§6).

  The four FR-1 properties, and where each is held up:

  1. **rebuildable** — `rebuild/1` and the `portfolixir.derived.rebuild` mix
     task drop and recompute everything from the ledger;
  2. **versioned** — `Portfolixir.Derived.DataVersion`, bumped by every ledger
     write through `Portfolixir.Derived.Invalidation`;
  3. **never silent about freshness** — the tagged read shapes here, plus
     `as_of`/`stale` in every payload that serves a derived value;
  4. **never authoritative for a write** — no write path may call `fetch/4` or
     `peek/3`; enforced by `derived_never_a_write_source_test.exs`.

  ADR-0035 stays the first line of defence: a value merely computed more often
  than necessary gets computed once, not registered here.
  """

  import Ecto.Query

  alias Portfolixir.Derived.DataVersion
  alias Portfolixir.Derived.Memo
  alias Portfolixir.Derived.Registry
  alias Portfolixir.Derived.Value
  alias Portfolixir.Repo

  # Durable rows a store pass considers junk: same analytic and basis, but so
  # old that no surface will ask for their entry key again (day-rollover keys).
  @prune_after_days 30

  @doc "Whether the derived layer is active. Off means every lifetime is `:none`."
  @spec enabled?() :: boolean()
  def enabled? do
    :portfolixir
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:enabled?, true)
  end

  @doc "The basis key of one portfolio's derived values."
  defdelegate portfolio_basis(portfolio_id), to: DataVersion

  @doc "The basis key of derived values depending on every portfolio."
  defdelegate global_basis(), to: DataVersion

  @doc """
  The derived value for `(analytic_id, basis, entry_key)`, computing it with
  `compute` when no current-version value exists.

  Always returns `{:fresh, value}`: a memo or durable hit is only a hit when
  its `(data_version, computation_version)` pair is current, and everything
  else recomputes. The version is captured **before** the computation runs, so
  a write landing mid-compute leaves the stored result already superseded —
  failing toward recomputation, never toward a stale number.
  """
  @spec fetch(atom(), String.t(), String.t(), (-> term())) :: {:fresh, term()}
  def fetch(analytic_id, basis, entry_key, compute)
      when is_binary(basis) and is_binary(entry_key) and is_function(compute, 0) do
    case Registry.lifetime(analytic_id) do
      :none ->
        {:fresh, compute.()}

      lifetime ->
        comp = Registry.computation_version!(analytic_id)
        version = DataVersion.current(basis)
        key = {analytic_id, basis, entry_key, version, comp}

        with :miss <- Memo.get(key),
             :miss <- durable_get(lifetime, key) do
          value = compute.()
          as_of = DateTime.truncate(DateTime.utc_now(), :second)
          Memo.put(key, value, as_of)
          durable_put(lifetime, key, value, as_of)
          {:fresh, value}
        else
          {:hit, value, _as_of} -> {:fresh, value}
        end
    end
  end

  @doc """
  The non-computing read (I4 shape): `{:fresh, value}` when a current-version
  value exists, `{:stale, value, as_of}` when only a superseded one does, and
  `:none` otherwise.

  This is what a surface renders — labelled with `as_of` and marked stale —
  instead of a skeleton while `fetch/4` recomputes (ADR-0032 §6, carried
  forward). For a durable analytic the stale value survives restarts.
  """
  @spec peek(atom(), String.t(), String.t()) ::
          {:fresh, term()} | {:stale, term(), DateTime.t()} | :none
  def peek(analytic_id, basis, entry_key) when is_binary(basis) and is_binary(entry_key) do
    case Registry.lifetime(analytic_id) do
      :none ->
        :none

      lifetime ->
        comp = Registry.computation_version!(analytic_id)
        version = DataVersion.current(basis)
        key = {analytic_id, basis, entry_key, version, comp}

        with :miss <- Memo.get(key),
             :miss <- durable_get(lifetime, key) do
          peek_superseded(lifetime, key)
        else
          {:hit, value, _as_of} -> {:fresh, value}
        end
    end
  end

  @doc """
  Drops **every** durable derived value and resets every basis version, then
  recomputes the operative entries through `warm` (a zero-arity function that
  reads through the ordinary request path, e.g. the performance warm-up).

  This is the single operator command behind `mix portfolixir.derived.rebuild`
  (ADR-0039 §6): the emergency procedure, and it reports its own runtime.
  Returns `{:ok, %{dropped: n, runtime_ms: ms}}`.
  """
  @spec rebuild((-> any())) :: {:ok, %{dropped: non_neg_integer(), runtime_ms: non_neg_integer()}}
  def rebuild(warm) when is_function(warm, 0) do
    started = System.monotonic_time(:millisecond)

    {dropped, _} = Repo.delete_all(Value)
    DataVersion.compact()
    Memo.reset()
    warm.()

    {:ok, %{dropped: dropped, runtime_ms: System.monotonic_time(:millisecond) - started}}
  end

  # -- durable tier ------------------------------------------------------------

  defp durable_get(:request, _key), do: :miss

  defp durable_get(:durable, {analytic_id, basis, entry_key, version, comp} = key) do
    case durable_row(analytic_id, basis, entry_key) do
      %Value{data_version: ^version, computation_version: ^comp} = row ->
        value = Value.decode(row.payload)
        # Promote to the memo so the payload is decoded once per version.
        Memo.put(key, value, row.as_of)
        {:hit, value, row.as_of}

      _stale_or_missing ->
        :miss
    end
  end

  defp durable_put(:request, _key, _value, _as_of), do: :ok

  defp durable_put(:durable, {analytic_id, basis, entry_key, version, comp}, value, as_of) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    Repo.insert!(
      %Value{
        analytic_id: to_string(analytic_id),
        basis: basis,
        entry_key: entry_key,
        data_version: version,
        computation_version: comp,
        as_of: as_of,
        payload: Value.encode(value),
        inserted_at: now,
        updated_at: now
      },
      on_conflict:
        {:replace, [:data_version, :computation_version, :as_of, :payload, :updated_at]},
      conflict_target: [:analytic_id, :basis, :entry_key]
    )

    prune(analytic_id, basis, now)
    :ok
  end

  # A superseded value to render while recomputing: the request tier keeps one
  # previous generation in the memo; the durable tier's not-yet-replaced row
  # covers the same need across restarts. Both stay readable — always marked,
  # never as current — until a fresh computation replaces them.
  defp peek_superseded(lifetime, {analytic_id, basis, entry_key, _version, _comp} = key) do
    case Memo.previous(key) do
      {:hit, value, as_of} ->
        {:stale, value, as_of}

      :miss ->
        with :durable <- lifetime,
             %Value{} = row <- durable_row(analytic_id, basis, entry_key) do
          {:stale, Value.decode(row.payload), row.as_of}
        else
          _none -> :none
        end
    end
  end

  defp durable_row(analytic_id, basis, entry_key) do
    Value
    |> where(
      [v],
      v.analytic_id == ^to_string(analytic_id) and v.basis == ^basis and
        v.entry_key == ^entry_key
    )
    |> Repo.one()
  end

  # Entry keys carry the walk's end date, so superseded days accumulate rows
  # nobody will ask for again. Age-bounded, swept opportunistically on store.
  defp prune(analytic_id, basis, now) do
    cutoff = DateTime.add(now, -@prune_after_days * 86_400, :second)

    Value
    |> where(
      [v],
      v.analytic_id == ^to_string(analytic_id) and v.basis == ^basis and
        v.updated_at < ^cutoff
    )
    |> Repo.delete_all()
  end
end
