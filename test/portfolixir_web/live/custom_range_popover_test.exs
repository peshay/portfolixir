defmodule PortfolixirWeb.CustomRangePopoverTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Classifications
  alias Portfolixir.WorldFixtures

  # User story (#801, review C5 — variant A, picked 2026-09-14):
  # As a local portfolio maintainer picking a custom period,
  # I want the from/to pair, the year presets and Apply in a popover on the
  # "Custom range…" trigger — on the Wealth performance chart and on a
  # security's chart alike —
  # so that opening the range moves neither the section heading nor the
  # chart, Esc closes it and returns focus to the trigger, and an applied
  # range closes it by itself.
  #
  # Acceptance criteria:
  # - The disclosure is a popover: its body is positioned on the trigger
  #   (pinned in css_layout_sweep_test.exs) and carries the PopoverDisclosure
  #   hook (Esc closes, focus returns, a server "close-popover" event closes).
  # - The year presets are chips that apply on click; from/to sit in one row
  #   with Cancel and Apply.
  # - An applied year or range pushes the close event; a refused range keeps
  #   the popover open with the violation on its field.
  # - The security detail chart's custom range takes the same treatment.

  defp world do
    Classifications.ensure_builtins()
    world = WorldFixtures.base_world(name: "Range", cash_name: "Giro", depot_name: "Depot")
    security = WorldFixtures.create_security!(name: "Range ETF", ticker: "RNG")
    today = Date.utc_today()
    start = Date.add(today, -400)

    WorldFixtures.deposit!(world, "1000", start)
    WorldFixtures.buy!(world, security, quantity: "10", price: "100", date: start)
    WorldFixtures.put_quotes!(security, [{start, "100"}, {today, "110"}])
    %{world: world, security: security, today: today}
  end

  test "the Wealth custom range is a popover with year chips, cancel and apply", %{conn: conn} do
    %{today: today} = world()

    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    assert has_element?(
             view,
             ~s(#portfolio-performance details#period-custom.period-disclosure[phx-hook="PopoverDisclosure"])
           )

    popover = view |> element("#period-custom") |> render()
    assert popover =~ ~s(class="period-disclosure__body period-popover")
    assert popover =~ ~s(<label for="performance-from")
    assert popover =~ ~s(<label for="performance-to")
    assert popover =~ ~s(id="period-custom-cancel")

    # The year presets are chips, one per walked year, applying on click.
    year = today.year
    view |> element(~s(#period-custom button[phx-value-year="#{year}"])) |> render_click()
    assert has_element?(view, ~s([data-role="custom-period-chip"]), Integer.to_string(year))
    assert_push_event(view, "close-popover", %{id: "period-custom"})

    # An applied range closes the popover by itself…
    view
    |> element(~s(form[data-role="period-range"]))
    |> render_submit(%{"from" => "2026-01-01", "to" => "2026-03-31"})

    assert_push_event(view, "close-popover", %{id: "period-custom"})

    # …a refused one keeps it open with the violation on its field.
    view
    |> element(~s(form[data-role="period-range"]))
    |> render_submit(%{"from" => "2026-03-31", "to" => "2026-01-01"})

    assert has_element?(view, ~s([data-role="range-error"]))
    refute_push_event(view, "close-popover", %{id: "period-custom"})
  end

  test "the security detail chart's custom range takes the same treatment", %{conn: conn} do
    %{security: security} = world()

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=chart")

    assert has_element?(
             view,
             ~s(details#detail-period-custom.period-disclosure[phx-hook="PopoverDisclosure"] form#detail-custom-range)
           )

    view
    |> element("#detail-custom-range")
    |> render_submit(%{"from" => "2026-03-31", "to" => "2026-01-01"})

    assert has_element?(view, ~s([data-role="detail-range-error"]))
    refute_push_event(view, "close-popover", %{id: "detail-period-custom"})

    view
    |> element("#detail-custom-range")
    |> render_submit(%{"from" => "2026-01-01", "to" => "2026-03-31"})

    assert has_element?(view, ~s([data-role="custom-range-chip"]), "2026-01-01")
    assert_push_event(view, "close-popover", %{id: "detail-period-custom"})
  end
end
