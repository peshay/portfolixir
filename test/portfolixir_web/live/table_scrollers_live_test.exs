defmodule PortfolixirWeb.TableScrollersLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.WorldFixtures

  # User story (#788, UX-DR15 — every wide block owns its scroller, the
  # ≤ 5-column tail the inventory listed "for uniformity"):
  # As a local portfolio maintainer on a narrow screen,
  # I want every table to scroll inside its own wrapper,
  # so that the next wide column never clips a value again.
  #
  # Acceptance criteria:
  # - The history, the cash table and the performance summary table sit in
  #   the shared `.data-table-wrapper` (the holdings table left the
  #   Transactions route with #803).
  test "the transactions tables sit in the shared wrapper", %{conn: conn} do
    world = WorldFixtures.base_world()
    share = WorldFixtures.create_security!(name: "Share Co", ticker: "SHR")
    WorldFixtures.deposit!(world, "1000", ~D[2026-02-01])
    WorldFixtures.buy!(world, share, quantity: "2", price: "100", date: ~D[2026-02-10])

    {:ok, view, _html} = live(conn, "/transactions")

    assert has_element?(view, "#transaction-table-wrapper.data-table-wrapper > #transaction-list")
  end

  test "the Wealth cash and performance tables sit in the shared wrapper", %{conn: conn} do
    Portfolixir.Classifications.ensure_builtins()
    world = WorldFixtures.base_world()
    share = WorldFixtures.create_security!(name: "Share Co", ticker: "SHR")
    today = Date.utc_today()
    WorldFixtures.deposit!(world, "1000", Date.add(today, -10))
    WorldFixtures.buy!(world, share, quantity: "2", price: "100", date: Date.add(today, -9))
    WorldFixtures.put_quote!(share, today, "110")

    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    assert has_element?(view, ".data-table-wrapper > table.cash-table")
    assert has_element?(view, ".data-table-wrapper > table.perf-data-table")
  end
end
