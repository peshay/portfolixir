defmodule Portfolixir.Portfolios.Performance.DefaultPeriodWarmupTest do
  # The default period warmed in the background (I34 step 2, Sprint 31 P1,
  # plan D-12), with the derived layer ON: the test config keeps the layer,
  # the warm-up and the refresher off (ADR-0032 §7.3), so only this file's
  # tests start them, each under its own supervisor. The memo table is
  # global, hence async: false.
  use Portfolixir.DataCase, async: false

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Derived
  alias Portfolixir.Derived.Memo
  alias Portfolixir.Derived.Refresher
  alias Portfolixir.DerivedConfig
  alias Portfolixir.Portfolios.Performance.Bands
  alias Portfolixir.Portfolios.Performance.Contribution
  alias Portfolixir.Portfolios.Performance.Warmup

  @event [:portfolixir, :performance, :warmup, :default_period]

  setup do
    Memo.reset()
    on_exit(&Memo.reset/0)
    DerivedConfig.enable!(lifetimes: [])

    test_pid = self()
    handler = "default-period-warmup-#{inspect(test_pid)}"

    :ok =
      :telemetry.attach(
        handler,
        @event,
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:default_period, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    :ok
  end

  # -- the synthetic world ------------------------------------------------------
  #
  # Invented figures only, dated from today so the default period (one year)
  # holds them: one EUR portfolio, two securities, and one view beside the
  # Everything scope.
  defp world! do
    today = Date.utc_today()
    world = base_world(name: "Warm period", cash_name: "Cash", depot_name: "Depot")
    alpha = create_security!(name: "Alpha", ticker: "WPA")
    beta = create_security!(name: "Beta", ticker: "WPB")

    deposit!(world, "5000", Date.add(today, -300))
    buy!(world, alpha, quantity: "10", price: "100", date: Date.add(today, -300))
    buy!(world, beta, quantity: "20", price: "50", date: Date.add(today, -120))

    put_quotes!(alpha, [{Date.add(today, -300), "100"}, {Date.add(today, -30), "120"}])
    put_quotes!(beta, [{Date.add(today, -120), "50"}, {Date.add(today, -10), "45"}])

    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Warm view"})

    %{world: world, alpha: alpha, view: view, today: today}
  end

  # The request each screen opens with: the stack at „Kategorien €“ (the
  # value series' default, and the axis „ab 0“ reads) and the table, one
  # year, in the first portfolio's base currency.
  defp bands_opts, do: [period: "1y", base_currency: "EUR", level: :category]
  defp table_opts, do: [period: "1y", base_currency: "EUR"]

  defp bands_key(view_id, today),
    do:
      "view=#{view_id || "unscoped"}|base=EUR|today=#{today}|period=1y|level=category" <>
        "|sort=size|scale=value|category=none|classification=default"

  defp table_key(view_id, today),
    do: "view=#{view_id || "unscoped"}|base=EUR|today=#{today}|period=1y"

  defp peek(:bands, view_id, today),
    do: Derived.peek(:performance_view_bands, Derived.global_basis(), bands_key(view_id, today))

  defp peek(:table, view_id, today),
    do:
      Derived.peek(
        :performance_view_contribution,
        Derived.global_basis(),
        table_key(view_id, today)
      )

  defp fresh(:bands, view_id) do
    DerivedConfig.with_layer_off(fn ->
      {:ok, result} = Bands.for_view(view_id, bands_opts())
      result
    end)
  end

  defp fresh(:table, view_id) do
    DerivedConfig.with_layer_off(fn ->
      {:ok, result} = Contribution.for_view(view_id, table_opts())
      result
    end)
  end

  # Byte for byte, without `as_of` (the instant a walk was computed, which a
  # recomputation must move) and the table's `stale` flag (set outside the
  # memoised value, ADR-0039 C4).
  defp bytes(result),
    do: result |> Map.drop([:as_of, :stale]) |> :erlang.term_to_binary([:deterministic])

  defp entry_keys(analytic) do
    :ets.select(Memo, [{{{analytic, :_, :"$1", :_, :_}, :_, :_, :_}, [], [:"$1"]}])
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp start_warmup!(opts \\ []),
    do: start_supervised!({Warmup, Keyword.merge([enabled?: true], opts)})

  # User story (I34 step 2, Sprint 31 P1; plan D-12):
  # As the operator opening Wealth after a restart,
  # I want the chart and the table under it for one year, the period every
  # screen opens with, already computed for the Everything scope and for
  # each view,
  # so that the first paint does not wait for two windowed walks.
  #
  # Acceptance criteria:
  # - After boot, the warm-up fills the default period's bands (the stack at
  #   „Kategorien €“) and its contribution table for the Everything scope
  #   and every view, through the request path: each entry is a current
  #   hit, equal byte for byte to a read with the derived layer off.
  # - It warms nothing else of those analytics: no other period, level or
  #   scale (plan D-12, the memo's budget).
  # - It runs in the background: the warm-up process answers while it runs.
  test "after boot, the default period's bands and table are a hit for every scope" do
    w = world!()

    start_warmup!()
    assert_receive {:default_period, %{duration_ms: _}, %{outcome: :done, scopes: 2}}, 30_000

    for view_id <- [nil, w.view.id], read <- [:bands, :table] do
      assert {:fresh, warm} = peek(read, view_id, w.today),
             "#{read} for view #{inspect(view_id)} was not warmed"

      assert bytes(warm) == bytes(fresh(read, view_id)),
             "#{read} for view #{inspect(view_id)}: the warmed entry differs from a read"
    end

    assert entry_keys(:performance_view_bands) ==
             Enum.sort([bands_key(nil, w.today), bands_key(w.view.id, w.today)])

    assert entry_keys(:performance_view_contribution) ==
             Enum.sort([table_key(nil, w.today), table_key(w.view.id, w.today)])
  end

  # User story (I34 step 2, Sprint 31 P1; ADR-0039 §4, amendment §1):
  # As the operator who just booked something,
  # I want the warmed chart never to outlive my booking, and the default
  # period warmed again from the new books,
  # so that the next first paint is quick and shows the booking.
  #
  # Acceptance criteria:
  # - A write bumps the global basis: the warmed bands and table are no
  #   longer served as current (a peek finds only the superseded value).
  # - The refresher's re-warm of the global basis warms the default period
  #   again: the new entries are current hits, equal to a fresh read of the
  #   books after the write, and the bands differ from the warmed ones.
  test "a write bumps the basis: the warmed value is not served, and the re-warm happens" do
    w = world!()

    start_warmup!()
    assert_receive {:default_period, _measurements, %{outcome: :done}}, 30_000
    {:fresh, warmed} = peek(:bands, nil, w.today)

    start_supervised!({Refresher, quiet_ms: 300, refresh: &Warmup.warm_basis/1})

    buy!(w.world, w.alpha, quantity: "5", price: "110", date: Date.add(w.today, -20))

    for view_id <- [nil, w.view.id], read <- [:bands, :table] do
      refute match?({:fresh, _}, peek(read, view_id, w.today)),
             "#{read} for view #{inspect(view_id)}: the warmed value outlived the write"
    end

    assert_receive {:default_period, _measurements, %{outcome: :done, scopes: 2}}, 30_000

    for view_id <- [nil, w.view.id], read <- [:bands, :table] do
      assert {:fresh, rewarmed} = peek(read, view_id, w.today),
             "#{read} for view #{inspect(view_id)} was not warmed again after the write"

      assert bytes(rewarmed) == bytes(fresh(read, view_id))
    end

    {:fresh, rewarmed} = peek(:bands, nil, w.today)
    refute bytes(rewarmed) == bytes(warmed), "the re-warm served the books before the write"
  end

  # User story (I34 step 2, Sprint 31 P1; ADR-0032 §5):
  # As the operator whose page is waiting for a walk,
  # I want the warm-up to yield to my requests and stop when its work is
  # superseded,
  # so that it never stands between me and a figure.
  #
  # Acceptance criteria:
  # - Each read runs at low priority, in a worker under the heap cap.
  # - A second ask while a warm runs cancels it after its current read (no
  #   walk is killed mid-query) and starts one fresh warm, never two at once.
  # - A read that raises is skipped and the warm goes on.
  test "it runs at low priority, a newer ask cancels it, and a failing read is skipped" do
    w = world!()
    test_pid = self()

    reads = fn view_id, _base_currency ->
      send(test_pid, {:reading, view_id, self(), Process.info(self(), :priority)})

      receive do
        :go -> :ok
      end

      if view_id == w.view.id, do: raise("a synthetic failure")
    end

    start_warmup!(period_reads: reads)

    assert_receive {:reading, nil, first, {:priority, :low}}, 30_000
    Warmup.warm_default_period()
    # The ask is served before the read is let go: the cancel is in the
    # warm's mailbox when its first scope ends.
    _state = :sys.get_state(Warmup)
    send(first, :go)

    assert_receive {:default_period, _measurements, %{outcome: :cancelled, scopes: 1}}, 30_000

    # The fresh warm reads every scope; the failing one is logged and skipped.
    assert_receive {:reading, nil, second, {:priority, :low}}, 30_000
    refute second == first
    send(second, :go)
    assert_receive {:reading, view_id, third, {:priority, :low}}, 30_000
    assert view_id == w.view.id

    ExUnit.CaptureLog.capture_log(fn ->
      send(third, :go)
      assert_receive {:default_period, _measurements, %{outcome: :done, scopes: 2}}, 30_000
    end)

    refute_received {:reading, _view, _pid, _priority}
  end

  # User story (I34 step 2, Sprint 31 P1; PortfolixirWeb.CappedAsync's rule):
  # As the operator restarting the instance while it warms,
  # I want the warm to stop after the read it is in,
  # so that a shutdown never kills a walk in the middle of a query.
  #
  # Acceptance criteria:
  # - Stopping the warm-up while a read runs waits for that read, then the
  #   warm ends as cancelled, without reading the next scope.
  test "a shutdown lets the running read end, then stops the warm" do
    _w = world!()
    test_pid = self()

    reads = fn view_id, _base_currency ->
      send(test_pid, {:reading, view_id, self()})

      receive do
        :go -> :ok
      end
    end

    # Started outside the test's supervisor, so another process can stop it.
    {:ok, warmup} =
      GenServer.start(Warmup, [enabled?: true, period_reads: reads], name: Warmup)

    on_exit(fn -> if Process.alive?(warmup), do: GenServer.stop(warmup) end)
    assert_receive {:reading, nil, worker}, 30_000

    stopping = Task.async(fn -> GenServer.stop(warmup, :shutdown) end)
    refute Task.yield(stopping, 200), "the shutdown did not wait for the running read"
    send(worker, :go)

    assert Task.await(stopping) == :ok
    assert_receive {:default_period, _measurements, %{outcome: :cancelled, scopes: 1}}, 5_000
    refute_received {:reading, _view, _pid}
  end

  # User story (I34 step 2, plan D-12; ADR-0032 §7.3):
  # As the maintainer,
  # I want the default period's warm-up bounded by the memo's budget and
  # switched off with the derived layer,
  # so that warming never empties the memo a request filled, and "off"
  # stays one state.
  #
  # Acceptance criteria:
  # - With the memo past half its budget, no scope is read.
  # - With the derived layer off, the warm-up process does not start and an
  #   ask is a no-op.
  test "it stops at half the memo's budget, and the layer's switch turns it off" do
    _w = world!()
    test_pid = self()
    reads = fn view_id, _base -> send(test_pid, {:reading, view_id}) end

    configured = Application.get_env(:portfolixir, Derived)
    Application.put_env(:portfolixir, Derived, Keyword.put(configured, :memo_max_entries, 2))
    on_exit(fn -> Application.put_env(:portfolixir, Derived, configured) end)

    Memo.put({:test_filler, "global", "a", 1, 1}, :filler, DateTime.utc_now())

    start_warmup!(period_reads: reads)

    assert_receive {:default_period, _measurements, %{outcome: :over_budget, scopes: 0}},
                   30_000

    refute_received {:reading, _view}

    stop_supervised!(Warmup)
    Application.put_env(:portfolixir, Derived, Keyword.put(configured, :enabled?, false))

    assert Warmup.start_link(enabled?: true, period_reads: reads) == :ignore
    assert Warmup.warm_default_period() == :ok
    refute_receive {:reading, _view}, 100
  end
end
