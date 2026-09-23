defmodule PortfolixirWeb.RiskLiveTest do
  use PortfolixirWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 0, buy!: 3, create_security!: 1, deposit!: 3, put_quotes!: 2]

  defp day(offset), do: Date.add(Date.utc_today(), offset)

  defp daily_closes(security, from_offset, close_fun) do
    put_quotes!(security, for(offset <- from_offset..0, do: {day(offset), close_fun.(offset)}))
  end

  # Two stocks and an ETF, a year of daily closes, so every figure computes.
  defp risk_world do
    world = base_world()

    big =
      create_security!(name: "Nordic Timber Holdings AB", ticker: "NTH", asset_class: "equity")

    small =
      create_security!(name: "Helios Solar Systems SE", ticker: "HSS", asset_class: "equity")

    etf = create_security!(name: "Meridian Global Equity ETF", ticker: "MGE", asset_class: "etf")

    deposit!(world, "10000", day(-400))
    buy!(world, big, quantity: "20", price: "100", date: day(-400))
    buy!(world, small, quantity: "5", price: "100", date: day(-400))
    buy!(world, etf, quantity: "70", price: "100", date: day(-400))

    daily_closes(big, -400, fn offset -> "#{100 + rem(offset, 7)}" end)
    daily_closes(small, -400, fn offset -> "#{100 - rem(offset, 5)}" end)
    daily_closes(etf, -400, fn offset -> "#{100 + rem(offset, 3)}" end)

    Map.merge(world, %{big: big, small: small, etf: etf})
  end

  # User story (FR-8/FR-9/FR-10 and FR-40, ADR-0047 §9, Sprint 14 D-2 / E1-A):
  # As the operator,
  # I want a Risk tab in Wealth that shows how concentrated my portfolio is
  # and how much it moves,
  # so that the concentration lens and the portfolio metrics the agent reads
  # are visible to me on a screen as well.
  #
  # Acceptance criteria:
  # - Wealth carries a sixth area tab, "Risk", at /risk, marked current there,
  #   and the sidebar keeps Wealth active.
  # - The four portfolio metrics render over the one-year window with their
  #   observation count and minimum, and the basis line names the flow-adjusted
  #   TTWROR factors and √365.
  # - The Top-N table shows each name's weight and the threshold it is above
  #   or below, in words — the lens's own vocabulary, not a verdict.
  # - The HHI renders with its band; with no caps configured, the cap section
  #   says so; the correlation matrix sits behind a closed disclosure.
  test "renders the concentration lens and the portfolio metrics on a sixth Wealth tab", %{
    conn: conn
  } do
    world = risk_world()
    {:ok, view, html} = live(conn, "/risk")

    assert has_element?(
             view,
             ~s([data-role="area-tabs"] a[href="/risk"][aria-current="page"]),
             "Risk"
           )

    assert has_element?(view, "#nav-portfolio[aria-current='page']")

    for role <- ~w(volatility max-drawdown risk-adjusted-return correlations) do
      assert has_element?(view, ~s([data-role="risk-metric-#{role}"]))
    end

    assert has_element?(view, ~s([data-role="risk-metric-volatility"]), "min. 20")
    assert has_element?(view, ~s([data-role="risk-basis"]), "√365")
    assert has_element?(view, ~s([data-role="risk-basis"]), "flow-adjusted")

    assert has_element?(view, ~s(#risk-top-holdings tr[data-security-id="#{world.big.id}"]))
    # 20 × ~100 of ~10000: above 10 % → the stock's hard threshold, in words.
    assert has_element?(
             view,
             ~s(#risk-top-holdings tr[data-security-id="#{world.big.id}"] [data-severity="hard"]),
             "above 10 %"
           )

    assert has_element?(
             view,
             ~s(#risk-top-holdings tr[data-security-id="#{world.etf.id}"] [data-severity="warn"]),
             "above 25 %"
           )

    # The asset class is the catalogue's label, not the stored code.
    assert has_element?(
             view,
             ~s(#risk-top-holdings tr[data-security-id="#{world.etf.id}"] td),
             "ETF"
           )

    refute has_element?(view, "#risk-top-holdings td", "equity")

    assert has_element?(view, ~s([data-role="risk-hhi"] [data-band]))
    assert has_element?(view, ~s([data-role="risk-caps"]), "No cap configured")
    assert has_element?(view, "details#risk-correlations:not([open])")
    assert has_element?(view, ~s(#risk-correlations table tbody tr))

    refute html =~ ~r/recommend|signal|rating/i
  end

  # Acceptance criteria (ADR-0047 §5 and the #838 amendment, on the screen):
  # - A metric below its minimum renders "not computable" with what it had
  #   and what it needed — never a dash and never a number.
  # - A portfolio with no accounts renders an empty state, not a crash.
  test "a refused metric says what it had and what it needed", %{conn: conn} do
    world = base_world()
    thin = create_security!(name: "Kestrel Industrial Group NV", ticker: "KIG")
    deposit!(world, "1000", day(-5))
    buy!(world, thin, quantity: "5", price: "100", date: day(-5))
    daily_closes(thin, -5, fn _ -> "100" end)

    {:ok, view, _html} = live(conn, "/risk")

    assert has_element?(
             view,
             ~s([data-role="risk-metric-volatility"][data-refused]),
             "not computable"
           )

    assert has_element?(view, ~s([data-role="risk-metric-volatility"]), "6 of 20")
  end

  test "renders an empty state when there is no portfolio", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/risk")
    assert has_element?(view, ~s([data-role="risk-empty"]))
  end
end
