defmodule Portfolixir.Dashboards.Widgets do
  @moduledoc """
  The widget registry (ADR-0062 §1, §5): every widget kind, registered once,
  in code.

  A kind holds:

    * `key` — a stable string (`"movers"`). Keys are matched against this
      list **as strings**; no atom is ever made from a stored or sent key
      (`fetch/1` takes a binary and compares it).
    * `title` — an English msgid the screen translates (`title/1`, context
      `"widget kind"`); `group` — the catalogue's topic (`group_title/1`).
    * `sizes` — the subset of `sizes/0` it supports, smallest first. `S`,
      `M`, `L` and `XL` are the grid sizes (`dimensions/1`), Apple's widget
      families small, medium, large and extra large (`family/1`; ADR-0062's
      amendment of 2026-11-25, point 3; Sprint 32 E4): one square unit of 3
      columns by 2 rows, every size a multiple of it, every size of a fixed
      height. Each size of a kind shows more of the same, never something
      else, and a size that adds nothing is not offered. **„Zeile“**
      (`row`; the amendment's point 3, Sprint 32 S2) is the size of a
      section widget: the full width, 12 columns by 1 row in the stored
      grid, so validation and the arrangement treat it as any item, and
      drawn at its content's height (`height/1`), every row after it
      starting below it. `full` is its own
      page, reached through „Ganze Ansicht“, and never a size a layout item
      may take.
    * `source` — the one existing read it draws: the `/api/v1` route
      templates (`routes`, `GET` each), the context function behind them
      (`function`, `{module, name, arity}`) and, where the widget's figures
      come from a context function with no route of its own, a `note` naming
      the nearest route. A widget's source is the registry's, never the
      layout's (§11).
    * `period` — `:none`, or the rule by which it follows the dashboard's
      period (§5): `periods` (the fixed keys of the period vocabulary it
      answers, `Portfolixir.Periods`), `param` (the source route's query
      parameter), `values` (dashboard period → the source's own value of
      `param`), `ranges` (the periods it answers as a `from`/`to` range,
      as `Portfolixir.Periods.resolve/2` spans them: ADR-0061 §3's money
      window for the short ones), `years` (the periods it answers as
      `year=`, `year:YYYY` standing for every keyed year), `keyed` (a
      keyed period answered with the source's own value of `param`, as
      `values`) and `translated` (the
      periods it answers with a different span, which the screen says:
      „3M → Quartal“).
    * `scope` — `:view` when it takes a view (all of today's portfolio reads
      do), else `:none`.
    * `compact` — `true`: a kind is registered only with its compact form
      (§1, §6).

  The dashboard's periods are `periods/0`, the fixed keys of the period
  vocabulary (`Portfolixir.Periods.keys/0`; ADR-0062's amendment of
  2026-11-25, point 6; Sprint 32 T1), with `"1y"` the default as on Wealth;
  a keyed one, `year:YYYY`, is taken wherever a fixed one is.

  Nothing here reads data: a widget carries no figure of its own.
  """

  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Periods

  @periods Periods.keys()
  @default_period "1y"

  @sizes ~w(S M L XL row full)
  # „Zeile“ (`row`, Sprint 32 S2): 12 × 1 in the stored grid, drawn at its
  # content's height.
  @dimensions %{"S" => {3, 2}, "M" => {6, 2}, "L" => {6, 4}, "XL" => {12, 4}, "row" => {12, 1}}
  @families %{"S" => "small", "M" => "medium", "L" => "large", "XL" => "extra large"}

  @groups ~w(overview performance allocation risk analyses)

  # ADR-0061's windows: 1T to Tag, 1W to Woche, 1M to Monat, 3M to Quartal,
  # YTD to YTD, 1J, 3J and Max to 1J (ADR-0062 §5); by the amendment of
  # 2026-11-25, point 6, mtd and prev_month to Monat, qtd, prev_quarter
  # and q1 to q4 to Quartal, prev_year and year:YYYY to 1J. The two
  # rolling keys the vocabulary adds take the nearest window: 6M the
  # quarter, 5J the year, as 3J does (Sprint 32 T1).
  @movers_period %{
    periods: @periods,
    param: "window",
    values: %{
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
    },
    ranges: [],
    years: [],
    keyed: %{"year:YYYY" => "1y"},
    # An own period (`saved:<id>`, Sprint 32 T2) is read as the window its
    # span's days come nearest to: up to 1 day Tag, up to 7 Woche, up to
    # 31 Monat, up to 184 Quartal (6M is Quartal too), else 1J.
    spans: [
      %{window: "day", up_to_days: 1},
      %{window: "week", up_to_days: 7},
      %{window: "month", up_to_days: 31},
      %{window: "quarter", up_to_days: 184}
    ],
    spans_else: "1y",
    # Tag, Woche and Monat are calendar windows to date (ADR-0061 §3),
    # not the spans ending today that performance reads for 1T, 1W and
    # 1M, so the screen says them too: „folgt · 1W → Woche“ (Sprint 31
    # closing act, correctness lens C1); a previous month, quarter or year
    # is read as the current window, and says so.
    translated: (@periods -- ~w(ytd 1y)) ++ ["year:YYYY", "saved:<id>"]
  }

  # The performance family takes ytd, 1y, 3y, 5y and max as `period=`, a
  # year as `year=` and any span as `from=`/`to=`
  # (`PortfolixirWeb.Api.V1.PeriodParam`), so every other key is the range
  # `Portfolixir.Periods` spans for it: every period is its own, none
  # translated.
  @performance_period %{
    periods: @periods,
    param: "period",
    values: %{"ytd" => "ytd", "1y" => "1y", "3y" => "3y", "5y" => "5y", "max" => "max"},
    ranges: ~w(1d 1w 1m 3m 6m mtd prev_month qtd prev_quarter q1 q2 q3 q4 saved:<id>),
    years: ~w(prev_year year:YYYY),
    keyed: %{},
    spans: [],
    spans_else: nil,
    translated: []
  }

  # Sprint 32 S5: „Crash-Chart“ draws the crash benchmark's closes from the
  # period's first day to today, every period a range ending today, the
  # quotes route's from=/to=; none translated.
  @crash_chart_period %{
    periods: @periods,
    param: "from",
    values: %{},
    ranges: @periods ++ ["saved:<id>"],
    years: ~w(prev_year year:YYYY),
    keyed: %{},
    spans: [],
    spans_else: nil,
    translated: [],
    whole_ranges: true
  }

  @kinds [
    %{
      key: "total_value",
      title: "Total value",
      group: "overview",
      # Board 01 ④: S the figure and its change, M the figure with two
      # companions, L the figure with its course (Sprint 32 E4).
      sizes: ~w(S M L),
      source: %{
        routes: [
          "GET /api/v1/valuation",
          "GET /api/v1/views/:view_id/valuation",
          "GET /api/v1/performance",
          "GET /api/v1/views/:view_id/performance"
        ],
        function: {Portfolixir.Portfolios.Valuation, :for_view, 2},
        note:
          "The total and the cash quote are the valuation read's; the change over the " <>
            "item's period is the performance read's, GET /api/v1/performance with the " <>
            "period's parameters (Sprint 31 closing act, F2)."
      },
      # At S it draws the change the performance read gives for its
      # period, so it takes the dashboard periods by performance's rule
      # (Sprint 31 D8): its head names the period, its menu pins one.
      period: @performance_period,
      scope: :view,
      compact: true
    },
    %{
      key: "data_quality",
      title: "Data quality",
      group: "overview",
      # S the counts, L the list (Sprint 31's M, read as L).
      sizes: ~w(S L),
      source: %{
        routes: [
          "GET /api/v1/securities",
          "GET /api/v1/transactions/cash_mismatch",
          "GET /api/v1/transactions/rate_only",
          "GET /api/v1/splits/incomplete"
        ],
        function: {Portfolixir.Catalog.DataQuality, :count, 2},
        note:
          "The counts have no route of their own: each is the length of the list " <>
            "GET /api/v1/securities?data_quality=<finding> answers (the held " <>
            "securities), and of the three ledger checks' lists."
      },
      period: :none,
      scope: :none,
      compact: true
    },
    %{
      key: "due",
      title: "Due",
      group: "overview",
      sizes: ~w(S),
      source: %{
        routes: ["GET /api/v1/events/upcoming"],
        function: {Portfolixir.Knowledge.Events, :upcoming, 1},
        note: nil
      },
      period: :none,
      scope: :none,
      compact: true
    },
    %{
      key: "off_target",
      title: "Off target",
      group: "overview",
      # S the count, L the list (Sprint 31 closing act, DS1; its M read as L).
      sizes: ~w(S L),
      source: %{
        routes: ["GET /api/v1/portfolios/:portfolio_id/allocation"],
        function: {Portfolixir.Portfolios.Allocation, :for_portfolio, 3},
        note:
          "No route of its own: the categories beyond the drift threshold of the " <>
            "allocation read with view=, per portfolio."
      },
      period: :none,
      scope: :view,
      compact: true
    },
    %{
      key: "performance",
      title: "Performance",
      group: "performance",
      # S the return and its spark, L the return and its course, XL the
      # course by category (Sprint 31's S, M and L).
      sizes: ~w(S L XL full),
      source: %{
        routes: ["GET /api/v1/performance", "GET /api/v1/views/:view_id/performance"],
        function: {Portfolixir.Portfolios.Performance, :for_view, 2},
        note: nil
      },
      period: @performance_period,
      scope: :view,
      compact: true
    },
    %{
      key: "movers",
      title: "Tops and flops",
      group: "performance",
      sizes: ~w(S L),
      source: %{
        routes: ["GET /api/v1/movers", "GET /api/v1/views/:view_id/movers"],
        function: {Portfolixir.Portfolios.Performance.Movers, :read, 3},
        note: nil
      },
      period: @movers_period,
      scope: :view,
      compact: true
    },
    %{
      key: "snapshots",
      title: "Snapshots",
      group: "performance",
      sizes: ~w(S M),
      source: %{
        routes: [
          "GET /api/v1/snapshots",
          "GET /api/v1/portfolios/:portfolio_id/snapshots/:id/comparison"
        ],
        function: {Portfolixir.Portfolios.Snapshots, :list_snapshots, 1},
        note:
          "The latest snapshot of the list and its comparison in the first portfolio: " <>
            "the real TTWROR since its as_of date and its daily chain."
      },
      period: :none,
      scope: :none,
      compact: true
    },
    %{
      key: "allocation_drift",
      title: "Allocation and drift",
      group: "allocation",
      # Sprint 31's M and T both read as L; T was M, only narrower (board 07
      # ①, finding 6).
      sizes: ~w(L),
      source: %{
        routes: ["GET /api/v1/portfolios/:portfolio_id/allocation"],
        function: {Portfolixir.Portfolios.Allocation, :for_portfolio, 3},
        note: "The allocation read is portfolio-bound; its view= narrows it to a view."
      },
      period: :none,
      scope: :view,
      compact: true
    },
    %{
      key: "crashes",
      title: "Crashes compared",
      group: "risk",
      # Sprint 31's L (read as XL) showed what its M did, with space (board
      # 07 ①, finding 6): not offered.
      sizes: ~w(L),
      source: %{
        routes: ["GET /api/v1/crashes", "GET /api/v1/crashes/:key/rankings"],
        function: {Portfolixir.Crashes, :list_windows, 0},
        note:
          "The windows newest first, each with the losers' list over universe=held or " <>
            "universe=catalogue: its reference.return and its first entry."
      },
      period: :none,
      scope: :none,
      compact: true
    },
    %{
      key: "bitcoin_cycle",
      title: "Bitcoin cycle",
      group: "analyses",
      # XL is Sprint 31's L; Lane L draws the cycle chart in it (plan L3).
      sizes: ~w(L XL full),
      source: %{
        routes: ["GET /api/v1/securities/:security_id/cycles"],
        function: {Portfolixir.Catalog.SecurityCycles, :for_security, 2},
        note: nil
      },
      period: :none,
      scope: :none,
      compact: true
    },
    %{
      key: "sale_review",
      title: "Sale review",
      group: "analyses",
      # „Zeile“ (Sprint 32 S2): the Overview's card „Closed trades“ is a
      # section of today's screens, its list of five one band across the
      # page; the first kind to take the size before Lane W's sections.
      sizes: ~w(L row),
      source: %{
        routes: ["GET /api/v1/realized_gains"],
        function: {Portfolixir.Portfolios.RealizedGains, :newest_trades, 2},
        note:
          "Today's card „Closed trades“ in a frame (ADR-0062 §12): the newest closed " <>
            "trades of the realized-gains read, the rows GET /api/v1/realized_gains " <>
            "answers under trades, newest close first, with its exclusions."
      },
      period: :none,
      scope: :none,
      compact: true
    },
    # --- S32 S5 begin ---
    %{
      key: "distance_to_high",
      title: "Distance to high",
      group: "analyses",
      # Sprint 32 S5 (I61; boards 03, 05): the scope's holdings with their
      # distance to the 52-week high and their largest drawdown, from the
      # per-security metrics read (ADR-0047); L a list, XL a longer one.
      sizes: ~w(L XL),
      source: %{
        routes: [
          "GET /api/v1/valuation",
          "GET /api/v1/views/:view_id/valuation",
          "GET /api/v1/securities/:security_id/metrics"
        ],
        function: {Portfolixir.Catalog.SecurityMetrics, :for_security, 2},
        note:
          "The securities are the positions the scope holds today (the valuation read's, " <>
            "a view's or every depot's); one metrics read per security: " <>
            "metrics.distance_to_extremes.distance_to_high_pct and its high, and " <>
            "metrics.max_drawdown[\"365d\"].value; listed by the distance, ascending, a " <>
            "refused one last."
      },
      period: :none,
      scope: :view,
      compact: true
    },
    %{
      key: "crash_chart",
      title: "Crash chart",
      group: "risk",
      # Sprint 32 S5 (I61; board 11 ①, ②): the crash benchmark's closes with
      # every crash window shaded and named; L and XL, XL the year, a copy
      # pinned to 1M the zoom.
      sizes: ~w(L XL),
      source: %{
        routes: ["GET /api/v1/crashes", "GET /api/v1/securities/:security_id/quotes"],
        function: {Portfolixir.Crashes, :list_windows, 0},
        note:
          "The windows of GET /api/v1/crashes that overlap the period (a detected one from " <>
            "its start to recovered_on, or to today while provisional; a manual one to its " <>
            "trough) over the crash benchmark's quotes from the period's from to its to, " <>
            "their adjusted_close."
      },
      period: @crash_chart_period,
      scope: :none,
      compact: true
    },
    %{
      key: "rebounders",
      title: "Rebounders after crashes",
      group: "risk",
      # Sprint 32 S5 (I61; board 11 ⑤; D-15): the rebounders' lists of the
      # last three ended crash windows side by side; L three rows, XL five.
      sizes: ~w(L XL),
      source: %{
        routes: [
          "GET /api/v1/crashes",
          "GET /api/v1/crashes/:key/rankings",
          "GET /api/v1/views/:view_id/valuation"
        ],
        function: {Portfolixir.Crashes, :rankings, 3},
        note:
          "The three newest windows of GET /api/v1/crashes whose fall has ended, each its " <>
            "list=rebounders over universe=view:<id> (the widget's view; held without one) " <>
            "or universe=catalogue, limit=5; a name in more than one list is marked by name " <>
            "only, nothing scored across the windows."
      },
      period: :none,
      scope: :view,
      compact: true
    },
    # --- S32 S5 end ---
    # --- S32 W2 begin ---
    %{
      key: "summary_line",
      title: "Key figures line",
      group: "allocation",
      # Sprint 32 W2 (I57; board 02 ②): the summary line that heads
      # Wealth's tab „Allokation & Ziele“, a section widget in the size
      # „Zeile“; not W1's „Kennzahlen“ (`wealth_key_figures`). Its TTWROR
      # is the performance read's over the period, by performance's rule.
      sizes: ~w(row),
      source: %{
        routes: [
          "GET /api/v1/valuation",
          "GET /api/v1/views/:view_id/valuation",
          "GET /api/v1/performance",
          "GET /api/v1/views/:view_id/performance"
        ],
        function: {Portfolixir.Portfolios.Valuation, :for_view, 2},
        note:
          "The total incl. cash and the cash quote are the valuation read's; the TTWROR " <>
            "is the performance read's over the item's period, GET /api/v1/performance " <>
            "with the period's parameters."
      },
      period: @performance_period,
      scope: :view,
      compact: true
    },
    %{
      key: "allocation",
      title: "Allocation",
      group: "allocation",
      # Sprint 32 W2 (I57; board 02 ②): Wealth's section „Allokation“ —
      # tree or positions, the sunburst, the drift table with the
      # display-only hints of ADR-0023, the classification choice — a
      # section widget in the size „Zeile“.
      sizes: ~w(row),
      source: %{
        routes: ["GET /api/v1/portfolios/:portfolio_id/allocation"],
        function: {Portfolixir.Portfolios.Allocation, :for_portfolio, 3},
        note:
          "The allocation read of the first portfolio, as Wealth reads it: " <>
            "classification_id the tree picked (the default steering tree until one is), " <>
            "view= the widget's view; min_drift= is the drift chips'."
      },
      period: :none,
      scope: :view,
      compact: true
    },
    # --- S32 W2 end ---
    # --- S32 W3 begin ---
    %{
      key: "snapshot_comparison",
      title: "Comparison against a snapshot",
      group: "performance",
      # Sprint 32 W3 (I57; board 02 ②): the comparison that heads Wealth's
      # tab „Snapshots“ (ADR-0027), a section widget in the size „Zeile“;
      # a snapshot carries its own scope, so it takes no view.
      sizes: ~w(row),
      source: %{
        routes: [
          "GET /api/v1/snapshots",
          "GET /api/v1/portfolios/:portfolio_id/snapshots/:id/comparison"
        ],
        function: {Portfolixir.Portfolios.SnapshotComparison, :for_snapshot, 2},
        note:
          "The snapshot compared is the newest of GET /api/v1/snapshots until the list " <>
            "picks another; its comparison in the first portfolio, as the Snapshots page " <>
            "reads it."
      },
      period: :none,
      scope: :none,
      compact: true
    },
    %{
      key: "snapshot_list",
      title: "Snapshot list",
      group: "performance",
      # Sprint 32 W3 (I57; board 02 ②): the tab's list of snapshots; a
      # snapshot is made and deleted on the tab, linked („Neuer Snapshot →“).
      sizes: ~w(row),
      source: %{
        routes: ["GET /api/v1/snapshots"],
        function: {Portfolixir.Portfolios.Snapshots, :list_snapshots, 1},
        note: nil
      },
      period: :none,
      scope: :none,
      compact: true
    },
    # --- S32 W3 end ---
    # --- S32 W4 begin ---
    %{
      key: "own_rules",
      title: "Own rules",
      group: "risk",
      # Sprint 32 W4 (I57; board 02 ②): the operator's own rules and their
      # findings (ADR-0049 §9); the rule dialog stays on the Risk tab.
      sizes: ~w(row),
      source: %{
        routes: [
          "GET /api/v1/portfolios/:portfolio_id/policy_findings",
          "GET /api/v1/portfolios/:portfolio_id/policy_rules"
        ],
        function: {Portfolixir.Portfolios.PolicyFindings, :for_portfolio, 2},
        note:
          "The findings of the rules in force for the widget's view, breached and " <>
            "undetermined first, with view=; the rules' list for the scheduled and the " <>
            "retired ones."
      },
      period: :none,
      scope: :view,
      compact: true
    },
    %{
      key: "key_figures",
      title: "Portfolio metrics",
      group: "risk",
      # Sprint 32 W4: the portfolio metrics of the Risk tab (ADR-0047 §3);
      # M the volatility, the drawdown and the risk-adjusted return.
      sizes: ~w(M row),
      source: %{
        routes: ["GET /api/v1/portfolios/:portfolio_id/risk"],
        function: {Portfolixir.Portfolios.Risk, :for_portfolio, 2},
        note:
          "metrics of the risk read with view=: volatility, max_drawdown and " <>
            "risk_adjusted_return of the window 365d, and correlations."
      },
      period: :none,
      scope: :view,
      compact: true
    },
    %{
      key: "crash_section",
      title: "Crashes",
      group: "risk",
      # Sprint 32 W4: the Risk tab's whole section „Crashes“ (ADR-0058 §9);
      # „Crashes im Vergleich“ (`crashes`) stays its compact relative.
      sizes: ~w(row),
      source: %{
        routes: [
          "GET /api/v1/crashes",
          "GET /api/v1/crashes/:key/rankings",
          "GET /api/v1/views/:view_id/performance"
        ],
        function: {Portfolixir.Crashes, :rankings, 3},
        note:
          "The window picked (the newest until one is), its list (losers, winners or " <>
            "rebounders) over universe=view:<id> (held without a view) or catalogue; the " <>
            "view's first booking day, from its performance read, says whether Holdings " <>
            "can show the window."
      },
      period: :none,
      scope: :view,
      compact: true
    },
    %{
      key: "top_holdings",
      title: "Largest single names",
      group: "risk",
      # Sprint 32 W4: the lens's Top-N single names, generic thresholds.
      sizes: ~w(row),
      source: %{
        routes: ["GET /api/v1/portfolios/:portfolio_id/risk"],
        function: {Portfolixir.Portfolios.Risk, :for_portfolio, 2},
        note: "top_holdings of the risk read with view=, each weight on the steerable basis."
      },
      period: :none,
      scope: :view,
      compact: true
    },
    %{
      key: "concentration",
      title: "Concentration risk",
      group: "risk",
      # Sprint 32 W4: the HHI with its band; S the figure alone.
      sizes: ~w(S row),
      source: %{
        routes: ["GET /api/v1/portfolios/:portfolio_id/risk"],
        function: {Portfolixir.Portfolios.Risk, :for_portfolio, 2},
        note: "hhi of the risk read with view=: its value and band."
      },
      period: :none,
      scope: :view,
      compact: true
    },
    %{
      key: "asset_class_limits",
      title: "Asset-class caps",
      group: "risk",
      # Sprint 32 W4: the asset-class caps and the correlations' table.
      sizes: ~w(row),
      source: %{
        routes: ["GET /api/v1/portfolios/:portfolio_id/risk"],
        function: {Portfolixir.Portfolios.Risk, :for_portfolio, 2},
        note:
          "asset_class_caps and asset_class_violations of the risk read (none " <>
            "configured on the screen), and metrics.correlations."
      },
      period: :none,
      scope: :view,
      compact: true
    }
    # --- S32 W4 end ---
  ]

  @by_key Map.new(@kinds, &{&1.key, &1})
  @keys Enum.map(@kinds, & &1.key)

  @type size :: String.t()
  @type period_rule ::
          :none
          | %{
              periods: [String.t()],
              param: String.t(),
              values: %{String.t() => String.t()},
              ranges: [String.t()],
              years: [String.t()],
              keyed: %{String.t() => String.t()},
              spans: [%{window: String.t(), up_to_days: pos_integer()}],
              spans_else: String.t() | nil,
              translated: [String.t()]
            }
  @type kind :: %{
          key: String.t(),
          title: String.t(),
          group: String.t(),
          sizes: [size()],
          source: %{routes: [String.t()], function: mfa(), note: String.t() | nil},
          period: period_rule(),
          scope: :view | :none,
          compact: true
        }

  @doc "Every registered kind, in the catalogue's order."
  @spec kinds() :: [kind()]
  def kinds, do: @kinds

  @doc "Every registered kind's key, in the catalogue's order."
  @spec keys() :: [String.t()]
  def keys, do: @keys

  @doc """
  The kind registered under `key`, matched as a string: `{:ok, kind}`, or
  `:error` for an unknown key and for anything that is not a binary.
  """
  @spec fetch(term()) :: {:ok, kind()} | :error
  def fetch(key) when is_binary(key), do: Map.fetch(@by_key, key)
  def fetch(_key), do: :error

  @doc "The sizes a kind may support: the four families, `row` and `full`."
  @spec sizes() :: [size()]
  def sizes, do: @sizes

  @doc """
  The width and height on the 12-column grid of a grid size, or `:error`
  for `full` (a page, not a grid size) and anything else.
  """
  @spec dimensions(term()) :: {:ok, {pos_integer(), pos_integer()}} | :error
  def dimensions(size) when is_binary(size), do: Map.fetch(@dimensions, size)
  def dimensions(_size), do: :error

  @doc """
  The widget family a grid size names (Apple's WidgetKit families):
  `"small"`, `"medium"`, `"large"`, `"extra large"`; `nil` for anything
  else.
  """
  @spec family(term()) :: String.t() | nil
  def family(size) when is_binary(size), do: Map.get(@families, size)
  def family(_size), do: nil

  @doc """
  How a grid size is drawn: `"fixed"`, its rows' fixed height (the
  families), or `"content"`, as tall as its content (`row`, „Zeile“);
  `nil` for anything else.
  """
  @spec height(term()) :: String.t() | nil
  def height("row"), do: "content"
  def height(size) when is_map_key(@families, size), do: "fixed"
  def height(_size), do: nil

  @doc "The catalogue's groups, in its order."
  @spec groups() :: [String.t()]
  def groups, do: @groups

  @doc """
  The periods above every dashboard: the fixed keys of the period
  vocabulary (`Portfolixir.Periods.keys/0`, ADR-0062 §5 as amended on
  2026-11-25).
  """
  @spec periods() :: [String.t()]
  def periods, do: @periods

  @doc "The dashboard's default period, Wealth's: one year."
  @spec default_period() :: String.t()
  def default_period, do: @default_period

  @doc """
  Whether the kind `key` answers the dashboard period `period`: a key of
  the vocabulary by its form (`Portfolixir.Periods.key?/1`), for a kind
  with a period rule.
  """
  @spec takes_period?(term(), term()) :: boolean()
  def takes_period?(key, period) when is_binary(period) do
    case fetch(key) do
      {:ok, %{period: %{periods: periods}}} -> period in periods or Periods.key?(period)
      _none -> false
    end
  end

  def takes_period?(_key, _period), do: false

  @doc """
  Whether the kind `key` answers `period` with another span than the
  period's own, which the screen says („folgt · 3M → Quartal“).
  """
  @spec translated?(term(), term()) :: boolean()
  def translated?(key, period) do
    case fetch(key) do
      {:ok, %{period: %{translated: translated}}} when is_binary(period) ->
        period in translated or (keyed?(period) and "year:YYYY" in translated) or
          (Periods.saved_id(period) != :error and "saved:<id>" in translated)

      _none ->
        false
    end
  end

  @doc """
  The query parameters of the kind's source route for the dashboard period
  `period` on `today`: `{:ok, %{"window" => "quarter"}}`, `{:ok,
  %{"period" => "ytd"}}`, `{:ok, %{"year" => "2025"}}`, or for a range
  `{:ok, %{"from" => "2026-10-22", "to" => "2026-11-21"}}`, as
  `Portfolixir.Periods.resolve/3` spans it (`saved`, where a stored
  period is looked up, as there). `{:error, :no_period}` for a
  kind that takes none, `{:error, :unknown_period}` for a period it does
  not answer, or one that has not begun on `today`, `{:error,
  :unknown_kind}` for an unknown key.
  """
  @spec source_params(term(), term(), Date.t(), :stored | [Periods.SavedPeriod.t()]) ::
          {:ok, %{String.t() => String.t()}}
          | {:error, :no_period | :unknown_period | :unknown_kind}
  def source_params(key, period, %Date{} = today, saved \\ :stored) do
    case fetch(key) do
      :error -> {:error, :unknown_kind}
      {:ok, %{period: :none}} -> {:error, :no_period}
      {:ok, %{period: rule}} -> rule_params(rule, period, today, saved)
    end
  end

  # The period resolved first, so a quarter or a year not yet begun is no
  # period for any kind; then the rule's own value, a range or a year as
  # the vocabulary spans it.
  defp rule_params(%{param: param, values: values, keyed: keyed} = rule, period, today, saved) do
    case Periods.resolve(period, today, saved) do
      {:ok, term} ->
        cond do
          Map.has_key?(values, period) ->
            {:ok, %{param => Map.fetch!(values, period)}}

          keyed?(period) and is_map_key(keyed, "year:YYYY") ->
            {:ok, %{param => keyed["year:YYYY"]}}

          rule.spans != [] ->
            {:ok, %{param => span_window(rule, term)}}

          # Sprint 32 S5: „Crash-Chart“ reads every period as a whole range.
          Map.get(rule, :whole_ranges, false) ->
            spelled(whole_range(term, today))

          true ->
            spelled(term)
        end

      {:error, _refusal} ->
        {:error, :unknown_period}
    end
  end

  # The window an own period's span comes nearest to, by its days.
  defp span_window(%{spans: spans, spans_else: fallback}, {:range, from, to}) do
    days = Date.diff(to, from) + 1

    case Enum.find(spans, &(days <= &1.up_to_days)) do
      %{window: window} -> window
      nil -> fallback
    end
  end

  defp spelled({:range, from, to}),
    do: {:ok, %{"from" => Date.to_iso8601(from), "to" => Date.to_iso8601(to)}}

  defp spelled({:year, year}), do: {:ok, %{"year" => Integer.to_string(year)}}
  defp spelled(_key), do: {:error, :unknown_period}

  defp keyed?(period), do: is_binary(period) and String.starts_with?(period, "year:")

  # --- S32 S5 begin ---
  # A whole range from the period's first day to its last, for a kind that
  # reads a series over the period itself („Crash-Chart“): a range as the
  # vocabulary spans it; YTD from 1 January, 1J, 3J and 5J the day after
  # the date as many years back, Max from the series' floor, each to
  # today; a year from 1 January to 31 December, or to today while it runs.
  defp whole_range({:range, from, to}, _today), do: {:range, from, to}
  defp whole_range("ytd", today), do: {:range, Date.new!(today.year, 1, 1), today}
  defp whole_range("max", today), do: {:range, ~D[1900-01-01], today}

  defp whole_range({:year, year}, today),
    do: {:range, Date.new!(year, 1, 1), Enum.min([Date.new!(year, 12, 31), today], Date)}

  defp whole_range(years_back, today) when years_back in ~w(1y 3y 5y) do
    years = String.to_integer(String.trim_trailing(years_back, "y"))
    {:range, today |> Date.shift(year: -years) |> Date.add(1), today}
  end

  defp whole_range(_term, _today), do: :error
  # --- S32 S5 end ---

  @doc "`{module, name, arity}` written as Elixir names it: `Mod.fun/2`."
  @spec function_name(mfa()) :: String.t()
  def function_name({module, name, arity}),
    do: "#{inspect(module)}.#{name}/#{arity}"

  @doc "The kind's title in the current locale; `nil` for an unknown key."
  @spec title(term()) :: String.t() | nil
  def title("total_value"), do: pgettext("widget kind", "Total value")
  def title("data_quality"), do: pgettext("widget kind", "Data quality")
  def title("due"), do: pgettext("widget kind", "Due")
  def title("off_target"), do: pgettext("widget kind", "Off target")
  def title("performance"), do: pgettext("widget kind", "Performance")
  def title("movers"), do: pgettext("widget kind", "Tops and flops")
  def title("snapshots"), do: pgettext("widget kind", "Snapshots")
  def title("allocation_drift"), do: pgettext("widget kind", "Allocation and drift")
  def title("crashes"), do: pgettext("widget kind", "Crashes compared")
  def title("bitcoin_cycle"), do: pgettext("widget kind", "Bitcoin cycle")
  def title("sale_review"), do: pgettext("widget kind", "Sale review")
  def title("distance_to_high"), do: pgettext("widget kind", "Distance to high")
  def title("crash_chart"), do: pgettext("widget kind", "Crash chart")
  def title("rebounders"), do: pgettext("widget kind", "Rebounders after crashes")
  # --- S32 W2 begin ---
  def title("summary_line"), do: pgettext("widget kind", "Key figures line")
  def title("allocation"), do: pgettext("widget kind", "Allocation")
  # --- S32 W2 end ---
  # --- S32 W3 begin ---
  def title("snapshot_comparison"), do: pgettext("widget kind", "Comparison against a snapshot")
  def title("snapshot_list"), do: pgettext("widget kind", "Snapshot list")
  # --- S32 W3 end ---
  # --- S32 W4 begin ---
  def title("own_rules"), do: pgettext("widget kind", "Own rules")
  def title("key_figures"), do: pgettext("widget kind", "Portfolio metrics")
  def title("crash_section"), do: pgettext("widget kind", "Crashes")
  def title("top_holdings"), do: pgettext("widget kind", "Largest single names")
  def title("concentration"), do: pgettext("widget kind", "Concentration risk")
  def title("asset_class_limits"), do: pgettext("widget kind", "Asset-class caps")
  # --- S32 W4 end ---
  def title(_key), do: nil

  @doc "The group's title in the current locale; `nil` for an unknown group."
  @spec group_title(term()) :: String.t() | nil
  def group_title("overview"), do: pgettext("widget group", "Overview")
  def group_title("performance"), do: pgettext("widget group", "Performance")
  def group_title("allocation"), do: pgettext("widget group", "Allocation")
  def group_title("risk"), do: pgettext("widget group", "Risk")
  def group_title("analyses"), do: pgettext("widget group", "Analyses")
  def group_title(_group), do: nil
end
