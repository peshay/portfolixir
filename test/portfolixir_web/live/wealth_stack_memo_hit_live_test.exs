defmodule PortfolixirWeb.WealthStackMemoHitLiveTest do
  # I34 step 2 (Sprint 31 P2): the stacked chart on Wealth draws a
  # remembered answer in the render that asked for it, without the
  # "computing" skeleton. The derived layer is ON here (the test config
  # keeps it off, ADR-0032 §7.3), and the memo table is global, hence
  # async: false.
  use PortfolixirWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quotes!: 2]

  alias Portfolixir.Clock
  alias Portfolixir.Derived.Memo
  alias Portfolixir.DerivedConfig

  setup do
    Memo.reset()
    on_exit(&Memo.reset/0)
    DerivedConfig.enable!(lifetimes: [])
    :ok
  end

  # Invented names and figures only: two positions bought 500 days back,
  # before every window but `max`, with a close today.
  defp world! do
    today = Clock.today()
    d0 = Date.add(today, -500)
    world = base_world(name: "Memo Hit World", cash_name: "Giro", depot_name: "Depot")
    deposit!(world, "10000", d0)

    for {name, price, close} <- [{"Alpha Hit AG", "100", "120"}, {"Beta Hit SE", "50", "45"}] do
      security = create_security!(name: name)
      buy!(world, security, quantity: "10", price: price, date: d0)
      put_quotes!(security, [{d0, price}, {today, close}])
      security
    end
  end

  defp settle(view), do: Enum.each(1..4, fn _round -> render_async(view) end)

  defp skeleton?(html), do: html =~ ~s(data-role="stack-skeleton")

  defp legend(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find("#stack-legend tbody tr")
    |> Enum.flat_map(&Floki.attribute(&1, "data-band"))
  end

  defp switch(view, period),
    do:
      view
      |> element("[data-role='period-tokens'] button[phx-value-period='#{period}']")
      |> render_click()

  # User story (I34 step 2, Sprint 31 P2; M6's finding that every warm
  # switch rendered the skeleton first and the chart second):
  # As the operator switching the stacked chart between periods,
  # I want a period whose chart is remembered drawn at once,
  # so that the chart does not flash "computing" for a figure already known.
  #
  # Acceptance criteria:
  # - A switch to a period not yet read shows the skeleton until its walk
  #   lands (a miss still loads in the background).
  # - A switch back to a period already read draws the chart in the render
  #   the click answers: no `stack-skeleton`, the legend the walk answered.
  # - After a write, which bumps the basis, the remembered chart is not
  #   drawn: the switch shows the skeleton again until the fresh walk lands.
  test "a switch to a remembered period draws the chart without the skeleton", %{conn: conn} do
    [alpha, _beta] = world!()

    {:ok, view, _html} = live(conn, "/portfolio?level=category&period=1y")
    settle(view)
    one_year = view |> render() |> legend()
    assert one_year != []

    assert view |> switch("3y") |> skeleton?(), "a cold switch drew no skeleton"
    settle(view)
    three_years = view |> render() |> legend()

    warm = switch(view, "1y")
    refute skeleton?(warm), "a warm switch to 1y drew the skeleton"
    assert legend(warm) == one_year

    warm = switch(view, "3y")
    refute skeleton?(warm), "a warm switch to 3y drew the skeleton"
    assert legend(warm) == three_years

    put_quotes!(alpha, [{Date.add(Clock.today(), -3), "125"}])
    assert view |> switch("1y") |> skeleton?(), "a chart remembered before the write was drawn"
    settle(view)
    refute view |> render() |> skeleton?()
  end
end
