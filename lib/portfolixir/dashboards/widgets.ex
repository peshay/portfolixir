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
      else, and a size that adds nothing is not offered. `full` is its own
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

  @sizes ~w(S M L XL full)
  @dimensions %{"S" => {3, 2}, "M" => {6, 2}, "L" => {6, 4}, "XL" => {12, 4}}
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
      sizes: ~w(L),
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
    }
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

  @doc "The sizes a kind may support: the four grid sizes and `full`."
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
