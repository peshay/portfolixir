defmodule PortfolixirWeb.WealthPolishPassTest do
  # Sprint 30 W2, the Wealth polish pass (#1366; board
  # `mockups/ux-design-2026-11-15-sprint30/02-wealth-polish`, plan D-7):
  # the lines LiveViewTest can drive, each pinned by one test written first
  # and seen failing for its line's reason. The layout lines (the holdings
  # notes at 1200 px, the stacked chart's gutter, the touch tooltip) are
  # measured in Chromium by test/browser/wealth_polish_test.exs. Every
  # name and figure is synthetic.
  #
  # async: false -- the exchange-rate provider the sync test gates is the
  # application's, set in the application environment for the page's task.
  use PortfolixirWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deliver_untraded!: 4, put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Derived.Memo
  alias Portfolixir.DerivedConfig
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios.Performance

  defp day(offset), do: Date.add(Date.utc_today(), offset)

  defp cash!(world, type, amount, date) do
    {:ok, _tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        type: type,
        date: date,
        gross_amount: amount,
        currency_code: "EUR"
      })
  end

  # An exchange-rate provider that holds every fetch until the test lets
  # it go, so a second push can arrive while the first sync runs. Each
  # fetch reports itself to the test process named in the application
  # environment.
  defmodule GatedFx do
    @moduledoc false
    @behaviour Portfolixir.Fx.RateSync.Provider

    @impl true
    def id, do: :gated

    @impl true
    def fetch(_opts) do
      test = Application.fetch_env!(:portfolixir, :wealth_polish_gated_fx)
      send(test, {:fx_fetch, self()})

      receive do
        :go -> {:ok, []}
      after
        5_000 -> {:ok, []}
      end
    end
  end

  # User story (#1366, the lifecycle audit's #32; ADR-0059 §9: busy is one
  # encoding, with a server-side guard):
  # As the operator whose exchange-rate provider counts my requests,
  # I want "Sync exchange rates" refused by the server while its sync runs,
  # so that an event pushed past the disabled button starts no second
  # fetch.
  #
  # Acceptance criteria:
  # - A second sync_rates on the page while its sync runs fetches nothing:
  #   the provider is asked once.
  test "a sync_rates pushed while the page's sync runs makes no second fetch", %{conn: conn} do
    world = base_world(name: "Synthetic Rate Depot")
    cash!(world, "deposit", "1000", day(-5))

    previous = Application.get_env(:portfolixir, Portfolixir.Fx.RateSync)
    Application.put_env(:portfolixir, Portfolixir.Fx.RateSync, provider: GatedFx)
    Application.put_env(:portfolixir, :wealth_polish_gated_fx, self())

    on_exit(fn ->
      Application.put_env(:portfolixir, Portfolixir.Fx.RateSync, previous)
      Application.delete_env(:portfolixir, :wealth_polish_gated_fx)
    end)

    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    render_click(view, "sync_rates", %{})
    assert_receive {:fx_fetch, first}, 2_000

    # A client pushes the event again, as any LiveView client can.
    render_click(view, "sync_rates", %{})

    second =
      receive do
        {:fx_fetch, pid} -> pid
      after
        500 -> nil
      end

    for pid <- [first, second], pid, do: send(pid, :go)
    render_async(view)

    assert is_nil(second),
           "a second sync_rates while the first ran asked the provider again"
  end

  # User story (#1366, Sprint 29 PR 2's fixer on #1461):
  # As the operator reading Wealth's data-quality note "no price at all",
  # I want its link to open the securities it counts,
  # so that the list I land on holds the positions the note named, not
  # every unquoted security of the catalogue.
  #
  # Acceptance criteria:
  # - The note links /securities?dq=missing_quote&holding=held.
  # - That list shows the held security without a quote and leaves out a
  #   watch-list security without one.
  test "the no-price note links the held securities without a price", %{conn: conn} do
    world = base_world(name: "Synthetic Unpriced Depot")
    held = create_security!(name: "Synthetic Held Unpriced AG", ticker: "SHU")
    deliver_untraded!(world, held, "3", date: day(-10))
    _watched = create_security!(name: "Synthetic Watched Unpriced AG", ticker: "SWU")

    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    href = "/securities?dq=missing_quote&holding=held"
    assert has_element?(view, ~s([data-role="dq-no-price"] a[href="#{href}"]))

    {:ok, list, _html} = live(conn, href)
    assert has_element?(list, "td", "Synthetic Held Unpriced AG")
    refute has_element?(list, "td", "Synthetic Watched Unpriced AG")
  end

  # User story (#1366; board 02 ③; the UAT persona on #1436, screenshots
  # 12 and 13):
  # As the operator reading the stacked chart in money,
  # I want a cash band that dips below zero, less than one axis step, to
  # reach a labelled tick below zero,
  # so that the depth reads on the screen and not only in the API.
  #
  # Acceptance criteria:
  # - With cash below zero on two days, shallower than one step, the axis
  #   carries one round step below zero, labelled, and the cash band's
  #   lowest value in the bands read (the API's) lies between that tick and
  #   zero.
  test "a negative cash day shallower than a step reaches one tick below zero", %{conn: conn} do
    world = base_world(name: "Synthetic Dip Depot")
    security = create_security!(name: "Synthetic Dip Fund", ticker: "SDF")
    cash!(world, "deposit", "10000", day(-100))
    buy!(world, security, quantity: "10", price: "1000", date: day(-100))
    put_quotes!(security, [{day(-100), "1000"}, {day(-1), "1050"}])
    cash!(world, "removal", "1500", day(-50))
    cash!(world, "deposit", "1500", day(-48))

    {:ok, view, _html} = live(conn, "/portfolio?level=category")
    render_async(view)
    render_async(view)

    cash_low =
      build_conn()
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")
      |> get("/api/v1/performance/bands?level=category&period=1y")
      |> json_response(200)
      |> get_in(["data", "bands"])
      |> Enum.find(&(&1["key"] == "cash"))
      |> Map.fetch!("values")
      |> Enum.map(&Decimal.new/1)
      |> Enum.min(Decimal)

    assert Decimal.equal?(cash_low, Decimal.new("-1500"))

    ticks =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#performance-figure-stack .chart-axis-y")
      |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
      |> Enum.map(&(&1 |> String.replace(",", "") |> String.replace("−", "-") |> Decimal.new()))

    lowest = Enum.min(ticks, Decimal)

    assert Decimal.lt?(lowest, 0),
           "the axis has no tick below zero, its ticks are #{inspect(Enum.map(ticks, &Decimal.to_string/1))}"

    assert Decimal.compare(lowest, cash_low) != :gt
  end

  # User story (#1366; board 02 ④; the busy-marker rule of
  # busy_placeholders_test, found by the browser privacy walk on #1436):
  # As the operator on the Allocation tab,
  # I want its TTWROR figure marked busy while a fresh one computes,
  # so that the superseded figure never reads as current.
  #
  # Acceptance criteria:
  # - While the performance walk recomputes over a superseded series, the
  #   summary line is aria-busy and its TTWROR slot is the app's
  #   placeholder (`.value-slot-pending`, aria-busy, data-waits
  #   "performance"), not the superseded figure.
  # - Once the fresh walk lands, the figure shows and nothing is busy.
  test "the Allocation tab's TTWROR is busy while a fresh walk computes", %{conn: conn} do
    Memo.reset()
    DerivedConfig.enable!(lifetimes: [])
    world = base_world(name: "Synthetic Busy Depot")
    security = create_security!(name: "Synthetic Busy Fund", ticker: "SBF")
    cash!(world, "deposit", "5000", ~D[2024-01-02])
    buy!(world, security, quantity: "10", price: "100", date: ~D[2024-01-02])
    put_quotes!(security, [{~D[2024-01-02], "100"}, {day(-1), "120"}])

    # Computed once, then superseded by a booking: the previous generation
    # is what the page serves while the fresh walk runs (ADR-0032 §6).
    Performance.view_analysis(nil, base_currency: "EUR")
    buy!(world, security, quantity: "5", price: "110", date: ~D[2024-04-02])
    assert %{daily: [_ | _]} = Performance.previous_view_analysis(nil, base_currency: "EUR")

    {:ok, view, html} = live(conn, "/portfolio?tab=allocation")

    summary = html |> LazyHTML.from_document() |> LazyHTML.query("[data-role='kpi-summary']")
    assert LazyHTML.attribute(summary, "aria-busy") == ["true"]

    assert summary
           |> LazyHTML.query(".value-slot-pending[aria-busy='true'][data-waits='performance']")
           |> Enum.count() == 1,
           "the TTWROR slot shows the superseded figure without a busy marker: " <>
             (summary |> LazyHTML.text() |> String.replace(~r/\s+/, " "))

    render_async(view)
    refute has_element?(view, "[data-role='kpi-summary'][aria-busy]")
    refute has_element?(view, "[data-role='kpi-summary'] .value-slot-pending")
    assert has_element?(view, "[data-role='kpi-summary'] strong", "%")
  end
end
