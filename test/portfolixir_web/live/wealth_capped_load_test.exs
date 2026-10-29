defmodule PortfolixirWeb.WealthCappedLoadTest do
  # #1204 (Sprint 21, D-4 answer (b)): a page's load that the heap cap kills
  # is reported to the page as a failed load, instead of taking the page
  # down with it.
  use PortfolixirWeb.ConnCase

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.WorldFixtures

  defp seed_world do
    world = WorldFixtures.base_world(name: "Capped Depot")
    security = WorldFixtures.create_security!(name: "Capped ETF", ticker: "CAP")
    today = Date.utc_today()
    start = Date.add(today, -10)

    WorldFixtures.deposit!(world, "1000", start)
    WorldFixtures.buy!(world, security, quantity: "8", price: "100", date: start)
    WorldFixtures.put_quotes!(security, [{start, "100"}, {today, "110"}])

    for name <- ["Strategy", "Region"] do
      {:ok, classification} =
        Classifications.create_classification(Actor.owner_ui(), %{name: name})

      {:ok, _category} =
        Classifications.create_category(Actor.owner_ui(), %{
          classification_id: classification.id,
          name: "Core"
        })

      classification
    end
  end

  # The cap the next task takes as its first act, set after the page mounted
  # under its own: 2 KiB, below what any load holds, so the runtime kills the
  # task at its first collection.
  defp with_lowered_cap(fun) do
    prior = Application.get_env(:portfolixir, Portfolixir.HeapCap, [])

    Application.put_env(
      :portfolixir,
      Portfolixir.HeapCap,
      Keyword.put(prior, :max_heap_bytes, 2_048)
    )

    try do
      fun.()
    after
      Application.put_env(:portfolixir, Portfolixir.HeapCap, prior)
    end
  end

  # User story (#1204):
  # As the operator whose Wealth page loads its figures in capped tasks,
  # I want a load the heap cap kills to end in the page's own failure state,
  # so that I read "Couldn't load the wealth figures." once, instead of a
  # page that drops, reconnects and starts the same load again.
  #
  # Acceptance criteria:
  # - A load killed at the cap reaches the page as a failed load, and the
  #   page shows its own failure note.
  # - The page's process survives the kill and keeps serving events.
  test "a Wealth load killed at the heap cap shows the page's own failure, and the page stays up",
       %{conn: conn} do
    [_strategy, region] = seed_world()

    {:ok, view, _html} = live(conn, "/portfolio?tab=allocation")
    render_async(view)
    page = view.pid
    watch = Process.monitor(page)
    # The test is linked to the page's client: a page that went down would
    # take the test with it before it could say so.
    Process.flag(:trap_exit, true)

    # The runtime's report of the kill is captured, not asserted: it may land
    # after the page has answered.
    capture_log(fn ->
      outcome =
        with_lowered_cap(fn ->
          try do
            view
            |> element("form[phx-change='select_classification']")
            |> render_change(%{"classification_id" => to_string(region.id)})

            {:rendered, render_async(view)}
          catch
            :exit, reason -> {:page_down, reason}
          end
        end)

      refute_received {:DOWN, ^watch, :process, ^page, _reason}
      assert {:rendered, html} = outcome
      assert html =~ "Couldn&#39;t load the wealth figures."
      assert Process.alive?(page)

      # The page still serves: a load under the restored cap lands.
      render_click(view, "set_allocation_mode", %{"mode" => "value"})
      assert Process.alive?(page)
    end)
  end
end
