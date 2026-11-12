defmodule Portfolixir.Crashes.Rankings do
  @moduledoc """
  The lists of one crash window (ADR-0058 §5, §6; amendment of 2026-11-12,
  F2, F3), derived at read and never stored. `Portfolixir.Crashes.rankings/3`
  finds the window by its key and hands it here with the crash benchmark.

  ## The universe

    * `"catalogue"` (default): every security in the catalogue (a merged-away
      one has no row left) not flagged `is_benchmark`, minus the crash
      benchmark itself;
    * `"view:<id>"`: of those, the securities the view holds **today** — a
      position in a depot the view covers
      (`Portfolixir.Buckets.load_global_scope/1`) whose quantity summed over
      those depots is not zero, the rule the news digest reads a view's
      holdings by. "My holdings in that crash" is this filter, not a
      calculation of its own (the owner's answer of 2026-11-07).

  Flagged securities are reference instruments, not choices; the crash
  benchmark is the reference line beside each entry.

  ## The lists

  **Losers** and **winners** rank each security's EUR price return from the
  window's `start` to its `trough` by
  `Portfolixir.Portfolios.Performance.WindowReturn.price_return/3`, the one
  window-return function sale hindsight and the prediction resolution call:
  its close lookup (the last positive close on or before the date, at most
  7 days old), its split adjustment, its conversion at each close's own
  EUR-hub rate, one division. A crash return and a sale's hindsight return
  over the same dates therefore agree to the last digit. Losers come lowest
  first, winners highest first; the winners list keeps negative returns with
  their signs when few securities rose.

  Beside each entry: the crash benchmark's EUR return over the same dates
  (`benchmark_return`, the same call) and the difference in percentage
  points, `vs_benchmark_pp = (return − benchmark_return) × 100`, exact (a
  multiplication by 100 rounds nothing). With no crash benchmark (F2) both
  are `nil`, `reference` is `nil` and `reference_reason` says why; the
  ranking is unchanged.

  **Ties** within a list: by the figure, then the security's name
  case-folded, then its ISIN (a security without one after those with one),
  never by an id.

  **No answer** is never a zero: a security whose return cannot be measured
  is in no list and is counted under its reason (`no_close_at_start`,
  `no_close_at_end`, `no_fx_rate`), listed by `include_unanswered: true`.

  **Rebounders** rank each security's rise from its **own low** — its
  lowest close (display basis) on a day from `start` to `trough`, the
  earliest of equal lows — to the end of the **recovery span**, `trough`
  plus three calendar months (`Date.shift/2`, as sale hindsight's spans: a
  day the month lacks becomes its last day, so 30 November ends on 28
  February), in EUR by `WindowReturn.price_return/3` from the low's date to
  the span's end; highest first. A rebounder needs a close standing for
  `start` (its pre-crash close) and a close on a day from `start` to
  `trough` (its low), else `no_close_at_start`. Beside it: `days_back`, the
  **calendar days** (F3) from its own low to its first close at or above its
  close at `start`, 0 when the low is not below it, or `nil` with `not_yet:
  true` when that has not happened by its last close up to today. The
  reference is the crash benchmark's rise from its own low by the same rule.

  ## Provisional

  The lists of a window not yet recovered carry `provisional: true`, as its
  trough does (§2.5, §7.5): it moves while the benchmark falls. A rebound
  span that ends after today is measured to today, `provisional: true`, and
  `completes_on` names the day it ends (for a window still falling there is
  no such day yet: `nil`); a rebound is never ranked over a shorter span than
  the one it names without saying so.
  """

  import Ecto.Query

  alias Portfolixir.Buckets
  alias Portfolixir.Catalog.BenchmarkSecurity
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Clock
  alias Portfolixir.Crashes.PeakTrough
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.HeldSecurities
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Performance.WindowReturn
  alias Portfolixir.Repo

  @lists ~w(losers winners rebounders)
  @default_limit 8
  @max_limit 50
  @recovery_span_months 3
  @hundred Decimal.new(100)
  @reasons [:no_close_at_start, :no_close_at_end, :no_fx_rate]
  # The largest id a bigint column holds: a longer id names no view.
  @max_id 9_223_372_036_854_775_807

  @typedoc "The checked request: the list, the universe, the limit and the flags."
  @type request :: %{
          list: String.t(),
          universe: String.t(),
          limit: pos_integer(),
          include_unanswered: boolean(),
          today: Date.t()
        }

  @type refusal :: :invalid_list | :invalid_universe | :invalid_limit

  @doc "The lists `rank/4` answers, in the order the API names them."
  @spec lists() :: [String.t()]
  def lists, do: @lists

  @doc "The largest `limit` a request may name."
  @spec max_limit() :: pos_integer()
  def max_limit, do: @max_limit

  @doc """
  Checks a request before anything is read: `universe` is `"catalogue"` or
  `"view:<id>"`, the id spelled without a leading zero or sign;
  `opts` take `:list` (`"losers"`, the default, `"winners"` or
  `"rebounders"`), `:limit` (default
  #{@default_limit}, at most #{@max_limit}), `:include_unanswered` (default
  false) and `:today` (default `Portfolixir.Clock.today/0`).
  """
  @spec request(String.t(), keyword()) :: {:ok, request()} | {:error, refusal()}
  def request(universe, opts) when is_list(opts) do
    with {:ok, list} <- list(Keyword.get(opts, :list, "losers")),
         {:ok, universe} <- universe(universe),
         {:ok, limit} <- limit(Keyword.get(opts, :limit, @default_limit)) do
      {:ok,
       %{
         list: list,
         universe: universe,
         limit: limit,
         include_unanswered: Keyword.get(opts, :include_unanswered, false) == true,
         today: Keyword.get_lazy(opts, :today, &Clock.today/0)
       }}
    end
  end

  defp list(list) when list in @lists, do: {:ok, list}
  defp list(_list), do: {:error, :invalid_list}

  defp universe("catalogue"), do: {:ok, "catalogue"}

  defp universe("view:" <> id_text = universe) do
    case Integer.parse(id_text) do
      {id, ""} when id > 0 and id <= @max_id ->
        if universe == "view:#{id}", do: {:ok, universe}, else: {:error, :invalid_universe}

      _not_an_id ->
        {:error, :invalid_universe}
    end
  end

  defp universe(_universe), do: {:error, :invalid_universe}

  defp limit(limit) when is_integer(limit) and limit in 1..@max_limit, do: {:ok, limit}
  defp limit(_limit), do: {:error, :invalid_limit}

  @doc """
  The list `request` names for `window` (a detected or manual window as
  `Portfolixir.Crashes.list_windows/0` reads it), against `benchmark`, the
  crash benchmark (`nil` with `benchmark_reason` saying why).
  `{:error, :view_not_found}` for a view that does not exist.
  """
  @spec rank(map(), Security.t() | nil, String.t() | nil, request()) ::
          {:ok, map()} | {:error, :view_not_found}
  def rank(window, benchmark, benchmark_reason, request) do
    with {:ok, securities} <- universe_securities(request.universe, benchmark) do
      {:ok, ranked(window, securities, benchmark, benchmark_reason, request)}
    end
  end

  defp ranked(window, securities, benchmark, benchmark_reason, request) do
    held = MapSet.new(HeldSecurities.held_ids())
    span = span(request.list, window, request.today)

    {reference, reference_reason} = reference(benchmark, benchmark_reason, span)

    {answered, unanswered} =
      securities
      |> Enum.map(&measure(&1, span))
      |> Enum.split_with(&match?({:ok, _entry}, &1))

    entries =
      answered
      |> Enum.map(fn {:ok, entry} -> entry end)
      |> order(direction(request.list))
      |> Enum.take(request.limit)
      |> Enum.with_index(1)
      |> Enum.map(fn {entry, rank} -> entry(entry, rank, held, reference) end)

    unanswered = Enum.map(unanswered, fn {:error, security, reason} -> {security, reason} end)

    %{
      window: window_read(window),
      list: request.list,
      universe: request.universe,
      limit: request.limit,
      provisional: span.provisional,
      completes_on: span.completes_on,
      benchmark: benchmark_read(benchmark),
      reference: reference,
      reference_reason: reference_reason,
      entries: entries,
      answered: length(answered),
      unanswered: count(unanswered),
      basis: basis(window, benchmark, benchmark_reason, request)
    }
    |> Map.merge(span_dates(span))
    |> with_unanswered(unanswered, held, request.include_unanswered)
  end

  # What a list measures over. Losers and winners: the window's fall, from
  # start to trough. Rebounders: each own low within start..trough, to the
  # end of the recovery span (trough + 3 calendar months, the last day of
  # the month when the day does not exist), or to today while it has not
  # ended.
  defp span("rebounders", window, today) do
    span_end = Date.shift(window.trough, month: @recovery_span_months)
    open? = Date.compare(span_end, today) == :gt
    falling? = provisional?(window)

    %{
      kind: :rebound,
      low_from: window.start,
      low_to: window.trough,
      span_end: span_end,
      measured_to: if(open?, do: today, else: span_end),
      today: today,
      provisional: falling? or open?,
      completes_on: if(open? and not falling?, do: span_end, else: nil)
    }
  end

  defp span(_list, window, _today) do
    %{
      kind: :fall,
      from: window.start,
      to: window.trough,
      provisional: provisional?(window),
      completes_on: nil
    }
  end

  defp span_dates(%{kind: :fall} = span), do: Map.take(span, [:from, :to])

  defp span_dates(%{kind: :rebound} = span),
    do: Map.take(span, [:low_from, :low_to, :span_end, :measured_to])

  # -- the universe ------------------------------------------------------------

  defp universe_securities("catalogue", benchmark) do
    {:ok, from(s in Security, where: s.is_benchmark == false) |> without(benchmark) |> Repo.all()}
  end

  defp universe_securities("view:" <> id_text, benchmark) do
    case Buckets.load_global_scope(String.to_integer(id_text)) do
      {:error, :view_not_found} ->
        {:error, :view_not_found}

      scope ->
        ids = held_in(scope)

        {:ok,
         from(s in Security, where: s.is_benchmark == false and s.id in ^ids)
         |> without(benchmark)
         |> Repo.all()}
    end
  end

  # The securities held today in the depots `scope` covers: per position in
  # scope, summed per security, not zero (the news digest's rule for a
  # view's holdings, `Portfolixir.News.Reads.digest_securities/1`).
  defp held_in(scope) do
    Portfolios.list_portfolios()
    |> Enum.flat_map(fn portfolio ->
      portfolio.id
      |> Ledger.positions_for_portfolio()
      |> Enum.filter(fn {{account_id, security_id}, _quantity} ->
        Buckets.position_in_scope?(scope, account_id, security_id)
      end)
    end)
    |> Enum.reduce(%{}, fn {{_account_id, security_id}, quantity}, acc ->
      Map.update(acc, security_id, quantity, &Decimal.add(&1, quantity))
    end)
    |> Enum.reject(fn {_security_id, quantity} -> Decimal.eq?(quantity, 0) end)
    |> Enum.map(&elem(&1, 0))
  end

  defp without(query, nil), do: query
  defp without(query, %Security{id: id}), do: where(query, [s], s.id != ^id)

  # -- the figures -------------------------------------------------------------

  defp measure(security, %{kind: :fall, from: start_on, to: end_on}) do
    case WindowReturn.price_return(security, start_on, end_on) do
      {:ok, result} -> {:ok, figure(security, result)}
      {:error, reason} -> {:error, security, unanswered_reason(reason)}
    end
  end

  defp measure(security, %{kind: :rebound} = span) do
    with {:ok, start_close} <- pre_crash_close(security, span.low_from),
         closes = closes_since(security, span.low_from, span.today),
         {:ok, low} <- own_low(closes, span.low_to),
         {:ok, result} <- rise(security, low.date, span.measured_to) do
      back = Enum.find(closes, &back?(&1, low, start_close))

      {:ok,
       security
       |> figure(result)
       |> Map.merge(%{
         low: %{date: low.date, close: low.close},
         start_close: Map.take(start_close, [:stands_for, :date, :close]),
         back_on: back && back.date,
         days_back: back && Date.diff(back.date, low.date),
         not_yet: is_nil(back)
       })}
    else
      {:error, reason} -> {:error, security, reason}
    end
  end

  defp figure(security, result),
    do: %{security: security, return: result.return, start: result.start, end: result.end}

  # The close standing for the window's start, by WindowReturn's lookup.
  defp pre_crash_close(security, start_on) do
    case WindowReturn.close_on_or_before(security, start_on) do
      {:ok, close} -> {:ok, close}
      {:error, :no_close} -> {:error, :no_close_at_start}
    end
  end

  # The positive closes from the window's start to today, in the current
  # display basis, oldest first: the own low is read from them, and the
  # first close back at the pre-crash close.
  defp closes_since(%Security{id: id}, from, today) do
    id
    |> Quotes.adjusted_range(from, today)
    |> Enum.filter(&(Decimal.compare(&1.close, 0) == :gt))
  end

  # The lowest close on a day up to the trough; the earliest of equal lows.
  defp own_low(closes, low_to) do
    closes
    |> Enum.take_while(&(Date.compare(&1.date, low_to) != :gt))
    |> Enum.reduce(nil, fn
      close, nil -> close
      close, low -> if Decimal.compare(close.close, low.close) == :lt, do: close, else: low
    end)
    |> case do
      nil -> {:error, :no_close_at_start}
      low -> {:ok, low}
    end
  end

  defp rise(security, low_on, end_on) do
    case WindowReturn.price_return(security, low_on, end_on) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, unanswered_reason(reason)}
    end
  end

  # A close on or after the low's day at or above the pre-crash close.
  defp back?(close, low, start_close) do
    Date.compare(close.date, low.date) != :lt and
      Decimal.compare(close.close, start_close.close) != :lt
  end

  defp unanswered_reason(:no_start_close), do: :no_close_at_start
  defp unanswered_reason(:no_end_close), do: :no_close_at_end
  defp unanswered_reason(:no_fx_rate), do: :no_fx_rate

  # The crash benchmark's EUR figure by the same rule and call as each
  # entry's (over the same dates for a fall, from its own low for a
  # rebound); without one (F2), or without its close, no reference and the
  # reason.
  defp reference(nil, benchmark_reason, _span), do: {nil, benchmark_reason}

  defp reference(%Security{} = benchmark, _benchmark_reason, span) do
    case measure(benchmark, span) do
      {:ok, figure} ->
        {figure
         |> Map.take([:return, :start, :end, :low])
         |> Map.put(:security_id, benchmark.id), nil}

      {:error, _benchmark, :no_fx_rate} ->
        {nil, "no_fx_rate"}

      {:error, _benchmark, _no_close} ->
        {nil, "no_benchmark_close"}
    end
  end

  defp entry(entry, rank, held, reference) do
    benchmark_return = reference && reference.return

    entry
    |> Map.take([:return, :start, :end, :low, :start_close, :back_on, :days_back, :not_yet])
    |> Map.merge(%{
      rank: rank,
      security: security_read(entry.security),
      held: MapSet.member?(held, entry.security.id),
      benchmark_return: benchmark_return,
      vs_benchmark_pp: points(entry.return, benchmark_return)
    })
  end

  defp points(_return, nil), do: nil
  defp points(return, benchmark), do: return |> Decimal.sub(benchmark) |> Decimal.mult(@hundred)

  # -- order -------------------------------------------------------------------

  defp direction("losers"), do: :asc
  defp direction("winners"), do: :desc
  defp direction("rebounders"), do: :desc

  # Ties by the figure, then the case-folded name, then the ISIN (none
  # after any), never by an id.
  defp order(entries, direction), do: Enum.sort(entries, &before?(&1, &2, direction))

  defp before?(a, b, direction) do
    case {Decimal.compare(a.return, b.return), direction} do
      {:eq, _direction} -> tie_key(a.security) <= tie_key(b.security)
      {:lt, :asc} -> true
      {:gt, :desc} -> true
      _other -> false
    end
  end

  defp tie_key(%Security{name: name, isin: isin}),
    do: {String.downcase(name || ""), is_nil(isin), isin || ""}

  # -- the unanswered ----------------------------------------------------------

  defp count(unanswered) do
    counts = Map.new(@reasons, &{&1, 0})

    Enum.reduce(unanswered, counts, fn {_security, reason}, acc ->
      Map.update!(acc, reason, &(&1 + 1))
    end)
  end

  defp with_unanswered(payload, _unanswered, _held, false), do: payload

  defp with_unanswered(payload, unanswered, held, true) do
    listed =
      unanswered
      |> Enum.sort_by(fn {security, _reason} -> tie_key(security) end)
      |> Enum.map(fn {security, reason} ->
        %{
          security: security_read(security),
          held: MapSet.member?(held, security.id),
          reason: Atom.to_string(reason)
        }
      end)

    Map.put(payload, :unanswered_entries, listed)
  end

  # -- the reads ---------------------------------------------------------------

  defp security_read(%Security{} = security),
    do: Map.take(security, [:id, :name, :isin, :currency_code])

  defp benchmark_read(nil), do: nil

  defp benchmark_read(%Security{} = benchmark) do
    benchmark
    |> security_read()
    |> Map.put(:standing, benchmark |> BenchmarkSecurity.standing() |> Atom.to_string())
  end

  # A manual window's dates are fixed; a detected one is provisional until
  # it recovers.
  defp provisional?(window), do: Map.get(window, :provisional, false)

  defp window_read(window) do
    %{
      key: window.key,
      kind: window.kind,
      name: window.name,
      start: window.start,
      trough: window.trough,
      provisional: provisional?(window),
      recovered_on: Map.get(window, :recovered_on),
      max_gap_days: Map.get(window, :max_gap_days)
    }
  end

  # -- the computation basis (ADR-0058 §6) -------------------------------------

  defp basis(window, benchmark, benchmark_reason, request) do
    staleness = WindowReturn.staleness_days()

    %{
      benchmark: benchmark_read(benchmark),
      reason: if(benchmark, do: nil, else: benchmark_reason),
      reference: reference_text(benchmark),
      window: Map.take(window_read(window), [:key, :kind, :start, :trough, :provisional]),
      rule: if(window.kind == "detected", do: PeakTrough.rule(), else: nil),
      threshold: if(window.kind == "detected", do: PeakTrough.threshold(), else: nil),
      dates: dates_text(window.kind),
      universe: universe_text(request.universe),
      list: request.list,
      figure: figure_text(request.list),
      input_series:
        "each security's stored closes in the current display basis (ADR-0028 §2), " <>
          "positive closes only, each converted to EUR at the most recent stored EUR-hub " <>
          "rate on or before the close's own date",
      currency: "EUR",
      detection_currency: benchmark && benchmark.currency_code,
      currency_note:
        "the rule detects a window in the crash benchmark's own currency; every list, the " <>
          "benchmark's return beside it included, is in EUR",
      close_lookup:
        "the close standing for a date is the last positive stored close on or before it, " <>
          "at most #{staleness} calendar days older",
      staleness_days: staleness,
      split_adjustment:
        "both closes in the current display basis: a booked split divides the raw closes " <>
          "before its effective date, so a split inside the window is not a move",
      fx:
        "each close converts at the stored EUR-hub rate of its own date, carried forward " <>
          "without a bound, never a later one; the return is one division of exact products",
      recovery_span_months: @recovery_span_months,
      recovery_span:
        "rebounders are measured to the trough plus #{@recovery_span_months} calendar months, " <>
          "one span for every window; a day the month lacks becomes its last day; while the " <>
          "span has not ended the list is measured to today, provisional, and names the day " <>
          "it completes",
      days_back_unit: "calendar_days",
      days_back:
        "calendar days from a security's own low to its first close at or above its close " <>
          "standing for the window's start, compared in the display basis in its own " <>
          "currency; 0 when the low is not below that close; null with not_yet when no close " <>
          "up to today reaches it",
      gaps:
        "a day without a close is skipped, never interpolated; a security with no close " <>
          "standing for the start is no_close_at_start, none standing for the end " <>
          "no_close_at_end (none within #{staleness} days, or a security younger than the " <>
          "window), a close without a stored rate path to EUR no_fx_rate; each is counted " <>
          "under its reason and never ranked as a zero",
      ties:
        "equal figures are ordered by the security's name, case-folded, then by its ISIN " <>
          "(a security without one after those with one), never by an id",
      provisional:
        "a window not yet recovered is provisional, its trough the lowest close so far; its " <>
          "lists move with it and carry the flag",
      survivorship:
        "the catalogue holds what is still tracked: a security that failed and was removed " <>
          "is in no list, so the lists read better than the market did, and a rebound most " <>
          "of all"
    }
  end

  defp reference_text(nil),
    do:
      "none: no crash benchmark is chosen, so no entry carries a benchmark return or a difference"

  defp reference_text(%Security{}),
    do:
      "the crash benchmark measured by the same rule and function as each entry: over the " <>
        "same dates for losers and winners, from its own low for rebounders; " <>
        "vs_benchmark_pp is (return - benchmark_return) x 100, in percentage points, unrounded"

  defp dates_text("detected"),
    do:
      "the rule's: start is the last day at the peak, trough the earliest lowest close " <>
        "before the recovery; a name never moves them"

  defp dates_text("manual"),
    do:
      "chosen by a person (kind manual), who may have chosen them knowing the outcome; " <>
        "no rule fixed them"

  defp universe_text("catalogue"),
    do:
      "catalogue: every security the catalogue holds, not merged away, minus those flagged " <>
        "is_benchmark (reference instruments) and the crash benchmark itself"

  defp universe_text("view:" <> _id),
    do:
      "the securities the view holds today: a position in a depot the view covers whose " <>
        "quantity summed over them is not zero, minus those flagged is_benchmark and the " <>
        "crash benchmark itself; held today, not at the window's dates"

  defp figure_text(list) when list in ["losers", "winners"] do
    order = if list == "losers", do: "lowest first", else: "highest first"

    "each security's EUR price return from the window's start to its trough by " <>
      "WindowReturn.price_return/3, the function sale hindsight and the prediction " <>
      "resolution share; #{order}; a price return: distributions are not counted"
  end

  defp figure_text("rebounders") do
    "each security's rise from its own low, its lowest close in the display basis on a day " <>
      "from the window's start to its trough (the earliest of equal lows), to its close at " <>
      "the end of the recovery span (the trough plus #{@recovery_span_months} calendar " <>
      "months, the last day of the month when the day does not exist), in EUR by " <>
      "WindowReturn.price_return/3 from the low's date; highest first; a rebounder needs a " <>
      "close standing for the start and one on a day from start to trough, else " <>
      "no_close_at_start; a price return: distributions are not counted"
  end
end
