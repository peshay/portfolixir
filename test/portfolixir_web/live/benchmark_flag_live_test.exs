defmodule PortfolixirWeb.BenchmarkFlagLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.WorldFixtures

  # User story (#572, ADR-0046 §1 — the human half of the flag):
  # As a local portfolio maintainer,
  # I want to mark a security as a benchmark from its row menu, and never be
  # offered it in a booking form,
  # so that an index ETF I only compare against cannot be booked by accident
  # and the flag is mine to set without the API.
  #
  # Acceptance criteria:
  # - The row action toggles the flag and says so; toggling again unmarks it.
  # - The transaction form's security select lists the plain security and
  #   not the benchmark.
  test "the row action marks and unmarks a benchmark", %{conn: conn} do
    security = WorldFixtures.create_security!(name: "Index Proxy ETF", ticker: "IDXP")

    {:ok, view, _html} = live(conn, "/securities")

    # The row menu offers the flag, and names the reverse once it is set.
    render_click(view, "open_row_menu", %{"id" => "#{security.id}"})
    assert has_element?(view, "[role='menuitem']", "Mark as benchmark")
    refute has_element?(view, "[role='menuitem']", "Unmark benchmark")

    html = render_click(view, "row_action", %{"action" => "benchmark", "id" => "#{security.id}"})
    assert html =~ "Index Proxy ETF"
    assert Catalog.get_security(security.id).is_benchmark

    render_click(view, "open_row_menu", %{"id" => "#{security.id}"})
    assert has_element?(view, "[role='menuitem']", "Unmark benchmark")

    render_click(view, "row_action", %{"action" => "benchmark", "id" => "#{security.id}"})
    refute Catalog.get_security(security.id).is_benchmark
  end

  test "the booking form never offers a benchmark security", %{conn: conn} do
    _world = WorldFixtures.base_world(name: "Solo")
    WorldFixtures.create_security!(name: "Bookable Co", ticker: "BOOK")

    {:ok, _bench} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "World Index ETF",
        ticker_symbol: "WRLD",
        currency_code: "EUR",
        asset_class: "etf",
        is_benchmark: true
      })

    {:ok, view, _html} = live(conn, "/transactions")
    view |> element("#open-booking") |> render_click()

    select =
      view |> element("#transaction-form select[name='transaction[security_id]']") |> render()

    assert select =~ "Bookable Co"
    refute select =~ "World Index ETF"
  end
end
