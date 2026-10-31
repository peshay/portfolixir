defmodule PortfolixirWeb.SecuritiesSyncRearmTest do
  # "Sync prices" and "Retry logo lookup for all" are refused server-side
  # while a run is in flight, whatever the button's DOM state. Synthetic data
  # only; no network: quote fetches go to a gated test adapter, logo lookups
  # run into a Req `plug:` stub, and names resolve through
  # Portfolixir.Net.FakeResolver.
  use PortfolixirWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.LogoDiscovery
  alias Portfolixir.Catalog.QuoteSync
  alias Portfolixir.Catalog.Security

  @registered :securities_sync_rearm_test

  # A quote provider that tells the test about every fetch and then waits for
  # the test to let it answer, so the interleaving of two sweeps is the
  # test's to choose. A module, not the per-process Fake: the sync runs in a
  # Task the test's process dictionary does not reach.
  defmodule GatedAdapter do
    @moduledoc false
    @behaviour Portfolixir.Catalog.QuoteSync.Provider

    @impl true
    def id, do: :sync_rearm_gated

    @impl true
    def fetch(%Security{id: id}, _opts) do
      case Process.whereis(:securities_sync_rearm_test) do
        nil ->
          {:ok, []}

        test ->
          send(test, {:rearm_fetch, id, self()})

          receive do
            :go -> {:ok, []}
          after
            5_000 -> {:ok, []}
          end
      end
    end
  end

  setup do
    Process.register(self(), @registered)
    :ok
  end

  defp create_quoted_security!(name) do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: name,
        currency_code: "EUR",
        asset_class: "etf",
        provider: "portfolio_performance"
      })

    security
  end

  # The QuoteSync config keeps `enabled?: false` (so creating a security
  # queues no enrichment fetch); only the adapter map points at the gate.
  defp with_gated_adapter do
    config = Application.get_env(:portfolixir, QuoteSync, [])

    Application.put_env(
      :portfolixir,
      QuoteSync,
      Keyword.put(config, :adapter_for, %{"portfolio_performance" => GatedAdapter})
    )

    on_exit(fn -> Application.put_env(:portfolixir, QuoteSync, config) end)
  end

  defp next_fetch(timeout) do
    receive do
      {:rearm_fetch, id, pid} -> {id, pid}
    after
      timeout -> nil
    end
  end

  # Lets every waiting fetch answer and records each one, until no sweep
  # asks for another within the quiet period: the full list of provider
  # fetches the events caused from here on.
  defp release_and_record(acc) do
    case next_fetch(400) do
      nil ->
        Enum.reverse(acc)

      {id, pid} ->
        send(pid, :go)
        release_and_record([id | acc])
    end
  end

  # Waits until the page's monitored sync tasks are all gone, so no task
  # outlives the test (Portfolixir.LogNoise). Never raises: it runs in an
  # `after`, where a raise would hide the test's own failure.
  defp await_tasks(view, tries \\ 150)
  defp await_tasks(_view, 0), do: :gave_up

  defp await_tasks(view, tries) do
    tasks =
      try do
        :sys.get_state(view.pid).socket.assigns.watched_tasks
      catch
        :exit, _ -> %{}
      end

    if map_size(tasks) == 0 do
      :ok
    else
      Process.sleep(20)
      await_tasks(view, tries - 1)
    end
  end

  # One sweep is under way: it has answered for the first security and waits
  # on the second, and the page that started it shows the sync running.
  defp start_first_sweep(view) do
    render_click(view, "sync_now", %{})

    assert {first_id, first_pid} = next_fetch(2_000)
    send(first_pid, :go)
    assert {second_id, second_pid} = next_fetch(2_000)

    {first_id, second_id, second_pid}
  end

  describe "Sync prices (sync_now)" do
    setup do
      a = create_quoted_security!("Synthetic Alpha Index ETF")
      b = create_quoted_security!("Synthetic Beta Index ETF")
      with_gated_adapter()
      %{ids: Enum.sort([a.id, b.id])}
    end

    # User story (security review 2026-10-12, H39):
    # As the operator whose providers rate-limit this instance,
    # I want "Sync prices" refused by the server while the page's sync runs,
    # so that a pushed event cannot start another sweep of every security.
    #
    # Acceptance criteria:
    # - A second sync_now on the page while its sync runs fetches nothing
    #   more: every security is fetched once.
    test "a sync_now pushed while the page's catalog sync runs makes no further provider fetch",
         %{conn: conn, ids: ids} do
      {:ok, view, _html} = live(conn, "/securities")

      {fetched, busy?} =
        try do
          {first_id, second_id, second_pid} = start_first_sweep(view)

          # The page's only brake: the button is disabled in the DOM.
          busy? = has_element?(view, "button#sync-prices[disabled]")

          # A client pushes the event anyway, as any LiveView client can.
          render_click(view, "sync_now", %{})

          send(second_pid, :go)
          {[first_id, second_id | release_and_record([])], busy?}
        after
          # Whatever happened above, every blocked task answers and ends here.
          release_and_record([])
          await_tasks(view)
        end

      assert busy?, "precondition: the page showed the first sync as running"

      assert Enum.sort(fetched) == ids,
             "two sync_now events on one page (the second pushed while the page showed " <>
               "the sync running) made #{length(fetched)} provider fetches for " <>
               "#{length(ids)} securities: #{inspect(fetched)} — the second event started " <>
               "another full sweep instead of being refused"
    end

    # User story (security review 2026-10-12, H39; board 07 of
    # ux-design-2026-10-27):
    # As the operator with a second window open (or the scheduled sync
    # running),
    # I want a catalog sync to run once at a time across the instance, and
    # the refused one named,
    # so that two windows never sweep the providers twice.
    #
    # Acceptance criteria:
    # - A second page's sync_now while a catalog sync runs fetches nothing
    #   more, and that page says "A price sync of every security is already
    #   running; it was not started a second time."
    test "a second page's sync_now while a catalog sync runs makes no further provider fetch",
         %{conn: conn, ids: ids} do
      {:ok, view1, _html} = live(conn, "/securities")
      {:ok, view2, _html} = live(conn, "/securities")

      fetched =
        try do
          {first_id, second_id, second_pid} = start_first_sweep(view1)

          # A second tab (or a second client of an open UI) has no flag set
          # at all; its button is enabled.
          render_click(view2, "sync_now", %{})

          send(second_pid, :go)
          [first_id, second_id | release_and_record([])]
        after
          release_and_record([])
          await_tasks(view1)
          await_tasks(view2)
        end

      assert Enum.sort(fetched) == ids,
             "a sync_now from a second page while the first page's catalog sync ran made " <>
               "#{length(fetched)} provider fetches for #{length(ids)} securities: " <>
               "#{inspect(fetched)} — QuoteSync.sync_all has no catalog-wide single flight"

      assert render(view2) =~
               "A price sync of every security is already running; it was not started a second time."
    end
  end

  describe "Retry logo lookup for all (retry_missing_logos)" do
    @png_free_stub_status 404

    setup do
      prior_enabled = Application.get_env(:portfolixir, :enable_logo_discovery, false)
      prior_opts = Application.get_env(:portfolixir, :logo_discovery_opts, [])

      tmp =
        Path.join(
          System.tmp_dir!(),
          "sync-rearm-logos-#{System.unique_integer([:positive])}"
        )

      # Created while discovery is off, so creation queues nothing.
      Application.put_env(:portfolixir, :enable_logo_discovery, false)

      {:ok, security} =
        Catalog.create_security(Actor.owner_ui(), %{
          name: "Arbolia Inc.",
          currency_code: "USD",
          provider: "portfolio_performance",
          feed: "PORTFOLIO_PERFORMANCE"
        })

      test_pid = self()

      stub = [
        plug: fn conn ->
          send(test_pid, {:rearm_logo_request, conn.host, conn.request_path})
          Plug.Conn.send_resp(conn, @png_free_stub_status, "not found")
        end
      ]

      Application.put_env(:portfolixir, :enable_logo_discovery, true)
      Application.put_env(:portfolixir, :logo_discovery_opts, req: stub, storage_dir: tmp)

      on_exit(fn ->
        Application.put_env(:portfolixir, :enable_logo_discovery, prior_enabled)
        Application.put_env(:portfolixir, :logo_discovery_opts, prior_opts)
        File.rm_rf(tmp)
      end)

      %{security: security}
    end

    defp await_logo_queue_idle(tries \\ 150)
    defp await_logo_queue_idle(0), do: :gave_up

    defp await_logo_queue_idle(tries) do
      state = :sys.get_state(LogoDiscovery)

      if :queue.is_empty(state.queue) and not state.scheduled? do
        :ok
      else
        Process.sleep(20)
        await_logo_queue_idle(tries - 1)
      end
    end

    defp drain_logo_requests(acc \\ []) do
      receive do
        {:rearm_logo_request, host, path} -> drain_logo_requests([{host, path} | acc])
      after
        100 -> Enum.reverse(acc)
      end
    end

    # User story (security review 2026-10-12, H39):
    # As the operator whose logo providers rate-limit this instance,
    # I want "Retry logo lookup for all" refused while the page shows it
    # queued,
    # so that a pushed event cannot re-queue every lookup.
    #
    # Acceptance criteria:
    # - A second retry on the page sends no provider request, and the page
    #   keeps its result "Logo lookup queued for all securities without a
    #   logo."
    test "a retry pushed while the page shows the lookup queued sends no further provider request",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, "/securities?dq=missing_logo")
      assert has_element?(view, "button#retry-missing-logos")

      {first, busy?, second} =
        ExUnit.CaptureLog.with_log(fn ->
          render_click(view, "retry_missing_logos", %{})
          # The cast is in the queue's mailbox before render_click returns.
          :sys.get_state(LogoDiscovery)
          await_logo_queue_idle()
          first = drain_logo_requests()

          # The page's only brake: the button is disabled in the DOM.
          busy? = has_element?(view, "button#retry-missing-logos[disabled]")

          render_click(view, "retry_missing_logos", %{})
          :sys.get_state(LogoDiscovery)
          await_logo_queue_idle()
          second = drain_logo_requests()

          {first, busy?, second}
        end)
        |> elem(0)

      assert first != [], "precondition: the first retry looked the logo up (stubbed)"
      assert busy?, "precondition: the page showed the retry as queued"

      assert render(view) =~ "Logo lookup queued for all securities without a logo."

      assert second == [],
             "a second retry_missing_logos, pushed while the page showed the lookup " <>
               "queued, made the server send #{length(second)} more provider request(s) " <>
               "(the first sent #{length(first)}): #{inspect(second)}"
    end
  end

  describe "the server side, without a page" do
    setup do
      a = create_quoted_security!("Synthetic Gamma Index ETF")
      with_gated_adapter()
      %{id: a.id}
    end

    # User story (security review 2026-10-12, H39):
    # As the operator,
    # I want one catalog-wide price sync at a time, whoever starts it (a
    # page, a second window, the scheduled tick),
    # so that overlapping runs never sweep the providers twice.
    #
    # Acceptance criteria:
    # - While QuoteSync.sync_all/1 runs, a second call answers
    #   {:error, :sync_in_progress} at once and fetches nothing.
    # - Once the first has returned, a new sync runs.
    test "a catalog sync runs once at a time and a second is refused", %{id: id} do
      first = Task.async(fn -> QuoteSync.sync_all() end)

      try do
        assert {^id, pid} = next_fetch(2_000)
        assert QuoteSync.sync_all() == {:error, :sync_in_progress}
        assert next_fetch(200) == nil
        send(pid, :go)
        assert {:ok, %{ok: _}} = Task.await(first)
      after
        release_and_record([])
      end

      second = Task.async(fn -> QuoteSync.sync_all() end)
      assert {^id, pid} = next_fetch(2_000)
      send(pid, :go)
      assert {:ok, _} = Task.await(second)
    end

    # User story (security review 2026-10-12, H39):
    # As the operator,
    # I want a logo retry to do nothing while a drain is pending,
    # so that a retry never rescans and re-queues the catalog mid-drain.
    #
    # Acceptance criteria:
    # - With an item queued and its drain pending, a retry leaves the queue
    #   as it was; with the queue empty, a retry queues every missing logo.
    test "a logo retry is a no-op while a drain is pending" do
      prior = %{
        enabled: Application.get_env(:portfolixir, :enable_logo_discovery, false),
        drain: Application.get_env(:portfolixir, :logo_discovery_drain_ms)
      }

      Application.put_env(:portfolixir, :enable_logo_discovery, false)

      {:ok, missing} =
        Catalog.create_security(Actor.owner_ui(), %{
          name: "Kestrel Point AG",
          currency_code: "EUR",
          provider: "portfolio_performance",
          feed: "PORTFOLIO_PERFORMANCE",
          asset_class: "equity"
        })

      on_exit(fn ->
        Application.put_env(:portfolixir, :enable_logo_discovery, prior.enabled)

        if prior.drain,
          do: Application.put_env(:portfolixir, :logo_discovery_drain_ms, prior.drain),
          else: Application.delete_env(:portfolixir, :logo_discovery_drain_ms)
      end)

      # A drain that never comes due inside the test.
      Application.put_env(:portfolixir, :logo_discovery_drain_ms, :timer.hours(1))

      name = :sync_rearm_logo_discovery
      pid = start_supervised!({LogoDiscovery, name: name})
      Application.put_env(:portfolixir, :enable_logo_discovery, true)

      pending = -1
      LogoDiscovery.enqueue_security_ids([pending], name)
      LogoDiscovery.retry_missing_security_logos(name)

      state = :sys.get_state(pid)
      assert :queue.to_list(state.queue) == [pending]
      assert state.scheduled?

      # With nothing pending, the retry queues the missing logo.
      :sys.replace_state(pid, fn s ->
        %{s | queue: :queue.new(), queued: MapSet.new(), scheduled?: false}
      end)

      LogoDiscovery.retry_missing_security_logos(name)
      assert missing.id in :queue.to_list(:sys.get_state(pid).queue)
    end
  end
end
