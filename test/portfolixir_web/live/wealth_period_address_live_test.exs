defmodule PortfolixirWeb.WealthPeriodAddressLiveTest do
  # #1432 (Sprint 28 S5; plan amendment D-A1): the performance period on
  # Wealth rides the address, so the privacy and language switches, a view
  # chip, a Wealth tab and a reload keep it, and an arrival validates it
  # against the analysis' range.
  use PortfolixirWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Clock

  # Invented names and figures only: one deposit and one buy on 10 January
  # of last year, closes at that day, at last year's end and today, so the
  # analysis walks last year and this one.
  defp world do
    today = Clock.today()
    start = Date.new!(today.year - 1, 1, 10)
    world = base_world(name: "Period World", cash_name: "Giro", depot_name: "Depot")
    deposit!(world, "1000", start)
    security = create_security!(name: "Period Synthetic ETF")
    buy!(world, security, quantity: "8", price: "100", date: start)

    put_quotes!(security, [
      {start, "100"},
      {Date.new!(today.year - 1, 12, 31), "110"},
      {today, "121"}
    ])

    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Period view"})
    %{today: today, last_year: today.year - 1, view: view}
  end

  defp settle(view), do: Enum.each(1..3, fn _round -> render_async(view) end)

  defp href(view, selector) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find(selector)
    |> Floki.attribute("href")
    |> List.first()
  end

  # A link followed as the browser would: a switch answers with a redirect
  # to the address without its own parameter.
  defp follow(conn, href) do
    case live(conn, href) do
      {:ok, view, _html} ->
        view

      {:error, {:redirect, %{to: to}}} ->
        {:ok, view, _html} = live(conn, to)
        view
    end
  end

  # The three kinds of pick, each as the page offers it, and the address
  # it patches to.
  defp pick(view, :token, _w) do
    view
    |> element("[data-role='period-tokens'] button[phx-value-period='max']")
    |> render_click()

    "/portfolio?period=max"
  end

  defp pick(view, :year, w) do
    view |> element("#period-custom button[phx-value-year='#{w.last_year}']") |> render_click()
    "/portfolio?year=#{w.last_year}"
  end

  defp pick(view, :range, w) do
    from = Date.new!(w.last_year, 12, 31)

    view
    |> form("[data-role='period-range']", %{"from" => "#{from}", "to" => "#{w.today}"})
    |> render_submit()

    "/portfolio?" <> URI.encode_query([{"from", "#{from}"}, {"to", "#{w.today}"}])
  end

  defp shown?(view, :token, _w),
    do: has_element?(view, "button[phx-value-period='max'][aria-pressed='true']")

  defp shown?(view, :year, w),
    do:
      has_element?(
        view,
        "#period-custom button[phx-value-year='#{w.last_year}'][aria-pressed='true']"
      ) and
        has_element?(view, "[data-role='custom-period-chip']")

  defp shown?(view, :range, w),
    do:
      has_element?(view, "[data-role='custom-period-chip']") and
        has_element?(view, "#performance-from[value='#{w.last_year}-12-31']") and
        has_element?(view, "#performance-to[value='#{Date.to_iso8601(w.today)}']")

  defp one_year?(view),
    do: has_element?(view, "button[phx-value-period='1y'][aria-pressed='true']")

  # User story (#1432, D-A1):
  # As the operator who picked a period on Wealth → Performance,
  # I want it kept when I switch the privacy mode or the language, change
  # the view or the tab, or reload,
  # so that the figures I read do not fall back to 1 year under my hand.
  #
  # Acceptance criteria:
  # - Picking a token, a year or a custom range patches the address:
  #   `period=`, `year=`, `from=` and `to=`.
  # - The privacy switch, the language switch, a view chip and the Wealth
  #   tabs (there and back) link with the period, and each reopens it;
  #   so does a reload of the patched address. The stacked chart's links
  #   carry it too.
  for kind <- [:token, :year, :range] do
    @kind kind
    test "a picked #{kind} rides the address through every switch and a reload", %{conn: conn} do
      w = world()

      {:ok, view, _html} = live(conn, "/portfolio")
      settle(view)
      assert one_year?(view)

      address = pick(view, @kind, w)
      assert_patch(view, address)
      settle(view)
      assert shown?(view, @kind, w)

      for {what, selector} <- [
            {"the privacy switch", "#privacy-mode"},
            {"the language switch", "#locale-de"},
            {"a view chip", "#view-switch-#{w.view.id}"}
          ] do
        followed = follow(conn, href(view, selector))
        settle(followed)
        assert shown?(followed, @kind, w), "#{what} lost the #{@kind}"
      end

      allocation = follow(conn, href(view, "#area-tabs a[href*='tab=allocation']"))
      settle(allocation)
      back = follow(conn, href(allocation, "#area-tabs a.area-tab:first-child"))
      settle(back)
      assert shown?(back, @kind, w), "the Wealth tabs lost the #{@kind}"

      reloaded = follow(conn, address)
      settle(reloaded)
      assert shown?(reloaded, @kind, w), "a reload lost the #{@kind}"

      # The stacked chart's links (its level bar) keep it too.
      view
      |> element("[data-role='chart-series'] button[phx-value-mode='value']")
      |> render_click()

      settle(view)

      assert href(view, "[data-role='stack-level'] a[data-level='total']") =~
               URI.parse(address).query
    end
  end

  # User story (#1432, D-A1):
  # As the operator opening a Wealth link whose period no longer fits the
  # data (a year without bookings, a range outside them, a typo),
  # I want the page at 1 year with one line saying so,
  # so that I never read an empty or invented period as mine.
  #
  # Acceptance criteria:
  # - A range wholly outside the walked history, a year without data, an
  #   unparsable or backwards range and an unknown token open at 1 year,
  #   with one line saying the period asked for was not valid, and the
  #   address is replaced by the page's own without the period.
  # - A valid range opens as asked, without the line; the line leaves with
  #   the next pick.
  test "an arrival period outside the analysis falls back to 1 year with one line", %{conn: conn} do
    w = world()

    for query <- [
          [{"from", "2001-01-01"}, {"to", "2001-12-31"}],
          [{"year", "#{w.last_year - 5}"}],
          [{"from", "garbage"}, {"to", "#{w.today}"}],
          [{"from", "#{w.today}"}, {"to", "#{w.last_year}-01-01"}],
          [{"period", "bogus"}]
        ] do
      {:ok, view, _html} = live(conn, "/portfolio?" <> URI.encode_query(query))
      settle(view)

      assert one_year?(view), "#{inspect(query)} did not fall back"
      assert has_element?(view, "[data-role='period-fallback']"), inspect(query)
      # The address is replaced: the switches link to the page without it.
      refute href(view, "#locale-de") =~ ~r/from=|year=|period=/

      view |> element("button[phx-value-period='ytd']") |> render_click()
      refute has_element?(view, "[data-role='period-fallback']")
    end

    {:ok, view, _html} =
      live(
        conn,
        "/portfolio?" <>
          URI.encode_query([{"from", "#{w.last_year}-12-31"}, {"to", "#{w.today}"}])
      )

    settle(view)
    assert shown?(view, :range, w)
    refute has_element?(view, "[data-role='period-fallback']")
  end
end
