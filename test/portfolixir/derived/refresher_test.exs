defmodule Portfolixir.Derived.RefresherTest do
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Application, as: PortfolixirApplication
  alias Portfolixir.Derived
  alias Portfolixir.Derived.DataVersion
  alias Portfolixir.Derived.Memo
  alias Portfolixir.Derived.Refresher
  alias Portfolixir.DerivedConfig
  alias Portfolixir.Imports
  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Performance.Warmup

  @fixtures Path.expand("../../support/fixtures/portfolio_performance", __DIR__)

  setup do
    Memo.reset()
    # `lifetimes: []` keeps the registry defaults this file was written
    # against, independent of what config.exs activates.
    DerivedConfig.enable!(lifetimes: [])
    :ok
  end

  # The refresher never touches the repo in these tests: the injected refresh
  # function only reports which basis it was asked to re-materialize. What is
  # under test is the scheduling — how many refreshes a burst of writes buys —
  # not what a refresh computes, which is `Warmup.warm_basis/1`'s own test.
  defp start_refresher!(opts \\ []) do
    test_pid = self()

    defaults = [
      quiet_ms: 200,
      max_delay_ms: 5_000,
      refresh: fn basis -> send(test_pid, {:refreshed, basis}) end
    ]

    start_supervised!({Refresher, Keyword.merge(defaults, opts)})
  end

  defp portfolio!(name) do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: name,
        base_currency_code: "EUR"
      })

    portfolio
  end

  # User story (#710, ADR-0039 amendment §§1-2):
  # As a local portfolio maintainer,
  # I want the figures I wait on to be recomputed by the write that
  # invalidated them rather than by the next page I open,
  # so that opening a page after a booking shows a number instead of a
  # "computing" cue.
  #
  # Acceptance criteria (§2, the load-bearing part):
  # - Importing a large export produces ONE refresh per affected basis, not
  #   one per row.
  # - A bump arriving while a refresh runs re-queues the basis exactly once.
  # - The queued unit is a basis, so the work does not grow per write.
  test "a Portfolio Performance import produces one refresh per affected basis, not one per row" do
    start_refresher!()
    portfolio = portfolio!("Import target")

    {:ok, preview} =
      PortfolioPerformance.parse(File.read!(Path.join(@fixtures, "sample.json")),
        filename: "sample.json"
      )

    # 13 entries plus the securities, cash accounts and depots the import
    # creates — every one of them a journaled write that bumps the version.
    assert {:ok, result} = Imports.apply(preview, %{portfolio_id: portfolio.id})
    assert result.created_transactions == 13

    # One refresh for the portfolio basis, one for the global basis.
    assert_receive {:refreshed, "global"}
    assert_receive {:refreshed, "portfolio:" <> _}
    refute_receive {:refreshed, _}, 400
  end

  test "a bump arriving during a running refresh re-queues the basis exactly once" do
    test_pid = self()

    start_refresher!(
      refresh: fn basis ->
        send(test_pid, {:refreshing, basis})

        receive do
          :continue -> :ok
        end
      end
    )

    portfolio = portfolio!("Busy")

    DataVersion.bump([portfolio.id])

    # Round one, first basis: the refresher is now busy.
    assert_receive {:refreshing, _}

    # Three more bumps land while it is.
    for _ <- 1..3, do: DataVersion.bump([portfolio.id])

    # Round one still owes its second basis.
    release()
    assert_receive {:refreshing, _}
    release()

    # The three bumps buy exactly ONE more round: two bases, then quiet.
    assert_receive {:refreshing, _}
    release()
    assert_receive {:refreshing, _}
    release()

    refute_receive {:refreshing, _}, 400
  end

  defp release, do: send(refresher_pid(), :continue)

  defp refresher_pid, do: Process.whereis(Refresher)

  test "the queued unit is a basis, so 200 bumps of two bases cost two refreshes" do
    start_refresher!()
    portfolio = portfolio!("Bursty")

    for _ <- 1..200, do: DataVersion.bump([portfolio.id])

    assert_receive {:refreshed, "global"}
    assert_receive {:refreshed, "portfolio:" <> _}
    refute_receive {:refreshed, _}, 400
  end

  test "a round refreshes only the bases the writes since the last round named" do
    start_refresher!()
    first = portfolio!("First")
    second = portfolio!("Second")

    # Creating the portfolios is itself a journaled write, so let that round
    # drain before measuring the one under test.
    assert_receive {:refreshed, _}
    assert_receive {:refreshed, _}
    assert_receive {:refreshed, _}
    refute_receive {:refreshed, _}, 400

    DataVersion.bump([second.id])

    assert_receive {:refreshed, one}
    assert_receive {:refreshed, other}

    # The second portfolio and the global basis — never the first, which was
    # dirty in the previous round and must not stay dirty forever.
    assert Enum.sort([one, other]) ==
             Enum.sort([DataVersion.portfolio_basis(second.id), DataVersion.global_basis()])

    refute one == DataVersion.portfolio_basis(first.id)
    refute other == DataVersion.portfolio_basis(first.id)
    refute_receive {:refreshed, _}, 400
  end

  test "a write stream that never pauses is still drained, at max_delay_ms" do
    start_refresher!(quiet_ms: 500, max_delay_ms: 200)
    portfolio = portfolio!("Relentless")

    # Bumps closer together than the quiet period, for two seconds. A plain
    # restart-on-every-bump debounce would starve the drain until the stream
    # stopped; the cap makes it land while the writes are still coming.
    stream =
      Task.async(fn ->
        Enum.each(1..20, fn _ ->
          DataVersion.bump([portfolio.id])
          Process.sleep(100)
        end)
      end)

    assert_receive {:refreshed, _}, 1_200
    Task.await(stream)
  end

  # Risk-tier invariant (ADR-0036 attention, issue #710): the refresher is
  # never a correctness dependency. `fetch/4` keeps its contract, so a failing
  # refresher costs latency and never freshness.
  test "a refresh that raises neither kills the refresher nor affects what a read is served" do
    test_pid = self()

    start_refresher!(
      refresh: fn basis ->
        send(test_pid, {:refreshed, basis})
        raise "refresh exploded"
      end
    )

    portfolio = portfolio!("Exploding")
    pid = refresher_pid()

    DataVersion.bump([portfolio.id])
    assert_receive {:refreshed, _}
    assert_receive {:refreshed, _}

    # Still alive, and still refreshing afterwards.
    assert Process.alive?(pid)
    assert refresher_pid() == pid

    DataVersion.bump([portfolio.id])
    assert_receive {:refreshed, _}
    assert_receive {:refreshed, _}

    # And the read path is untouched: a stale entry is still recomputed on
    # read, exactly as before the refresher existed.
    basis = DataVersion.portfolio_basis(portfolio.id)
    key = "view=unscoped|today=#{Date.utc_today()}"

    assert {:fresh, 1} = Derived.fetch(:performance_analysis, basis, key, fn -> 1 end)
    DataVersion.bump([portfolio.id])
    assert {:fresh, 2} = Derived.fetch(:performance_analysis, basis, key, fn -> 2 end)
  end

  test "it is disabled by the same switch as the rest of the derived layer" do
    Application.put_env(:portfolixir, Derived, enabled?: false)

    assert Refresher.init(refresh: fn _ -> :ok end) == :ignore

    Application.put_env(:portfolixir, Derived, enabled?: true)
    assert Refresher.init(enabled?: false, refresh: fn _ -> :ok end) == :ignore
  end

  # A mis-wired collaborator here would be a production-only no-op with a green
  # suite: the refresher would drain on schedule and warm nothing.
  test "the application wires the refresher to the warm-up's request path" do
    assert {Refresher, opts} =
             Enum.find(PortfolixirApplication.children(), &match?({Refresher, _}, &1))

    assert Keyword.fetch!(opts, :refresh) == (&Warmup.warm_basis/1)
  end

  test "an unexpected message neither kills the refresher nor loses a pending drain" do
    start_refresher!()
    portfolio = portfolio!("Noisy")
    pid = refresher_pid()

    DataVersion.bump([portfolio.id])
    send(pid, :something_nobody_sends)

    assert_receive {:refreshed, _}
    assert_receive {:refreshed, _}
    assert Process.alive?(pid)
  end

  # The callback exercised directly: the race is between a quiet timer that has
  # already fired and the bump that wants to restart it. Left unflushed, the
  # stale `:drain` would refresh mid-burst — the coalescing opportunity the
  # quiet period exists to take.
  test "a bump that races an already-fired quiet timer flushes the stale drain" do
    assert {:ok, state} =
             Refresher.init(quiet_ms: 1, max_delay_ms: 5_000, refresh: fn _ -> :ok end)

    assert {:noreply, state} = Refresher.handle_cast({:notify, ["global"]}, state)

    # The 1 ms timer has fired into this process's mailbox by now.
    Process.sleep(20)

    assert {:noreply, _state} =
             Refresher.handle_cast({:notify, ["portfolio:1"]}, %{state | quiet_ms: 5_000})

    refute_received :drain
  end

  test "notify/1 is a no-op when the refresher is not running" do
    refute refresher_pid()
    assert Refresher.notify(["global"]) == :ok
  end
end
