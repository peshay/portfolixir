defmodule PortfolixirWeb.DashboardReadCapTest do
  # Sprint 31 closing act, security lens SE1 (S2): one stored layout of 40
  # „Gesamtwert“ items, each on a view of its own, and a burst through the
  # eight periods started 321 capped workers at once — one value and drift
  # read and one performance read per item and period, none coalesced,
  # none queued. The page's reads are now one per name at a time (the
  # newest period wins per scope) and at most four at work.
  #
  # async: false — the probe counts the workers under the one
  # `Portfolixir.CappedTasks` supervisor, which other tests' pages share.
  # group: :dashboards -- a create takes the advisory lock that counts the
  # dashboards (`Portfolixir.LockTable` row 30).
  use PortfolixirWeb.ConnCase, async: false, group: :dashboards

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures, only: [base_world: 0, buy!: 3, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Dashboards

  # The page's reads at work at once (`DashboardLive`'s `@max_reads`), and
  # the slack a sample may catch: a worker that has answered but not yet
  # exited while the next one starts.
  @cap 4
  @slack 2

  # User story:
  # As the operator whose dashboard holds many widgets on many views,
  # I want the page to run only a few reads at once, and a burst of period
  # switches to read only the period I stopped on,
  # so that one layout cannot load the machine with hundreds of walks.
  #
  # Acceptance criteria:
  # - 40 items on 40 views, opened and switched through the seven other
  #   periods: never more than the cap (4) and a small slack of workers
  #   in flight at once.
  # - Every read still lands: once the page is no longer busy, every item
  #   draws its change for the period it stopped on (Max).
  test "a layout's reads are capped and the newest period wins per scope", %{conn: conn} do
    world = base_world()

    {:ok, security} =
      Portfolixir.Catalog.create_security(Actor.owner_ui(), %{
        name: "Capped Synthetic Co",
        currency_code: "EUR"
      })

    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-10])
    put_quote!(security, Portfolixir.Clock.today(), "120")

    views =
      for n <- 1..40 do
        {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Capped view #{n}"})
        view
      end

    layout =
      views
      |> Enum.with_index()
      |> Enum.map(fn {view, i} ->
        %{
          "kind" => "total_value",
          "size" => "S",
          "col" => rem(i, 4) * 3 + 1,
          "row" => div(i, 4) * 2 + 1,
          "settings" => %{"view_id" => view.id}
        }
      end)

    {:ok, dashboard} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Wide", "layout" => layout})

    parent = self()
    sampler = spawn_link(fn -> sample(parent, 0) end)
    {:ok, view, _html} = live(conn, "/dashboards/#{dashboard.id}")

    for period <- ~w(1d 1w 1m 3m ytd 3y max),
        do: render_hook(view, "set_period", %{"period" => period})

    settle(view)
    send(sampler, :stop)
    assert_receive {:peak, peak}, 60_000
    assert peak <= @cap + @slack, "#{peak} workers in flight at once"

    changes =
      view
      |> render()
      |> Floki.parse_document!()
      |> Floki.find("[data-role='card-period-change']")

    assert length(changes) == 40
    assert Enum.all?(changes, &(Floki.text(&1) =~ "TTWROR · Max")), inspect(changes)
    assert Enum.all?(changes, &(Floki.find(&1, ".value-skeleton") == [])), inspect(changes)
  end

  # Until the grid is no longer busy: a read that waited for a slot, or
  # the latest period a running read made wait, starts only once another
  # lands, after the `render_async/1` before it returned.
  defp settle(view, rounds \\ 200) do
    render_async(view, 30_000)

    cond do
      not has_element?(view, "#dashboard-grid[aria-busy='true']") -> :ok
      rounds == 0 -> flunk("the dashboard stayed busy")
      true -> settle(view, rounds - 1)
    end
  end

  defp sample(parent, peak) do
    receive do
      :stop -> send(parent, {:peak, peak})
    after
      5 ->
        workers = length(Task.Supervisor.children(Portfolixir.CappedTasks))
        sample(parent, max(peak, workers))
    end
  end
end
