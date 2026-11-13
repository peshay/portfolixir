defmodule Portfolixir.Chains.Reader do
  @moduledoc """
  The chain reader (ADR-0059 §5, §6, §7, §8, §10): the run that stores what
  `Portfolixir.Chains.Esplora` read, and the supervised process that starts
  it every 6 hours.

  ## The run (`run/2`)

  **A bound security is the opt-in** (§10). With no security bound to the
  chain the run asks no host and stores nothing (`{:ok, :unbound}`). A chain
  without a source (§2) answers `{:error, :no_source}`.

  **What is asked** (§3): the tip, then the hash and block of every halving
  *k* × the chain's interval at or below the tip that is not yet stored as
  confirmed on every bound security, of the tip and of tip − 2,016. **A
  confirmed halving is never read again** (§5). The stored tip and its
  block's time are handed to the adapter, so a source more than 6 blocks
  behind it, or further ahead of it than the time since its block allows,
  is refused, and the genesis check is due once a day per source (§7).

  **What is written**, for every security bound to the chain, through
  `Portfolixir.Knowledge.Events.put_chain_halving/6` under the system job
  `chain_read` (the one writer of `halving` events on a chain with a source,
  ADR-0048's amendment, item 4; registered in B5), each write journaled:

    * **a past halving** (§5): `timing: exact`, the **UTC date** of the
      block's timestamp, `source_url` `{base}/block/{hash}` of the source
      that answered, `checked_at` the day it was read, `machine_generated:
      false`; **confirmed and `primary`** once the tip is at least its height
      + 5 (six confirmations), otherwise unconfirmed and `unverified`. A row
      stored as confirmed is never written again;
    * **the next halving** (§6), the first *k* × the interval above the tip:
      an unconfirmed `window`, `unverified`, between the tip's timestamp +
      the remaining blocks × the mean block time of the last 2,016 blocks
      and the tip's timestamp + the remaining blocks × the target spacing;
      `date` the earlier, `date_end` the later UTC date, its basis in the
      one-line `note`. Integer arithmetic and `Decimal` division, no float.
      **Written at most once a day**: a row whose `checked_at` is the run's
      day is left as it is.

  **Failure behaviour** (§7). When every source fails, the run records the
  failures in the state row's `last_error` and its `last_tried_at`, and
  **changes nothing else**: the last estimate stands with its `checked_at`.

  **Two runs never write twice** (the scheduled run and an on-demand
  refresh). The writes and the state row take a transaction-scoped advisory
  lock per chain (`Portfolixir.LockTable`, row 24) before they read what
  is stored, so the later run finds the earlier one's rows: a confirmed
  halving is skipped and the day's estimate is left. The network reads lie
  outside the lock and its transaction. **A rebinding during a run**: the
  bound securities are read again under the lock, each held `FOR SHARE`
  ahead of its events (the order a rebinding takes too, security then
  events), so a rebinding either commits first and the run leaves that
  security out, or waits for the run and then deletes the halvings it
  wrote (ADR-0059 §4). A write the binding still refuses
  (`:binding_changed`) or any other refused write rolls the run's writes
  back and is recorded as `write_failed`.

  ## Health (§8)

  `state/1` is the chain's state row (`Portfolixir.Chains.ChainRead`), and
  `stale?/2` is true when the chain has had no successful run for 24 hours,
  counted from its first try when it never had one.

  ## The process (§10)

  **Where it runs:** exactly where the quote sync runs; the supervision tree
  hands it the quote sync's `enabled?` (production; development with
  `PORTFOLIXIR_BACKGROUND_FETCH`; never in tests), so there is no second
  switch. The first tick a minute after boot, then every 6 hours; each tick
  runs every chain with a source in its own task under
  `Portfolixir.Chains.Tasks`, apart from the quote sync and the news
  fetcher, so a failing chain stops nothing else. A tick that finds the last
  run still going skips.
  """

  use GenServer
  require Logger

  import Ecto.Query

  alias Portfolixir.Actor
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Chains.ChainRead
  alias Portfolixir.Chains.Esplora
  alias Portfolixir.Chains.Registry
  alias Portfolixir.Clock
  alias Portfolixir.Input.Text
  alias Portfolixir.Knowledge.Events
  alias Portfolixir.Knowledge.SecurityEvent
  alias Portfolixir.Repo

  @interval_ms 6 * 60 * 60 * 1000
  @first_tick_ms 60 * 1000
  @stale_seconds 24 * 60 * 60
  # Six confirmations: the tip at least the block's height + 5 (§5).
  @confirmation_depth 5
  # One difficulty period: the span of the recent mean block time (§6).
  @period 2016
  @max_error 512

  # The first key of the chain-read lock (`pg_advisory_xact_lock(int, int)`)
  # plus the chain's place in the registry, distinct from the app's other
  # advisory locks; the second is 0 unless the transaction has set
  # `portfolixir.chain_read_lock_scope`, which only the test sandbox does
  # (a sandboxed test never commits, so it would hold the lock until it
  # ended and every other async test's run would wait). `LockTable`, row 24.
  @lock_key 727_229_059
  @lock_sql """
  SELECT pg_advisory_xact_lock($1,
    coalesce(nullif(current_setting('portfolixir.chain_read_lock_scope', true), '')::integer, 0))
  /* chain read */
  """

  @type summary :: %{
          chain: Registry.chain(),
          host: String.t(),
          tip: non_neg_integer(),
          securities: non_neg_integer()
        }

  # -- the run -----------------------------------------------------------------

  @doc """
  One run for `chain`; see the moduledoc. Answers `{:ok, summary}` (the
  host that answered, the tip and the number of securities written for),
  `{:ok, :unbound}`, `{:error, :no_source}`, `{:error, failures}` when every
  source failed (`Esplora.read/2`'s failures), or `{:error, {:write_failed,
  reason}}`.

  Options: `:now` (the server's clock, `DateTime.utc_now/0` by default) and
  `:read` (the adapter's read, `&Esplora.read/2` by default; a test hands a
  canned reading).
  """
  @spec run(Registry.chain(), keyword()) ::
          {:ok, summary() | :unbound}
          | {:error, :no_source | [Esplora.failure()] | {:write_failed, term()}}
  def run(chain, opts \\ []) do
    {:ok, chain} = Registry.fetch(chain)
    now = opts |> Keyword.get_lazy(:now, &DateTime.utc_now/0) |> DateTime.truncate(:second)
    read = Keyword.get(opts, :read, &Esplora.read/2)

    cond do
      not Registry.has_source?(chain) -> {:error, :no_source}
      bound(chain) == [] -> {:ok, :unbound}
      true -> read_and_store(chain, read, now)
    end
  end

  defp read_and_store(chain, read, now) do
    state = state(chain)
    today = Clock.local_date(now)
    interval = Registry.halving_interval(chain)
    stored = confirmed_on_every_bound(chain)

    heights_for = fn tip ->
      past = for k <- 1..div(tip, interval)//1, (k * interval) not in stored, do: k * interval
      past ++ [tip, tip - @period]
    end

    reading =
      read.(heights_for,
        last_tip: state && state.tip_height,
        last_tip_at: state && state.tip_at,
        genesis_due?: &genesis_due?(state, today, &1),
        now: now
      )

    case reading do
      {:ok, reading} ->
        case store(chain, reading, now, today) do
          {:ok, summary} ->
            {:ok, summary}

          {:error, reason} ->
            record_failure(chain, now, "write_failed: " <> inspect(reason))
            {:error, {:write_failed, reason}}
        end

      {:error, failures} ->
        record_failure(chain, now, Enum.map_join(failures, "; ", &failure_text/1))
        {:error, failures}
    end
  end

  # The heights stored as a confirmed halving on every security bound to
  # `chain` now: those are not asked again.
  defp confirmed_on_every_bound(chain) do
    bound = bound(chain)

    from(e in SecurityEvent,
      where: e.kind == :halving and e.confirmed == true and e.security_id in ^bound,
      group_by: e.chain_height,
      having: count(e.id) == ^length(bound),
      select: e.chain_height
    )
    |> Repo.all()
    |> MapSet.new()
  end

  defp bound(chain) do
    Repo.all(from(s in Security, where: s.halving_chain == ^chain, order_by: s.id, select: s.id))
  end

  defp genesis_due?(nil, _today, _host), do: true

  defp genesis_due?(%ChainRead{} = state, today, host),
    do: state.genesis_checked_on != today or state.genesis_checked_host != host

  defp failure_text(%{host: host, source: source, error: error}),
    do: "#{host || source}: #{error}"

  # -- the writes, under the chain's lock ----------------------------------------

  defp store(chain, reading, now, today) do
    Repo.transaction(fn ->
      lock!(chain)
      securities = lock_bound(chain)
      stored = stored_halvings(securities)
      actor = Actor.system_job("chain_read")

      writes =
        past_writes(chain, reading, securities, stored, today) ++
          estimate_writes(chain, reading, securities, stored, today)

      Enum.each(writes, fn {security_id, height, attrs} ->
        case Events.put_chain_halving(actor, security_id, chain, height, attrs, today: today) do
          {:ok, _event} -> :ok
          {:error, reason} -> Repo.rollback(write_error(reason))
        end
      end)

      record_ok(chain, reading, now, today)

      %{chain: chain, host: reading.host, tip: reading.tip, securities: length(securities)}
    end)
  end

  defp write_error(%Ecto.Changeset{errors: errors}), do: {:invalid, Keyword.keys(errors)}
  defp write_error(reason), do: reason

  defp lock!(chain) do
    index = Enum.find_index(Registry.chains(), &(&1 == chain))
    Repo.query!(@lock_sql, [@lock_key + index])
  end

  # The bound securities read again under the lock, each held FOR SHARE
  # ahead of its events: a rebinding commits first or waits for this run.
  defp lock_bound(chain) do
    Repo.all(
      from(s in Security,
        where: s.halving_chain == ^chain,
        order_by: s.id,
        lock: "FOR SHARE",
        select: s.id
      )
    )
  end

  defp stored_halvings(securities) do
    from(e in SecurityEvent, where: e.kind == :halving and e.security_id in ^securities)
    |> Repo.all()
    |> Map.new(&{{&1.security_id, &1.chain_height}, &1})
  end

  # §5: every halving at or below the tip whose block this run read, on
  # every bound security that does not hold it confirmed.
  defp past_writes(chain, reading, securities, stored, today) do
    interval = Registry.halving_interval(chain)

    for {height, block} <- Enum.sort(reading.blocks),
        height > 0 and rem(height, interval) == 0,
        security_id <- securities,
        not match?(%SecurityEvent{confirmed: true}, stored[{security_id, height}]),
        do: {security_id, height, block_attrs(reading, block, today)}
  end

  defp block_attrs(reading, block, today) do
    confirmed? = reading.tip >= block.height + @confirmation_depth

    %{
      date: utc_date(block.timestamp),
      date_end: nil,
      timing: :exact,
      confirmed: confirmed?,
      source_quality: if(confirmed?, do: :primary, else: :unverified),
      source_url: block_url(reading, block),
      checked_at: today,
      note: nil,
      machine_generated: false
    }
  end

  # §6: the next halving's window, on every bound security whose row was not
  # written today.
  defp estimate_writes(chain, reading, securities, stored, today) do
    interval = Registry.halving_interval(chain)
    next = (div(reading.tip, interval) + 1) * interval
    attrs = estimate_attrs(chain, reading, next, today)

    for security_id <- securities,
        not written_on?(stored[{security_id, next}], today),
        do: {security_id, next, attrs}
  end

  defp written_on?(%SecurityEvent{checked_at: day}, today), do: day == today
  defp written_on?(nil, _today), do: false

  defp estimate_attrs(chain, reading, next, today) do
    tip = reading.blocks[reading.tip]
    earlier = reading.blocks[reading.tip - @period]
    spacing = Registry.target_spacing(chain)
    remaining = next - reading.tip
    span = tip.timestamp - earlier.timestamp
    mean = Decimal.div(span, @period)

    at_recent =
      tip.timestamp +
        (Decimal.div(remaining * span, @period)
         |> Decimal.round(0, :half_up)
         |> Decimal.to_integer())

    at_target = tip.timestamp + remaining * spacing
    [first, last] = Enum.sort([utc_date(at_recent), utc_date(at_target)], Date)

    note =
      "Halving #{next} from tip #{reading.tip} (#{utc_time(tip.timestamp)}) and block " <>
        "#{earlier.height} (#{utc_time(earlier.timestamp)}): mean " <>
        "#{Decimal.to_string(Decimal.round(mean, 2), :normal)} s a block over the last " <>
        "#{@period} blocks, #{remaining} blocks to go; #{utc_date(at_recent)} at that rate, " <>
        "#{utc_date(at_target)} at the #{spacing} s target (UTC)."

    %{
      date: first,
      date_end: last,
      timing: :window,
      confirmed: false,
      source_quality: :unverified,
      source_url: block_url(reading, tip),
      checked_at: today,
      note: note,
      machine_generated: false
    }
  end

  defp block_url(reading, block), do: reading.base <> "/block/" <> block.hash

  # The block's timestamp is UTC; no time zone conversion is ever applied (§5).
  defp utc_date(unix), do: unix |> DateTime.from_unix!() |> DateTime.to_date()
  defp utc_time(unix), do: unix |> DateTime.from_unix!() |> DateTime.to_iso8601()

  # -- the state row -------------------------------------------------------------

  @doc "The state row of `chain`, or `nil` before its first run."
  @spec state(Registry.chain()) :: ChainRead.t() | nil
  def state(chain) do
    {:ok, chain} = Registry.fetch(chain)
    Repo.get_by(ChainRead, chain: Atom.to_string(chain))
  end

  @doc """
  Whether a chain's source reads as dead at `now` (§8): no successful run
  for 24 hours or more, counted from the first try when there never was
  one. A chain never tried (`nil`) is not stale.
  """
  @spec stale?(ChainRead.t() | nil, DateTime.t()) :: boolean()
  def stale?(nil, %DateTime{}), do: false

  def stale?(%ChainRead{last_ok_at: ok_at, inserted_at: first_try}, %DateTime{} = now),
    do: DateTime.diff(now, ok_at || first_try, :second) >= @stale_seconds

  defp record_ok(chain, reading, now, today) do
    genesis =
      if reading.genesis_checked,
        do: %{genesis_checked_on: today, genesis_checked_host: reading.host},
        else: %{}

    fields =
      Map.merge(
        %{
          source_host: reading.host,
          last_tried_at: now,
          last_ok_at: now,
          last_error: nil,
          tip_height: reading.tip,
          tip_at: DateTime.from_unix!(reading.blocks[reading.tip].timestamp),
          tip_2016_at: DateTime.from_unix!(reading.blocks[reading.tip - @period].timestamp)
        },
        genesis
      )

    upsert!(chain, now, fields)
  end

  defp record_failure(chain, now, error) do
    Repo.transaction(fn ->
      lock!(chain)
      upsert!(chain, now, %{last_tried_at: now, last_error: error_text(error)})
    end)

    Logger.warning("chain read #{chain}: #{error}")
  end

  # The error as the state row stores it: one line of visible text within
  # its column, whatever a source or an exception put into it (a control
  # character a space, an invisible one spelled `[U+XXXX]`).
  defp error_text(error) do
    error
    |> String.replace_invalid()
    |> String.replace(~r/[\x{0}-\x{1F}\x{7F}-\x{9F}\x{2028}\x{2029}]/u, " ")
    |> Text.escape_invisible()
    |> String.slice(0, @max_error)
  end

  defp upsert!(chain, now, fields) do
    row =
      ChainRead.changeset(
        %ChainRead{inserted_at: now},
        Map.put(fields, :chain, Atom.to_string(chain))
      )

    Repo.insert!(row,
      on_conflict: {:replace, Map.keys(fields) ++ [:updated_at]},
      conflict_target: :chain
    )
  end

  # -- the process ---------------------------------------------------------------

  @doc "The time between two scheduled runs: 6 hours."
  @spec interval_ms() :: pos_integer()
  def interval_ms, do: @interval_ms

  @doc """
  Starts the reader. Options: `:enabled?` (default false), `:interval_ms`,
  `:first_tick_ms`, `:run_opts` (passed to every run), `:name` (nil for an
  unnamed one).
  """
  def start_link(opts) do
    case Keyword.get(opts, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @doc """
  Runs every chain with a source once (`run/2`), each guarded so that a
  raise stays that chain's; `[{chain, result}]`.
  """
  @spec run_all(keyword()) :: [{Registry.chain(), term()}]
  def run_all(opts \\ []) do
    for chain <- Registry.chains(), Registry.has_source?(chain) do
      {chain, guarded(chain, opts)}
    end
  end

  defp guarded(chain, opts) do
    run(chain, opts)
  rescue
    exception ->
      Logger.warning("chain read #{chain} raised: #{Exception.message(exception)}")
      {:error, :crashed}
  end

  @impl true
  def init(opts) do
    state = %{
      enabled?: Keyword.get(opts, :enabled?, false),
      interval_ms: Keyword.get(opts, :interval_ms, @interval_ms),
      run_opts: Keyword.get(opts, :run_opts, []),
      running: nil
    }

    if state.enabled?, do: schedule_tick(Keyword.get(opts, :first_tick_ms, @first_tick_ms))
    {:ok, state}
  end

  @impl true
  def handle_info(:tick, %{running: nil} = state) do
    run_opts = state.run_opts
    task = Task.Supervisor.async_nolink(Portfolixir.Chains.Tasks, fn -> run_all(run_opts) end)
    schedule_tick(state.interval_ms)
    {:noreply, %{state | running: task.ref}}
  end

  # The last run is still going: this tick skips.
  def handle_info(:tick, state) do
    schedule_tick(state.interval_ms)
    {:noreply, state}
  end

  def handle_info({ref, _results}, %{running: ref} = state) do
    Process.demonitor(ref, [:flush])
    {:noreply, %{state | running: nil}}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{running: ref} = state) do
    Logger.warning("chain reader run ended: #{inspect(reason)}")
    {:noreply, %{state | running: nil}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp schedule_tick(ms), do: Process.send_after(self(), :tick, ms)
end
