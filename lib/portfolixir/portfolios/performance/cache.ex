defmodule Portfolixir.Portfolios.Performance.Cache do
  @moduledoc """
  Volatile memo for the daily performance walk (ADR-0032).

  This is a **memoisation of a pure function, not a store**, and every property
  below follows from that:

  - it lives in ETS owned by this process and is empty after every restart;
  - it is never read as a source of truth — dropping the table at any moment
    changes latency and nothing else, which is what leaves
    [ADR-0004](`e:portfolixir:0004-holdings-derived-from-transactions.html`)
    (holdings are never stored) intact;
  - it can be switched off entirely by configuration, and the suite passes with
    it off. That is what makes the previous sentence a checked claim.

  ## Key

      {portfolio_id, view_scope_key, today, portfolio_data_version}

  `view_scope_key` is a view id or `:unscoped`; `today` is the walk's end date,
  so a day rollover misses naturally with no timer. The version is **per
  portfolio** (ADR-0032 §3, owner decision): invalidating one portfolio leaves
  every other memo readable.

  ## One previous generation

  `invalidate/1` bumps a portfolio's version, which makes its entries
  unreachable as *current* — but §6 renders exactly one superseded entry while
  the fresh series computes, so the sweep keeps the immediately preceding
  generation and drops everything older. Two generations is the whole bound.
  """

  use GenServer

  @table __MODULE__
  @version_prefix :version

  # -- client ----------------------------------------------------------------

  @doc false
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Whether the memo is active. Off means every read recomputes."
  @spec enabled?() :: boolean()
  def enabled? do
    :portfolixir
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:enabled?, true)
  end

  @doc """
  Returns the memoised analysis for the key, computing and remembering it on a
  miss. With the memo disabled, `compute` runs every time and nothing is kept.
  """
  @spec fetch(integer(), term(), Date.t(), (-> term())) :: term()
  def fetch(portfolio_id, scope_key, %Date{} = today, compute) when is_function(compute, 0) do
    if enabled?() and table?() do
      memoised(portfolio_id, scope_key, today, compute)
    else
      compute.()
    end
  end

  @doc """
  The most recent **superseded** entry for a key, or `nil`.

  This is what ADR-0032 §6 renders — labelled with its as-of and marked as
  recomputing — instead of a skeleton. It is deliberately only one generation
  deep: older than that is not "the last thing you saw", it is archaeology.
  """
  @spec previous(integer(), term(), Date.t()) :: term() | nil
  def previous(portfolio_id, scope_key, %Date{} = today) do
    if enabled?() and table?() do
      lookup(portfolio_id, scope_key, today, version(portfolio_id) - 1)
    end
  end

  @doc """
  Drops the memo of the given portfolios, or of every portfolio for `:all`.

  `:all` is not an emergency lever — it is the ordinary result of a write whose
  blast radius cannot be proven narrower (ADR-0032 §3.3).
  """
  @spec invalidate(:all | [integer()]) :: :ok
  def invalidate(target)

  def invalidate(:all) do
    if table?(), do: GenServer.call(__MODULE__, :invalidate_all), else: :ok
  end

  def invalidate(portfolio_ids) when is_list(portfolio_ids) do
    if table?() and portfolio_ids != [] do
      GenServer.call(__MODULE__, {:invalidate, Enum.uniq(portfolio_ids)})
    else
      :ok
    end
  end

  @doc "Empties the memo. For tests and for the disabled path's own coverage."
  @spec reset() :: :ok
  def reset do
    if table?(), do: GenServer.call(__MODULE__, :reset), else: :ok
  end

  @doc "The current data version of a portfolio; `0` before its first write."
  @spec version(integer()) :: integer()
  def version(portfolio_id) do
    case :ets.lookup(@table, {@version_prefix, portfolio_id}) do
      [{_key, version}] -> version
      [] -> 0
    end
  end

  # -- server ----------------------------------------------------------------

  @impl true
  def init(_opts) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    {:ok, %{}}
  end

  @impl true
  def handle_call({:invalidate, portfolio_ids}, _from, state) do
    Enum.each(portfolio_ids, &bump/1)
    {:reply, :ok, state}
  end

  def handle_call(:invalidate_all, _from, state) do
    # Both sources matter: a portfolio memoised but never yet invalidated has
    # entry rows and no version row, so matching version rows alone would miss
    # exactly the portfolios that have something to invalidate.
    versioned = :ets.match(@table, {{@version_prefix, :"$1"}, :_})
    memoised = :ets.match(@table, {{:"$1", :_, :_, :_}, :_})

    (versioned ++ memoised)
    |> Enum.map(fn [portfolio_id] -> portfolio_id end)
    |> Enum.uniq()
    |> Enum.each(&bump/1)

    {:reply, :ok, state}
  end

  def handle_call(:reset, _from, state) do
    :ets.delete_all_objects(@table)
    {:reply, :ok, state}
  end

  # -- internals -------------------------------------------------------------

  defp memoised(portfolio_id, scope_key, today, compute) do
    version = version(portfolio_id)

    case lookup(portfolio_id, scope_key, today, version) do
      nil ->
        analysis = compute.()
        :ets.insert(@table, {key(portfolio_id, scope_key, today, version), analysis})
        analysis

      analysis ->
        analysis
    end
  end

  defp lookup(_portfolio_id, _scope_key, _today, version) when version < 0, do: nil

  defp lookup(portfolio_id, scope_key, today, version) do
    case :ets.lookup(@table, key(portfolio_id, scope_key, today, version)) do
      [{_key, analysis}] -> analysis
      [] -> nil
    end
  end

  defp key(portfolio_id, scope_key, today, version),
    do: {portfolio_id, scope_key, today, version}

  # Bumping is what invalidates: entries of older versions can never be read as
  # current again. The sweep then drops everything but the generation §6 still
  # needs.
  defp bump(portfolio_id) do
    version = :ets.update_counter(@table, {@version_prefix, portfolio_id}, 1, {nil, 0})
    sweep(portfolio_id, version)
    :ok
  end

  defp sweep(portfolio_id, version) do
    :ets.select_delete(@table, [
      {{{portfolio_id, :_, :_, :"$1"}, :_}, [{:<, :"$1", version - 1}], [true]}
    ])
  end

  defp table?, do: :ets.whereis(@table) != :undefined
end
