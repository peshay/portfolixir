defmodule PortfolixirWeb.CashflowBackfillTest do
  # Issue #737 (Sprint 9 D-1): the exclusion notice on the Cash-flow facets
  # regains a live control — the one-shot historical backfill (UX-DR25's
  # no-dead-control clause, which is why the Sprint 8 control was removed).
  # async: false — the fake's history response is shared through the
  # application env because the backfill runs in the view's own task.
  use PortfolixirWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Portfolixir.Fx.RateSync.Fake
  alias Portfolixir.Portfolios.RealizedGains
  alias Portfolixir.WorldFixtures

  setup do
    on_exit(fn -> Fake.clear_shared_history_response() end)
    :ok
  end

  defp d1_fixture do
    world = WorldFixtures.base_world(name: "Realized", currency: "EUR")
    gbp = WorldFixtures.create_security!(name: "Pound Equity", ticker: "PGB", currency: "GBP")

    gbp_world =
      Map.merge(
        world,
        WorldFixtures.add_depot(world.portfolio,
          currency: "GBP",
          cash_name: "GBP Cash",
          depot_name: "GBP Depot"
        )
      )

    WorldFixtures.buy!(gbp_world, gbp,
      quantity: "2",
      price: "10",
      date: ~D[2026-01-09],
      currency: "GBP"
    )

    WorldFixtures.sell!(gbp_world, gbp,
      quantity: "2",
      price: "30",
      date: ~D[2026-02-20],
      currency: "GBP"
    )

    world
  end

  # User story (issue #737):
  # As a local portfolio maintainer reading "1 sale could not be converted",
  # I want the notice to offer the backfill of the historical ECB series right
  # there,
  # so that the stated limit has a remedy on the surface instead of a dead end
  # — and the sale leaves the exclusion as soon as its date has a rate.
  #
  # Acceptance criteria:
  # - The realized exclusion note carries the backfill control with the limit
  #   that remains stated (a day the ECB did not publish stays excluded).
  # - Clicking it runs the backfill in the background; on success the facet
  #   re-reads: the note is gone, excluded.count is 0 and the converted total
  #   is the exact Decimal.
  test "the realized exclusion note backfills the series and the sale converts", %{conn: conn} do
    d1_fixture()

    Fake.put_shared_history_response(
      {:ok,
       [
         %{
           base_currency: "EUR",
           quote_currency: "GBP",
           date: ~D[2026-02-20],
           rate: "0.85",
           source: "ecb"
         }
       ]}
    )

    {:ok, view, _html} = live(conn, "/cashflow?tab=realized")

    note = view |> element(~s([data-role="realized-excluded"])) |> render()
    assert note =~ "Pound Equity"
    assert note =~ "Backfill historical rates"
    assert note =~ "did not publish stays excluded"
    refute note =~ "Rate sync fetches current rates only"

    clicking = view |> element("#fx-backfill-button") |> render_click()
    assert clicking =~ "Backfilling…"

    render_async(view)
    html = render_async(view)

    # The sale converted: the note is gone, the February figure is on screen.
    refute has_element?(view, ~s([data-role="realized-excluded"]))
    assert RealizedGains.report().excluded.count == 0

    # The engine's own arithmetic: EUR-hub triangulation, amount × (1 / rate).
    expected = Decimal.mult(Decimal.new("40"), Decimal.div(Decimal.new(1), Decimal.new("0.85")))
    [%{months: months}] = RealizedGains.report().annual
    assert Decimal.equal?(months[2], expected)
    assert html =~ "47.06"
  end

  test "a failed backfill is named in the note, nothing else changes", %{conn: conn} do
    d1_fixture()
    Fake.put_shared_history_response({:error, :boom})

    {:ok, view, _html} = live(conn, "/cashflow?tab=realized")
    view |> element("#fx-backfill-button") |> render_click()
    render_async(view)

    result = view |> element(~s([data-role="fx-backfill-result"])) |> render()
    assert result =~ "Backfill failed"
    assert has_element?(view, ~s([data-role="realized-excluded"]))
    assert RealizedGains.report().excluded.count == 1
  end
end
