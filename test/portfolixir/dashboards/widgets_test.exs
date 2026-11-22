defmodule Portfolixir.Dashboards.WidgetsTest do
  # Sprint 31 D1 (FR-60, ADR-0062 §1, §5): the widget registry. A kind is
  # registered once, in code, with its title, group, sizes, the one existing
  # read it draws, its period rule and whether it takes a view, and only with
  # its compact form. Keys are matched as strings; nothing here makes an atom.
  use ExUnit.Case, async: true
  @moduletag :sweep

  alias Portfolixir.Dashboards.Widgets
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.Performance.Movers

  # The slice's kinds and sizes (planning board 01 ②, the Sprint 31 brief of
  # Lane D), with the German titles the boards draw.
  @slice %{
    "total_value" => {~w(S M), "overview", "Gesamtwert"},
    "data_quality" => {~w(S M), "overview", "Datenqualität"},
    "due" => {~w(S), "overview", "Fällig"},
    "off_target" => {~w(S), "overview", "Abseits des Ziels"},
    "performance" => {~w(S M L full), "performance", "Wertentwicklung"},
    "movers" => {~w(S M), "performance", "Tops und Flops"},
    "snapshots" => {~w(S W), "performance", "Snapshots"},
    "allocation_drift" => {~w(M T), "allocation", "Allokation und Drift"},
    "crashes" => {~w(M L), "risk", "Crashes im Vergleich"},
    "bitcoin_cycle" => {~w(M L full), "analyses", "Bitcoin-Zyklus"},
    "sale_review" => {~w(M), "analyses", "Verkaufsrückblick"}
  }

  # User story:
  # As the operator, or the agent I run, composing a dashboard,
  # I want every widget kind registered once with its sizes, its group and the
  # read it draws,
  # so that a layout can name a kind and the server knows what it shows.
  #
  # Acceptance criteria:
  # - The registry holds exactly the slice's eleven kinds, each with the
  #   sizes and the group the board draws, in the catalogue's order.
  # - Every kind is registered with its compact form (ADR-0062 §1).
  # - Lookup is by string key; an unknown string, an atom or another term
  #   finds nothing.
  test "the registry holds the slice's eleven kinds with their sizes and groups" do
    assert Widgets.keys() == ~w(total_value data_quality due off_target performance movers
                                snapshots allocation_drift crashes bitcoin_cycle sale_review)

    for {key, {sizes, group, _german}} <- @slice do
      assert {:ok, kind} = Widgets.fetch(key)
      assert kind.key == key
      assert kind.sizes == sizes, key
      assert kind.group == group, key
      assert kind.compact == true, key
    end

    assert Widgets.fetch("total_values") == :error
    assert Widgets.fetch("") == :error
    assert Widgets.fetch(:total_value) == :error
    assert Widgets.fetch(nil) == :error
    assert Widgets.fetch(%{"kind" => "movers"}) == :error
  end

  test "the sizes are the grid's, and full is a page, not a grid size" do
    assert Widgets.sizes() == ~w(S W M T L full)
    assert Widgets.dimensions("S") == {:ok, {3, 1}}
    assert Widgets.dimensions("W") == {:ok, {6, 1}}
    assert Widgets.dimensions("M") == {:ok, {6, 2}}
    assert Widgets.dimensions("T") == {:ok, {4, 3}}
    assert Widgets.dimensions("L") == {:ok, {8, 3}}
    assert Widgets.dimensions("full") == :error
    assert Widgets.dimensions("XL") == :error
    assert Widgets.dimensions(nil) == :error
  end

  test "the groups are the catalogue's five, in its order" do
    assert Widgets.groups() == ~w(overview performance allocation risk analyses)

    for kind <- Widgets.kinds(), do: assert(kind.group in Widgets.groups())
  end

  # User story:
  # As the operator reading the app in German,
  # I want each widget's title in the words the boards use,
  # so that the catalogue reads as the screens do.
  #
  # Acceptance criteria:
  # - The title is an English msgid; the screen's German is the board's name.
  # - The group titles read Überblick, Performance, Allokation, Risiko and
  #   Analysen.
  test "titles are English msgids translated to the boards' German" do
    for {key, {_sizes, _group, german}} <- @slice do
      {:ok, kind} = Widgets.fetch(key)

      assert Gettext.with_locale(PortfolixirWeb.Gettext, "en", fn -> Widgets.title(key) end) ==
               kind.title

      assert Gettext.with_locale(PortfolixirWeb.Gettext, "de", fn -> Widgets.title(key) end) ==
               german
    end

    assert Gettext.with_locale(PortfolixirWeb.Gettext, "de", fn ->
             Enum.map(Widgets.groups(), &Widgets.group_title/1)
           end) == ["Überblick", "Performance", "Allokation", "Risiko", "Analysen"]
  end

  # User story:
  # As the agent composing a dashboard without reading the code,
  # I want each kind to name the API route it draws and the function behind
  # it,
  # so that I can read what a widget shows from the API itself.
  #
  # Acceptance criteria:
  # - Every source route is a route the router answers, under /api/v1, GET.
  # - Every source function exists with the arity named.
  # - A kind that takes a view names a route with a view.
  test "every source names routes the router answers and a function that exists" do
    routes =
      MapSet.new(PortfolixirWeb.Router.__routes__(), fn route ->
        String.upcase(to_string(route.verb)) <> " " <> route.path
      end)

    for kind <- Widgets.kinds() do
      assert kind.source.routes != [], kind.key

      for route <- kind.source.routes do
        assert String.starts_with?(route, "GET /api/v1/"), "#{kind.key}: #{route}"
        assert MapSet.member?(routes, route), "#{kind.key}: #{route} is no route"
      end

      {module, fun, arity} = kind.source.function
      assert Code.ensure_loaded?(module), inspect(module)

      assert function_exported?(module, fun, arity),
             "#{kind.key}: #{inspect(kind.source.function)}"

      if kind.scope == :view do
        assert Enum.any?(kind.source.routes, &(&1 =~ ":view_id" or &1 =~ "/portfolios/")),
               kind.key
      else
        assert kind.scope == :none, kind.key
      end
    end

    assert Widgets.function_name({Movers, :read, 3}) ==
             "Portfolixir.Portfolios.Performance.Movers.read/3"
  end

  # User story:
  # As the operator reading the widget „Verkaufsrückblick“ on the Overview,
  # I want it to draw what today's card „Abgeschlossene Trades“ draws,
  # so that the widget is today's card in a frame (ADR-0062 §12), and the
  # agent reads the same trades from the route the registry names.
  #
  # Acceptance criteria:
  # - Its source is the realized-gains read: GET /api/v1/realized_gains and
  #   RealizedGains.newest_trades/2, the function the card reads.
  test "the sale review draws the realized gains' newest closed trades" do
    {:ok, review} = Widgets.fetch("sale_review")

    assert review.source.routes == ["GET /api/v1/realized_gains"]
    assert review.source.function == {Portfolixir.Portfolios.RealizedGains, :newest_trades, 2}
    assert review.source.note =~ "newest"
    assert review.scope == :none
    assert review.period == :none
  end

  test "the movers name both their routes and Movers.read/3" do
    {:ok, movers} = Widgets.fetch("movers")

    assert movers.source.routes == ["GET /api/v1/movers", "GET /api/v1/views/:view_id/movers"]
    assert movers.source.function == {Movers, :read, 3}
    assert movers.scope == :view
  end

  # User story:
  # As the operator switching the period above a dashboard,
  # I want each widget to follow it by a rule its kind states,
  # so that a widget without the period says which one it shows instead.
  #
  # Acceptance criteria:
  # - The dashboard's periods are 1d 1w 1m 3m ytd 1y 3y max, Wealth's keys,
  #   with 1y the default.
  # - Tops and flops map 1d→day, 1w→week, 1m→month, 3m→quarter, ytd→ytd and
  #   1y, 3y, max→1y (their own window keys); 3m, 3y and max are marked as
  #   translated.
  # - Performance takes ytd, 1y, 3y and max as its period and the four short
  #   periods as the trailing range ending today.
  # - A kind without a period takes none.
  test "period rules: none, the movers' windows, performance's periods and ranges" do
    assert Widgets.periods() == ~w(1d 1w 1m 3m ytd 1y 3y max)
    assert Widgets.default_period() == "1y"

    {:ok, movers} = Widgets.fetch("movers")

    assert movers.period == %{
             periods: Widgets.periods(),
             param: "window",
             values: %{
               "1d" => "day",
               "1w" => "week",
               "1m" => "month",
               "3m" => "quarter",
               "ytd" => "ytd",
               "1y" => "1y",
               "3y" => "1y",
               "max" => "1y"
             },
             ranges: [],
             translated: ~w(3m 3y max)
           }

    for {_period, window} <- movers.period.values,
        do: assert(window in Movers.windows())

    {:ok, performance} = Widgets.fetch("performance")
    assert performance.period.periods == Widgets.periods()
    assert performance.period.param == "period"

    assert performance.period.values == %{
             "ytd" => "ytd",
             "1y" => "1y",
             "3y" => "3y",
             "max" => "max"
           }

    assert performance.period.ranges == ~w(1d 1w 1m 3m)
    assert performance.period.translated == []

    for {_period, value} <- performance.period.values,
        do: assert(value in Performance.periods())

    # „Gesamtwert“ draws, at S, the change the performance read gives for
    # its period (Sprint 31 D8, the width walk's finding 3): it takes the
    # dashboard periods by the same rule.
    {:ok, total_value} = Widgets.fetch("total_value")
    assert total_value.period == performance.period

    for key <- Widgets.keys() -- ~w(movers performance total_value) do
      {:ok, kind} = Widgets.fetch(key)
      assert kind.period == :none, key
    end
  end

  test "source_params/3 turns a dashboard period into the source route's parameters" do
    today = ~D[2026-11-21]

    assert Widgets.source_params("movers", "3m", today) == {:ok, %{"window" => "quarter"}}
    assert Widgets.source_params("movers", "max", today) == {:ok, %{"window" => "1y"}}
    assert Widgets.source_params("performance", "ytd", today) == {:ok, %{"period" => "ytd"}}

    assert Widgets.source_params("total_value", "1m", today) ==
             Widgets.source_params("performance", "1m", today)

    assert Widgets.source_params("performance", "1d", today) ==
             {:ok, %{"from" => "2026-11-20", "to" => "2026-11-21"}}

    assert Widgets.source_params("performance", "1w", today) ==
             {:ok, %{"from" => "2026-11-14", "to" => "2026-11-21"}}

    assert Widgets.source_params("performance", "1m", today) ==
             {:ok, %{"from" => "2026-10-21", "to" => "2026-11-21"}}

    assert Widgets.source_params("performance", "3m", ~D[2026-05-31]) ==
             {:ok, %{"from" => "2026-02-28", "to" => "2026-05-31"}}

    assert Widgets.source_params("crashes", "1y", today) == {:error, :no_period}
    assert Widgets.source_params("movers", "5y", today) == {:error, :unknown_period}
    assert Widgets.source_params("movers", "quarter", today) == {:error, :unknown_period}
    assert Widgets.source_params("nope", "1y", today) == {:error, :unknown_kind}
  end

  test "takes_period?/2 answers by string, for the kinds with a period only" do
    assert Widgets.takes_period?("movers", "3y")
    assert Widgets.takes_period?("performance", "1d")
    assert Widgets.takes_period?("total_value", "max")
    refute Widgets.takes_period?("movers", "5y")
    refute Widgets.takes_period?("crashes", "1y")
    refute Widgets.takes_period?("nope", "1y")
    refute Widgets.takes_period?("movers", :"1y")
  end
end
