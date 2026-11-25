defmodule Portfolixir.Dashboards.WidgetsTest do
  # Sprint 31 D1 (FR-60, ADR-0062 §1, §5): the widget registry. A kind is
  # registered once, in code, with its title, group, sizes, the one existing
  # read it draws, its period rule and whether it takes a view, and only with
  # its compact form. Keys are matched as strings; nothing here makes an atom.
  use ExUnit.Case, async: true
  @moduletag :sweep

  alias Portfolixir.Dashboards.Widgets
  alias Portfolixir.Periods
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.Performance.Movers

  # The slice's kinds (planning board 01 ②, the Sprint 31 brief of Lane
  # D), with the German titles the boards draw, and their sizes on Apple's
  # families since Sprint 32 E4 (families_test.exs holds why each).
  @slice %{
    "total_value" => {~w(S M L), "overview", "Gesamtwert"},
    "data_quality" => {~w(S L), "overview", "Datenqualität"},
    "due" => {~w(S), "overview", "Fällig"},
    # The list since the closing act (DS1), S the count.
    "off_target" => {~w(S L), "overview", "Abseits des Ziels"},
    "performance" => {~w(S L XL full), "performance", "Wertentwicklung"},
    "movers" => {~w(S L), "performance", "Tops und Flops"},
    "snapshots" => {~w(S M), "performance", "Snapshots"},
    "allocation_drift" => {~w(L), "allocation", "Allokation und Drift"},
    "crashes" => {~w(L), "risk", "Crashes im Vergleich"},
    "bitcoin_cycle" => {~w(L XL full), "analyses", "Bitcoin-Zyklus"},
    "sale_review" => {~w(L), "analyses", "Verkaufsrückblick"}
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
    assert Widgets.sizes() == ~w(S M L XL full)
    assert Widgets.dimensions("S") == {:ok, {3, 2}}
    assert Widgets.dimensions("M") == {:ok, {6, 2}}
    assert Widgets.dimensions("L") == {:ok, {6, 4}}
    assert Widgets.dimensions("XL") == {:ok, {12, 4}}
    assert Widgets.dimensions("full") == :error
    assert Widgets.dimensions("W") == :error
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
  # Acceptance criteria (Sprint 32 T1: the dashboard's list is the period
  # vocabulary, `Portfolixir.Periods`, with 6m and 5y added):
  # - The dashboard's periods are the vocabulary's fixed keys, with 1y the
  #   default.
  # - Tops and flops map 1d→day, 1w→week, 1m→month, 3m and 6m→quarter,
  #   ytd→ytd and 1y, 3y, 5y, max→1y; by ADR-0062's amendment of
  #   2026-11-25, point 6, mtd and prev_month→month, qtd, prev_quarter and
  #   q1 to q4→quarter, prev_year and year:YYYY→1y. Every key but ytd and
  #   1y is marked as translated (Tag, Woche and Monat are calendar windows
  #   to date, not the trailing spans performance reads; a previous month
  #   or quarter is read as the current one), and the screen says it.
  # - Performance takes ytd, 1y, 3y, 5y and max as its period, every other
  #   span as from/to (ADR-0061 §3's money window for the short ones),
  #   prev_year and year:YYYY as year=: every period is its own, none
  #   translated.
  # - A kind without a period takes none.
  test "period rules: none, the movers' windows, performance's periods and ranges" do
    assert Widgets.periods() == Periods.keys()
    assert "6m" in Widgets.periods() and "5y" in Widgets.periods()
    assert Widgets.default_period() == "1y"

    {:ok, movers} = Widgets.fetch("movers")

    assert movers.period.periods == Widgets.periods()
    assert movers.period.param == "window"

    assert movers.period.values == %{
             "1d" => "day",
             "1w" => "week",
             "1m" => "month",
             "3m" => "quarter",
             "6m" => "quarter",
             "1y" => "1y",
             "3y" => "1y",
             "5y" => "1y",
             "max" => "1y",
             "mtd" => "month",
             "prev_month" => "month",
             "qtd" => "quarter",
             "prev_quarter" => "quarter",
             "q1" => "quarter",
             "q2" => "quarter",
             "q3" => "quarter",
             "q4" => "quarter",
             "ytd" => "ytd",
             "prev_year" => "1y"
           }

    assert movers.period.keyed == %{"year:YYYY" => "1y"}
    assert movers.period.ranges == []
    assert movers.period.years == []
    assert movers.period.translated == (Widgets.periods() -- ~w(ytd 1y)) ++ ["year:YYYY"]

    for {_period, window} <- movers.period.values,
        do: assert(window in Movers.windows())

    {:ok, performance} = Widgets.fetch("performance")
    assert performance.period.periods == Widgets.periods()
    assert performance.period.param == "period"

    assert performance.period.values == %{
             "ytd" => "ytd",
             "1y" => "1y",
             "3y" => "3y",
             "5y" => "5y",
             "max" => "max"
           }

    assert performance.period.ranges ==
             ~w(1d 1w 1m 3m 6m mtd prev_month qtd prev_quarter q1 q2 q3 q4)

    assert performance.period.years == ~w(prev_year year:YYYY)
    assert performance.period.keyed == %{}
    assert performance.period.translated == []

    for {_period, value} <- performance.period.values,
        do: assert(value in Performance.periods())

    # Every fixed key is answered exactly once by each rule.
    for rule <- [movers.period, performance.period] do
      answered = Map.keys(rule.values) ++ rule.ranges ++ (rule.years -- ["year:YYYY"])
      assert Enum.sort(answered) == Enum.sort(Widgets.periods())
    end

    # „Gesamtwert“ draws, at S, the change the performance read gives for
    # its period (Sprint 31 D8, the width walk's finding 3): it takes the
    # dashboard periods by the same rule.
    {:ok, total_value} = Widgets.fetch("total_value")
    assert total_value.period == performance.period

    # A kind that takes performance's period rule names the routes the
    # rule's parameters are for (Sprint 31 closing act, F2): the change
    # „Gesamtwert“ draws is GET /api/v1/performance's.
    for kind <- [total_value, performance],
        route <- ["GET /api/v1/performance", "GET /api/v1/views/:view_id/performance"] do
      assert route in kind.source.routes, "#{kind.key}: #{route}"
    end

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

    # ADR-0061 §3's money window `S + 1` to `T` (the range's baseline is
    # the close of the day before `from`): 1T is today alone, from the
    # close before it; 1W the seven days after T − 7; 1M and 3M the days
    # after the date one and three months back (Sprint 31 closing act,
    # correctness lens C1, money lens MO1).
    assert Widgets.source_params("performance", "1d", today) ==
             {:ok, %{"from" => "2026-11-21", "to" => "2026-11-21"}}

    assert Widgets.source_params("performance", "1w", today) ==
             {:ok, %{"from" => "2026-11-15", "to" => "2026-11-21"}}

    assert Widgets.source_params("performance", "1m", today) ==
             {:ok, %{"from" => "2026-10-22", "to" => "2026-11-21"}}

    assert Widgets.source_params("performance", "3m", ~D[2026-05-31]) ==
             {:ok, %{"from" => "2026-03-01", "to" => "2026-05-31"}}

    # Sprint 32 T1: the new keys, as `Portfolixir.Periods` resolves them.
    assert Widgets.source_params("performance", "5y", today) == {:ok, %{"period" => "5y"}}

    assert Widgets.source_params("performance", "6m", today) ==
             {:ok, %{"from" => "2026-05-22", "to" => "2026-11-21"}}

    assert Widgets.source_params("performance", "mtd", today) ==
             {:ok, %{"from" => "2026-11-01", "to" => "2026-11-21"}}

    assert Widgets.source_params("performance", "prev_quarter", today) ==
             {:ok, %{"from" => "2026-07-01", "to" => "2026-09-30"}}

    assert Widgets.source_params("performance", "prev_year", today) == {:ok, %{"year" => "2025"}}
    assert Widgets.source_params("performance", "year:2023", today) == {:ok, %{"year" => "2023"}}
    assert Widgets.source_params("movers", "prev_month", today) == {:ok, %{"window" => "month"}}
    assert Widgets.source_params("movers", "q1", today) == {:ok, %{"window" => "quarter"}}
    assert Widgets.source_params("movers", "6m", today) == {:ok, %{"window" => "quarter"}}
    assert Widgets.source_params("movers", "5y", today) == {:ok, %{"window" => "1y"}}
    assert Widgets.source_params("movers", "year:2023", today) == {:ok, %{"window" => "1y"}}

    # A quarter or a year not yet begun is no period any kind answers.
    assert Widgets.source_params("performance", "year:2027", today) == {:error, :unknown_period}

    assert Widgets.source_params("movers", "year:2027", ~D[2026-11-21]) ==
             {:error, :unknown_period}

    assert Widgets.source_params("performance", "q2", ~D[2026-03-31]) == {:error, :unknown_period}

    assert Widgets.source_params("crashes", "1y", today) == {:error, :no_period}
    assert Widgets.source_params("movers", "quarter", today) == {:error, :unknown_period}
    assert Widgets.source_params("nope", "1y", today) == {:error, :unknown_kind}
  end

  test "takes_period?/2 answers by string, for the kinds with a period only" do
    assert Widgets.takes_period?("movers", "3y")
    assert Widgets.takes_period?("performance", "1d")
    assert Widgets.takes_period?("total_value", "max")
    assert Widgets.takes_period?("movers", "5y")
    assert Widgets.takes_period?("movers", "q3")
    assert Widgets.takes_period?("performance", "year:2024")
    refute Widgets.takes_period?("movers", "quarter")
    refute Widgets.takes_period?("crashes", "1y")
    refute Widgets.takes_period?("nope", "1y")
    refute Widgets.takes_period?("movers", :"1y")
  end

  test "translated?/2 marks what tops and flops read with another span" do
    for key <-
          ~w(1d 1w 1m 3m 6m 3y 5y max mtd prev_month qtd prev_quarter q1 q4 prev_year year:2024),
        do: assert(Widgets.translated?("movers", key), key)

    refute Widgets.translated?("movers", "ytd")
    refute Widgets.translated?("movers", "1y")
    refute Widgets.translated?("performance", "mtd")
    refute Widgets.translated?("performance", "year:2024")
    refute Widgets.translated?("crashes", "1y")
  end
end
