defmodule PortfolixirWeb.DashboardTradesCardFailureTest do
  # Sprint 22 closing act (coverage of #1351's clamped failure note): the
  # Overview's closed-trades card when its read fails. The read fails here
  # because a column of the cash accounts table is renamed inside the test's
  # own transaction (rolled back with it), after the page's data is seeded
  # and before it mounts: the page's counts still read, every full row read
  # fails. Synchronous: the rename locks the table for the test.
  # Every name is synthetic.
  use PortfolixirWeb.ConnCase

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest

  alias Portfolixir.Repo
  alias Portfolixir.WorldFixtures

  # User story (#984's failure state, clamped by #1351):
  # As the operator landing on the Overview while the closed trades cannot
  # be read,
  # I want the card to say so in a problem note,
  # so that an empty card is never mistaken for "no trades".
  #
  # Acceptance criteria:
  # - A closed-trades read that fails renders "Couldn't load the closed
  #   trades." as a clamped problem note in the card, and the page stays up.
  test "a closed-trades read that fails shows the card's clamped problem note", %{conn: conn} do
    world = WorldFixtures.base_world(name: "Card", cash_name: "Giro", depot_name: "Depot")
    WorldFixtures.deposit!(world, "1000", ~D[2026-01-02])
    security = WorldFixtures.create_security!(name: "Quickturn Retail", ticker: nil)
    WorldFixtures.buy!(world, security, quantity: "10", price: "50", date: ~D[2026-02-01])
    WorldFixtures.sell!(world, security, quantity: "10", price: "45", date: ~D[2026-03-03])

    Repo.query!(
      "ALTER TABLE cash_accounts RENAME COLUMN liquidity_role TO liquidity_role_unreadable"
    )

    capture_log(fn ->
      {:ok, view, _html} = live(conn, "/")
      render_async(view)

      assert has_element?(
               view,
               "#dashboard-trades #trades-card-error.data-note--problem.data-note--clamped .data-note__text",
               "Couldn't load the closed trades."
             )

      assert Process.alive?(view.pid)
    end)
  end
end
