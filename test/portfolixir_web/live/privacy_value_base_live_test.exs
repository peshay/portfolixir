defmodule PortfolixirWeb.PrivacyValueBaseLiveTest do
  # The privacy mode's value line on Wealth (Sprint 26 P2, I22; board 02)
  # when its window opens at zero or below (Sprint 28, the S6 lens of the
  # closing act): the shared chart's percent view divided by the window's
  # first value, so a series that opened at 0 kept its amounts and labelled
  # them "%", and one that opened below 0 turned its axis over. The base is
  # now the first day the value is above zero, as the stacked chart's index
  # is (#1433); with no such day the axis carries no label. The component's
  # own cases are in test/portfolixir_web/components/security_chart_test.exs.
  #
  # Each world is synthetic and dated from today, so the 1Y window holds it
  # on every run: a buy booked two days before the money that pays it.
  use PortfolixirWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures
  import PortfolixirWeb.PreferenceCookieHelpers

  alias Portfolixir.Clock
  alias PortfolixirWeb.Format

  @address "/portfolio?level=total"

  defp start, do: Date.add(Clock.today(), -100)

  # 50 shares at 100 on day 0, quoted 110 on day 30 and 120 on day 60,
  # paid by a deposit on day 2: the value is 0 (or minus the fees) until
  # day 2, then 5 000, 5 500 and 6 000. Without the rise the quote stays
  # at 100.
  defp world!(fees, deposit, rise? \\ true) do
    world = base_world(name: "Synthetic Base Portfolio")
    security = create_security!(name: "Synthetic Base Fund", ticker: "SBF")
    d = start()
    rise = if rise?, do: [{Date.add(d, 30), "110"}, {Date.add(d, 60), "120"}], else: []
    put_quotes!(security, [{d, "100"} | rise])
    buy!(world, security, quantity: "50", price: "100", fees: fees, date: d)
    if deposit, do: deposit!(world, deposit, Date.add(d, 2))
    world
  end

  defp render_value_line(conn) do
    {:ok, view, _html} = live(conn, @address)
    html = render_async(view)
    assert html =~ ~s(data-chart-mode="value"), "#{@address} draws no value line"
    html
  end

  defp masked, do: build_conn() |> put_preference_cookie("portfolixir_privacy", "on")

  defp ticks(html) do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.query("#performance-figure .chart-axis-y")
    |> Enum.map(&String.trim(LazyHTML.text(&1)))
  end

  # A tick as a number: "6,300", "-300.00" or "+26.0%".
  defp number(tick) do
    tick |> String.replace(~r/[,%+]/, "") |> String.to_float()
  rescue
    ArgumentError -> tick |> String.replace(~r/[,%+]/, "") |> String.to_integer() |> Kernel.*(1.0)
  end

  defp points(html) do
    [json] =
      Regex.run(
        ~r/<script type="application\/json" data-chart-payload[^>]*>(.*?)<\/script>/s,
        html,
        capture: :all_but_first
      )

    json
    |> Jason.decode!()
    |> Map.fetch!("points")
    |> Map.new(fn [date, display | _] -> {date, display} end)
  end

  # A figure of the world standing as a number of its own, outside a row id.
  defp leaked(html, figures) do
    html =
      Regex.replace(
        ~r/([?&;](?:amp;)?[a-z_]*(?:tree|category|id|view|portfolio)=)\d+/,
        html,
        "\\1ID"
      )

    Enum.filter(figures, &Regex.match?(~r/(?<![\d.,])#{Regex.escape(&1)}(?!\d)/, html))
  end

  # The unmasked axis's ticks, read as numbers, each in percent of 5 000.
  defp indexed(plain_ticks) do
    Enum.map(plain_ticks, fn tick -> (number(tick) - 5000) / 5000 * 100 end)
  end

  defp assert_indexed(masked_ticks, plain_ticks) do
    assert length(masked_ticks) == 5 and Enum.all?(masked_ticks, &String.ends_with?(&1, "%")),
           inspect(masked_ticks)

    for {tick, expected} <- Enum.zip(masked_ticks, indexed(plain_ticks)) do
      assert_in_delta number(tick), expected, 0.051, "#{tick} is not #{expected} %"
    end
  end

  # User story (S6 lens, closing act of Sprint 28):
  # As the operator showing Wealth's value line in the privacy mode,
  # I want its percent axis based on the first day the value is above zero,
  # so that a window that opens at zero prints no amount as a percentage.
  #
  # Acceptance criteria:
  # - A value line whose window opens at 0 (a buy booked before its money)
  #   reads each tick in percent of the value on the first day it is above
  #   zero: the unmasked tick less 5 000, over 5 000; no tick, tooltip or
  #   attribute names an amount of the world.
  # - The tooltip reads the same percentage ("Value +10.0%" on day 30).
  # - The line under the chart names that day as its 100 %.
  test "a value line that opens at zero reads in percent of its first day above zero" do
    world!("0", "5000")
    plain = build_conn() |> render_value_line() |> ticks()
    assert plain == ["-300.00", "1,350", "3,000", "4,650", "6,300"]

    html = render_value_line(masked())
    assert_indexed(ticks(html), plain)

    assert leaked(
             html,
             ~w(-300.00 1,350 1350 3,000 4,650 4650 5,000 5000 5,500 5500 6,000 6000 6,300 6300)
           ) ==
             []

    by_date = points(html)
    assert by_date[Date.to_iso8601(start())] =~ ~r/· Value -100\.0%$/
    assert by_date[Date.to_iso8601(Date.add(start(), 30))] =~ ~r/· Value \+10\.0%$/

    assert html =~
             "the value in percent of the value on #{Format.date(Date.add(start(), 2))}, the first day it is above zero"
  end

  # Acceptance criteria:
  # - A window that opens below zero (the buy's fees before its money) is
  #   indexed the same way, so its axis is not turned over: the ticks rise
  #   from the bottom to the top, and day 0 reads -104 %.
  test "a value line that opens below zero is not turned over" do
    world!("200", "5200")
    plain = build_conn() |> render_value_line() |> ticks()

    html = render_value_line(masked())
    masked_ticks = ticks(html)
    assert_indexed(masked_ticks, plain)
    assert Enum.map(masked_ticks, &number/1) == Enum.sort(Enum.map(masked_ticks, &number/1))

    assert points(html)[Date.to_iso8601(start())] =~ ~r/· Value -104\.0%$/
  end

  # Acceptance criteria:
  # - A window in which the value is above zero on no day draws its line
  #   without tick labels, its tooltip names no figure of the value, and the
  #   line under the chart says the axis has no labels.
  test "a value line above zero on no day draws no tick labels" do
    world!("200", nil, false)

    html = render_value_line(masked())
    assert ticks(html) == []
    assert html =~ ~s(class="quote-line")
    assert html =~ "the axis has no labels: the value is above zero on no day of the window"
    refute Enum.any?(Map.values(points(html)), &(&1 =~ ~r/Value [+\-]?\d/))
    assert leaked(html, ~w(-200.00 200.00 -210.00)) == []
  end
end
