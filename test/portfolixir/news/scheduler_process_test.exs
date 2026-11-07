defmodule Portfolixir.News.SchedulerProcessTest do
  # ADR-0056 §5, B6 (Sprint 27, N3): the supervised scheduler. Not async:
  # the scheduler's own process reads the database, so the sandbox is shared.
  use Portfolixir.DataCase, async: false

  import Ecto.Query
  import Portfolixir.NewsFixtures

  alias Portfolixir.Catalog.QuoteSync
  alias Portfolixir.News.Item
  alias Portfolixir.News.Scheduler
  alias Portfolixir.Repo

  # User story:
  # As the operator,
  # I want the news scheduler to run exactly where the quote sync runs, and
  # an enabled feed to be its only opt-in,
  # so that there is no second switch to forget and a feed nobody registered
  # reaches no host (B6).
  #
  # Acceptance criteria:
  # - The supervision tree starts the scheduler with the quote sync's
  #   `enabled?`: on in production, in development with
  #   PORTFOLIXIR_BACKGROUND_FETCH, off in tests.
  # - An enabled scheduler fetches a due feed on its tick; a disabled one
  #   never ticks and requests nothing.
  test "it is enabled exactly where the quote sync is" do
    {Scheduler, opts} =
      Enum.find(Portfolixir.Application.children(), &match?({Scheduler, _}, &1))

    quote_sync = Application.get_env(:portfolixir, QuoteSync, [])
    assert Keyword.fetch!(opts, :enabled?) == Keyword.get(quote_sync, :enabled?, false)
    assert Keyword.fetch!(opts, :enabled?) == false

    for path <- ~w(config/config.exs config/dev.exs config/prod.exs config/runtime.exs) do
      refute File.read!(path) =~ "News.Scheduler",
             "#{path} gives the scheduler a switch of its own"
    end
  end

  test "an enabled scheduler fetches a due feed on its tick" do
    test_pid = self()
    feed = feed!(%{class: "issuer", security_id: security!().id})

    plug = fn conn ->
      send(test_pid, :requested)

      Plug.Conn.send_resp(
        conn,
        200,
        rss([%{title: "Northwind ships", link: "https://newsroom.example.com/s/1"}])
      )
    end

    # A tick an hour away, sent by hand: the run is the test's to wait for,
    # so no fetch outlives the test's sandbox.
    scheduler =
      start_supervised!(
        {Scheduler,
         name: nil, enabled?: true, tick_ms: :timer.hours(1), fetch_opts: [req: [plug: plug]]}
      )

    send(scheduler, :tick)
    assert_receive :requested, 2_000
    wait_until(fn -> :sys.get_state(scheduler).running == nil end)

    assert Repo.aggregate(from(i in Item, where: i.feed_id == ^feed.id), :count) == 1
  end

  test "a disabled scheduler requests nothing" do
    test_pid = self()
    feed!(%{class: "issuer", security_id: security!().id})

    plug = fn conn ->
      send(test_pid, :requested)
      Plug.Conn.send_resp(conn, 200, rss([]))
    end

    start_supervised!(
      {Scheduler, name: nil, enabled?: false, tick_ms: 20, fetch_opts: [req: [plug: plug]]}
    )

    refute_receive :requested, 200
  end

  defp wait_until(check, tries \\ 100) do
    cond do
      check.() -> :ok
      tries == 0 -> flunk("condition never held")
      true -> Process.sleep(20) && wait_until(check, tries - 1)
    end
  end
end
