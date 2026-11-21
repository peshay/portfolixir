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
    * `sizes` — the subset of `sizes/0` it supports. `S`, `W`, `M`, `T` and
      `L` are grid sizes (`dimensions/1`); `full` is its own page, reached
      through „Ganze Ansicht“, and never a size a layout item may take.
    * `source` — the one existing read it draws: the `/api/v1` route
      templates (`routes`, `GET` each), the context function behind them
      (`function`, `{module, name, arity}`) and, where the widget's figures
      come from a context function with no route of its own, a `note` naming
      the nearest route. A widget's source is the registry's, never the
      layout's (§11).
    * `period` — `:none`, or the rule by which it follows the dashboard's
      period (§5): `periods` (the dashboard periods it answers), `param`
      (the source route's query parameter), `values` (dashboard period →
      the source's own value of `param`), `ranges` (the dashboard periods
      it answers as the trailing `from`/`to` range ending today, for a route
      that takes one) and `translated` (the dashboard periods it answers
      with a different span, which the screen says: „3M → Quartal“).
    * `scope` — `:view` when it takes a view (all of today's portfolio reads
      do), else `:none`.
    * `compact` — `true`: a kind is registered only with its compact form
      (§1, §6).

  The dashboard's periods are `periods/0`, the keys Wealth uses for its
  own (`Portfolixir.Portfolios.Performance.periods/0`), with `"1y"` the
  default as on Wealth.

  Nothing here reads data: a widget carries no figure of its own.
  """

  use Gettext, backend: PortfolixirWeb.Gettext

  @periods ~w(1d 1w 1m 3m ytd 1y 3y max)
  @default_period "1y"

  @sizes ~w(S W M T L full)
  @dimensions %{"S" => {3, 1}, "W" => {6, 1}, "M" => {6, 2}, "T" => {4, 3}, "L" => {8, 3}}

  @groups ~w(overview performance allocation risk analyses)

  # ADR-0061's windows: 1T to Tag, 1W to Woche, 1M to Monat, 3M to Quartal,
  # YTD to YTD, 1J, 3J and Max to 1J (ADR-0062 §5).
  @movers_period %{
    periods: @periods,
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

  # The performance family takes ytd, 1y, 3y and max as `period=`, and any
  # span as `from=`/`to=` (`PortfolixirWeb.Api.V1.PeriodParam`), so the four
  # short periods are the trailing range ending today: every period is its
  # own, none translated.
  @performance_period %{
    periods: @periods,
    param: "period",
    values: %{"ytd" => "ytd", "1y" => "1y", "3y" => "3y", "max" => "max"},
    ranges: ~w(1d 1w 1m 3m),
    translated: []
  }

  @kinds [
    %{
      key: "total_value",
      title: "Total value",
      group: "overview",
      sizes: ~w(S),
      source: %{
        routes: ["GET /api/v1/valuation", "GET /api/v1/views/:view_id/valuation"],
        function: {Portfolixir.Portfolios.Valuation, :for_view, 2},
        note: nil
      },
      period: :none,
      scope: :view,
      compact: true
    },
    %{
      key: "data_quality",
      title: "Data quality",
      group: "overview",
      sizes: ~w(S M),
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
      sizes: ~w(S),
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
      sizes: ~w(S M L full),
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
      sizes: ~w(S M),
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
      sizes: ~w(S W),
      source: %{
        routes: ["GET /api/v1/snapshots"],
        function: {Portfolixir.Portfolios.Snapshots, :list_snapshots, 1},
        note: nil
      },
      period: :none,
      scope: :none,
      compact: true
    },
    %{
      key: "allocation_drift",
      title: "Allocation and drift",
      group: "allocation",
      sizes: ~w(M T),
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
      sizes: ~w(M L),
      source: %{
        routes: ["GET /api/v1/crashes", "GET /api/v1/crashes/:key/rankings"],
        function: {Portfolixir.Crashes, :list_windows, 0},
        note: nil
      },
      period: :none,
      scope: :none,
      compact: true
    },
    %{
      key: "bitcoin_cycle",
      title: "Bitcoin cycle",
      group: "analyses",
      sizes: ~w(M L full),
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
      sizes: ~w(M),
      source: %{
        routes: ["GET /api/v1/sales/hindsight"],
        function: {Portfolixir.Portfolios.Performance.SaleHindsight, :report, 1},
        note: nil
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

  @doc "The sizes a kind may support: the five grid sizes and `full`."
  @spec sizes() :: [size()]
  def sizes, do: @sizes

  @doc """
  The width and height on the 12-column grid of a grid size, or `:error`
  for `full` (a page, not a grid size) and anything else.
  """
  @spec dimensions(term()) :: {:ok, {pos_integer(), pos_integer()}} | :error
  def dimensions(size) when is_binary(size), do: Map.fetch(@dimensions, size)
  def dimensions(_size), do: :error

  @doc "The catalogue's groups, in its order."
  @spec groups() :: [String.t()]
  def groups, do: @groups

  @doc "The periods above every dashboard, Wealth's keys (ADR-0062 §5)."
  @spec periods() :: [String.t()]
  def periods, do: @periods

  @doc "The dashboard's default period, Wealth's: one year."
  @spec default_period() :: String.t()
  def default_period, do: @default_period

  @doc "Whether the kind `key` answers the dashboard period `period`."
  @spec takes_period?(term(), term()) :: boolean()
  def takes_period?(key, period) when is_binary(period) do
    case fetch(key) do
      {:ok, %{period: %{periods: periods}}} -> period in periods
      _none -> false
    end
  end

  def takes_period?(_key, _period), do: false

  @doc """
  The query parameters of the kind's source route for the dashboard period
  `period` on `today`: `{:ok, %{"window" => "quarter"}}`, `{:ok,
  %{"period" => "ytd"}}`, or for a trailing range `{:ok, %{"from" =>
  "2026-10-21", "to" => "2026-11-21"}}`. `{:error, :no_period}` for a kind
  that takes none, `{:error, :unknown_period}` for a period it does not
  answer, `{:error, :unknown_kind}` for an unknown key.
  """
  @spec source_params(term(), term(), Date.t()) ::
          {:ok, %{String.t() => String.t()}}
          | {:error, :no_period | :unknown_period | :unknown_kind}
  def source_params(key, period, %Date{} = today) do
    case fetch(key) do
      :error -> {:error, :unknown_kind}
      {:ok, %{period: :none}} -> {:error, :no_period}
      {:ok, %{period: rule}} -> rule_params(rule, period, today)
    end
  end

  defp rule_params(%{param: param, values: values, ranges: ranges}, period, today)
       when is_binary(period) do
    cond do
      Map.has_key?(values, period) ->
        {:ok, %{param => Map.fetch!(values, period)}}

      period in ranges ->
        {:ok,
         %{"from" => Date.to_iso8601(range_start(period, today)), "to" => Date.to_iso8601(today)}}

      true ->
        {:error, :unknown_period}
    end
  end

  defp rule_params(_rule, _period, _today), do: {:error, :unknown_period}

  defp range_start("1d", today), do: Date.add(today, -1)
  defp range_start("1w", today), do: Date.add(today, -7)
  defp range_start("1m", today), do: Date.shift(today, month: -1)
  defp range_start("3m", today), do: Date.shift(today, month: -3)

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
