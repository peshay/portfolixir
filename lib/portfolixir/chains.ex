defmodule Portfolixir.Chains do
  @moduledoc """
  The chains' reads and the on-demand refresh (FR-58,
  [ADR-0059](../../docs/decisions/0059-chain-source-block-heights-and-times-for-halvings.md)
  §8, §11), behind `GET /api/v1/chains`, `POST /api/v1/chains/:chain/refresh`
  and the cycles read's `chain_source`.

  ## The list (`list/1`)

  The registry's chains (`Portfolixir.Chains.Registry`) in its order, each
  with its protocol constants, whether the app reads it itself and how many
  securities are bound to it. **For a chain with a source**, its health of
  §8 from the state row (`Portfolixir.Chains.ChainRead`): the host that last
  answered, the last try, the last success, the last error and `stale` (no
  successful run for 24 hours, `Reader.stale?/2`); the inputs of the next
  halving's estimate (§6): the tip, its block's time, the time 2,016 blocks
  below and their mean in seconds; and when the next on-demand refresh is
  allowed. A chain without a source has none of the three.

  ## The refresh (`refresh/2`)

  One run of `Portfolixir.Chains.Reader.run/2`, **synchronous**, answering
  the chain's entry with the run's outcome. **Throttled to once per 10
  minutes per chain**, counted from the state row's `last_tried_at`, which
  every run that asked a host stamps, the scheduled ones too: sooner answers
  `{:error, {:too_soon, seconds}}`, the seconds until ten minutes after the
  last try (at most 600, also when the stored try lies after `now`). A run
  with no security bound asks no host and stamps nothing, so it starts no
  wait. A chain without a source answers `{:error, :no_source}`, a name the
  registry does not hold `{:error, :not_found}`; neither asks a host.

  Two refreshes sent in the same instant can both pass the check; the
  reader's lock per chain (`Reader`, "Two runs never write twice") keeps the
  second from writing anything the first wrote.
  """

  import Ecto.Query

  alias Portfolixir.Catalog.Security
  alias Portfolixir.Chains.ChainRead
  alias Portfolixir.Chains.Esplora
  alias Portfolixir.Chains.Reader
  alias Portfolixir.Chains.Registry
  alias Portfolixir.Repo

  @refresh_seconds 600
  # One difficulty period: the span of the recent mean block time (§6).
  @period 2016

  @typedoc "A run's outcome as the refresh answers it."
  @type run ::
          %{status: :ok, host: String.t(), tip: non_neg_integer(), securities: non_neg_integer()}
          | %{status: :unbound}
          | %{status: :failed, error: String.t() | nil}

  @doc "The seconds a chain waits between two runs on demand: 600."
  @spec refresh_seconds() :: pos_integer()
  def refresh_seconds, do: @refresh_seconds

  @doc "Every registered chain's entry at `now` (see the moduledoc)."
  @spec list(DateTime.t()) :: [map()]
  def list(%DateTime{} = now \\ DateTime.utc_now()) do
    bound = bound_counts()
    Enum.map(Registry.chains(), &entry(&1, Map.get(bound, &1, 0), now))
  end

  @doc """
  The health of `chain`'s source at `now`, as `list/1` states it, with the
  chain's name and `has_source` — `chain_source` in the cycles read
  (ADR-0059 §8). A chain without a source answers `has_source: false` and
  nothing else.
  """
  @spec source_health(Registry.chain(), DateTime.t()) :: map()
  def source_health(chain, %DateTime{} = now \\ DateTime.utc_now()) do
    {:ok, chain} = Registry.fetch(chain)
    name = Atom.to_string(chain)

    if Registry.has_source?(chain),
      do: chain |> Reader.state() |> health(now) |> Map.merge(%{chain: name, has_source: true}),
      else: %{chain: name, has_source: false}
  end

  @doc """
  The hosts `chain`'s source asks, in order, and whether they are the
  operator's own URL (`Portfolixir.Chains.Esplora.hosts/0`); `nil` for a
  chain without a source. The chart's health line reads it to name a
  fallback and a refused own URL (Sprint 29 H7, ADR-0059 §8).
  """
  @spec source_hosts(Registry.chain()) :: %{own?: boolean(), hosts: [String.t() | nil]} | nil
  def source_hosts(chain) do
    {:ok, chain} = Registry.fetch(chain)
    if Registry.has_source?(chain), do: Esplora.hosts()
  end

  @doc """
  One on-demand run of the chain named `name` (a registry name or atom);
  see the moduledoc. Options: `:now` (the server's clock,
  `DateTime.utc_now/0` by default) and `:read`, handed to `Reader.run/2`.

  `{:ok, entry}` with `entry.run` the outcome, `{:error, {:too_soon,
  seconds}}`, `{:error, :no_source}` or `{:error, :not_found}`.
  """
  @spec refresh(term(), keyword()) ::
          {:ok, map()} | {:error, :not_found | :no_source | {:too_soon, pos_integer()}}
  def refresh(name, opts \\ []) do
    now = opts |> Keyword.get_lazy(:now, &DateTime.utc_now/0) |> DateTime.truncate(:second)

    with {:ok, chain} <- fetch(name),
         :ok <- source(chain),
         :ok <- due(Reader.state(chain), now) do
      run = chain |> Reader.run(Keyword.put(opts, :now, now)) |> outcome(chain)
      {:ok, chain |> entry(bound_count(chain), now) |> Map.put(:run, run)}
    end
  end

  defp fetch(name) do
    case Registry.fetch(name) do
      {:ok, chain} -> {:ok, chain}
      :error -> {:error, :not_found}
    end
  end

  defp source(chain),
    do: if(Registry.has_source?(chain), do: :ok, else: {:error, :no_source})

  defp due(%ChainRead{last_tried_at: %DateTime{} = tried}, now) do
    case @refresh_seconds - DateTime.diff(now, tried, :second) do
      wait when wait > 0 -> {:error, {:too_soon, min(wait, @refresh_seconds)}}
      _due -> :ok
    end
  end

  defp due(_never_tried, _now), do: :ok

  defp outcome({:ok, :unbound}, _chain), do: %{status: :unbound}

  defp outcome({:ok, %{host: host, tip: tip, securities: securities}}, _chain),
    do: %{status: :ok, host: host, tip: tip, securities: securities}

  # Every source failed, or the writes were refused: the state row holds the
  # error the run recorded.
  defp outcome({:error, _reason}, chain),
    do: %{status: :failed, error: chain |> Reader.state() |> then(&(&1 && &1.last_error))}

  defp entry(chain, bound, now) do
    base = %{
      chain: Atom.to_string(chain),
      halving_interval: Registry.halving_interval(chain),
      target_spacing_seconds: Registry.target_spacing(chain),
      has_source: Registry.has_source?(chain),
      bound_securities: bound
    }

    if Registry.has_source?(chain) do
      state = Reader.state(chain)

      Map.merge(base, %{
        health: health(state, now),
        next_halving_inputs: inputs(state),
        refresh: %{
          interval_seconds: @refresh_seconds,
          available_at: state && state.last_tried_at && available_at(state.last_tried_at, now)
        }
      })
    else
      Map.merge(base, %{health: nil, next_halving_inputs: nil, refresh: nil})
    end
  end

  defp health(state, now) do
    %{
      source_host: state && state.source_host,
      last_tried_at: state && state.last_tried_at,
      last_ok_at: state && state.last_ok_at,
      last_error: state && state.last_error,
      stale: Reader.stale?(state, now)
    }
  end

  # A try stamped after `now` still waits ten minutes at most (`due/2`).
  defp available_at(tried, now) do
    at = DateTime.add(tried, @refresh_seconds)
    latest = DateTime.add(now, @refresh_seconds)
    if DateTime.compare(at, latest) == :gt, do: latest, else: at
  end

  defp inputs(%ChainRead{
         tip_height: tip,
         tip_at: %DateTime{} = at,
         tip_2016_at: %DateTime{} = early
       })
       when is_integer(tip) do
    %{
      tip_height: tip,
      tip_at: at,
      tip_2016_at: early,
      period_blocks: @period,
      mean_block_seconds:
        at |> DateTime.diff(early, :second) |> Decimal.div(@period) |> Decimal.round(2)
    }
  end

  defp inputs(_state), do: nil

  defp bound_counts do
    from(s in Security,
      where: not is_nil(s.halving_chain),
      group_by: s.halving_chain,
      select: {s.halving_chain, count(s.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp bound_count(chain),
    do: Repo.one(from(s in Security, where: s.halving_chain == ^chain, select: count(s.id)))
end
