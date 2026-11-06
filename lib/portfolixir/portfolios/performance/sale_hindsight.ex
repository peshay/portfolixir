defmodule Portfolixir.Portfolios.Performance.SaleHindsight do
  @moduledoc """
  What a sale missed (I18 modes 1 and 2; the Sprint 25 plan's D-3): for each
  sale booking, how the sold security moved after the sale, over fixed
  spans, optionally beside a benchmark over the same span. Ladder (c): it
  measures a decision recorded before its outcome was known against prices
  stored after it, and replays no rule. Nothing is stored; every read derives
  the figures from the closes and rates the catalogue holds at that moment.

  ## The rows

  **One row per sale booking** (a ledger transaction of type `sell` with a
  security), not per FIFO lot: the decision was the sale. A sell with no buy
  before it (an orphan sell) is a sale too. An `outbound_delivery` is not: it
  moves shares out of a depot without a price, so it records no decision to
  sell at a price. Rows come newest first (sale date, then id, descending),
  narrowed by `:portfolio_id`, `:security_id` and the sale date (`:from`,
  `:to`, both inclusive), and capped at `:limit`.

  ## The spans

  Every span starts on the sale day and is measured by
  `Portfolixir.Portfolios.Performance.WindowReturn.price_return/3` from the
  sale day to the span's end, the one function the prediction resolution
  also calls, so the two cannot drift:

    * `1m`, `3m`, `12m` end on the sale day shifted by 1, 3 and 12 calendar
      months (`Date.shift/2`: a day the month lacks becomes its last day);
    * `latest` ends on the date of the security's latest stored close, and
      on today when that close is dated after today.

  A span whose end is after today is `:pending`. A span that cannot be
  measured is `:incomplete` with S1's reason (`:no_start_close`,
  `:no_end_close`, `:no_fx_rate`) or, on the benchmark side,
  `:no_benchmark_close`, in which case the security's own figure stays. A
  `latest` span whose latest close is not after the sale day is
  `:incomplete`, `:no_end_close`.

  ## The benchmark

  Optional, ADR-0046's two kinds as the API's `benchmark=` parser resolves
  them: `{:rate, rate}` compounds daily over the span's calendar
  days (`WindowReturn.fixed_rate_return/3` from the sale day to the date the
  end close stands for); `{:security, security}` is measured by
  `price_return/3` over the same two dates. `difference` is the security's
  return minus the benchmark's, unrounded. No field gives a verdict.
  """

  import Ecto.Query

  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Clock
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios.Performance.SaleReinvestment
  alias Portfolixir.Portfolios.Performance.WindowReturn
  alias Portfolixir.Repo

  @default_limit 100
  @spans [{"1m", 1}, {"3m", 3}, {"12m", 12}]

  @type benchmark :: nil | {:rate, Decimal.t()} | {:security, Security.t()}
  @type status :: :complete | :pending | :incomplete
  @type reason :: WindowReturn.reason() | :no_benchmark_close

  @typedoc "One side of a span: the return and the two closes it is measured from."
  @type side :: %{
          return: Decimal.t(),
          start: WindowReturn.window_end() | nil,
          end: WindowReturn.window_end() | nil
        }

  @type span :: %{
          span: String.t(),
          end_on: Date.t() | nil,
          days: non_neg_integer() | nil,
          status: status(),
          reason: reason() | nil,
          security: side() | nil,
          benchmark: side() | nil,
          difference: Decimal.t() | nil
        }

  @typedoc """
  One sale booking: `sale_id` is its transaction id (named so because the
  no-verdict invariant reads `transaction_id` as containing "action"), the
  booked `quantity`, `price` and `currency_code`, the start close in EUR or
  its reason, and the spans in `span_labels/0` order.
  """
  @type row :: %{
          sale_id: integer(),
          portfolio_id: integer(),
          securities_account_id: integer() | nil,
          date: Date.t(),
          quantity: Decimal.t(),
          price: Decimal.t() | nil,
          currency_code: String.t(),
          security: Security.t(),
          start: WindowReturn.window_end() | nil,
          start_reason: WindowReturn.reason() | nil,
          spans: [span()]
        }

  @doc "The span labels in the order every row carries them."
  @spec span_labels() :: [String.t()]
  def span_labels, do: Enum.map(@spans, &elem(&1, 0)) ++ ["latest"]

  @doc """
  The sale rows and the basis they are computed on.

  Options: `:benchmark` (`t:benchmark/0`, default none), `:portfolio_id`,
  `:security_id`, `:from`, `:to` (the sale date, inclusive), `:limit`
  (default #{@default_limit}), `:today` (default `Portfolixir.Clock.today/0`)
  and `:include`, a list that may name `:reinvestment` (I18 mode 3,
  ADR-0057 §4): each row then carries `reinvestment`, its block from
  `Portfolixir.Portfolios.Performance.SaleReinvestment.blocks/2`, and the
  basis carries `reinvestment`, that read's own.

  Answers `%{rows, limit, truncated, benchmark, include, today,
  computation_basis}`; `truncated` is true when more sales matched than
  `limit`.
  """
  @spec report(keyword()) :: %{
          rows: [row()],
          limit: pos_integer(),
          truncated: boolean(),
          benchmark: benchmark(),
          include: [:reinvestment],
          today: Date.t(),
          computation_basis: map()
        }
  def report(opts \\ []) do
    benchmark = Keyword.get(opts, :benchmark)
    today = Keyword.get_lazy(opts, :today, &Clock.today/0)
    limit = Keyword.get(opts, :limit, @default_limit)
    include = Keyword.get(opts, :include, [])

    {sales, rest} = opts |> sales(limit + 1) |> Enum.split(limit)
    rows = Enum.map(sales, &row(&1, benchmark, today))

    %{
      rows: rows |> with_reinvestment(sales, include, today),
      limit: limit,
      truncated: rest != [],
      benchmark: benchmark,
      include: include,
      today: today,
      computation_basis: benchmark |> computation_basis() |> with_reinvestment_basis(include)
    }
  end

  # I18 mode 3 (ADR-0057 §4): what each switch cost, on request, beside the
  # spans; the two questions are independent of each other.
  defp with_reinvestment(rows, sales, include, today) do
    if :reinvestment in include do
      blocks = SaleReinvestment.blocks(sales, today)
      Enum.map(rows, &Map.put(&1, :reinvestment, Map.fetch!(blocks, &1.sale_id)))
    else
      rows
    end
  end

  defp with_reinvestment_basis(basis, include) do
    if :reinvestment in include,
      do: Map.put(basis, :reinvestment, SaleReinvestment.computation_basis()),
      else: basis
  end

  defp sales(opts, fetch) do
    from(t in Transaction,
      where: t.type == "sell" and not is_nil(t.security_id),
      order_by: [desc: t.date, desc: t.id],
      limit: ^fetch,
      preload: [:security]
    )
    |> narrow(:portfolio_id, opts[:portfolio_id])
    |> narrow(:security_id, opts[:security_id])
    |> narrow(:from, opts[:from])
    |> narrow(:to, opts[:to])
    |> Repo.all()
  end

  defp narrow(query, _key, nil), do: query
  defp narrow(query, :portfolio_id, id), do: where(query, [t], t.portfolio_id == ^id)
  defp narrow(query, :security_id, id), do: where(query, [t], t.security_id == ^id)
  defp narrow(query, :from, %Date{} = from), do: where(query, [t], t.date >= ^from)
  defp narrow(query, :to, %Date{} = to), do: where(query, [t], t.date <= ^to)

  defp row(%Transaction{security: %Security{} = security} = sale, benchmark, today) do
    # The start close, in EUR, through the same function as every span: a
    # window of one day, whose start is the close standing for the sale day.
    {start, start_reason} =
      case WindowReturn.price_return(security, sale.date, sale.date) do
        {:ok, result} -> {result.start, nil}
        {:error, reason} -> {nil, reason}
      end

    spans =
      Enum.map(span_ends(sale, today), fn
        {label, nil} -> incomplete(label, nil, sale, :no_end_close, nil)
        {label, end_on} -> span(label, end_on, sale, security, benchmark, today)
      end)

    %{
      sale_id: sale.id,
      portfolio_id: sale.portfolio_id,
      securities_account_id: sale.securities_account_id,
      date: sale.date,
      quantity: sale.quantity,
      price: sale.price,
      currency_code: sale.currency_code,
      security: security,
      start: start,
      start_reason: start_reason,
      spans: spans
    }
  end

  @doc """
  The end date of each span of a sale (its security preloaded), in
  `span_labels/0` order: `1m`, `3m` and `12m` shifted by calendar months,
  `latest` the date of the security's latest stored close capped at
  `today`, or nil when that date is not after the sale day (the span is
  then incomplete, `:no_end_close`). What a switch cost
  (`Portfolixir.Portfolios.Performance.SaleReinvestment`, ADR-0057 §2)
  measures over the same ends.
  """
  @spec span_ends(Transaction.t(), Date.t()) :: [{String.t(), Date.t() | nil}]
  def span_ends(%Transaction{security: %Security{} = security} = sale, %Date{} = today) do
    Enum.map(@spans, fn {label, months} -> {label, Date.shift(sale.date, month: months)} end) ++
      [{"latest", latest_end(sale, security, today)}]
  end

  defp latest_end(sale, security, today) do
    case Quotes.latest(security.id) do
      %{date: %Date{} = date} ->
        end_on = Enum.min([date, today], Date)
        if Date.compare(end_on, sale.date) == :gt, do: end_on, else: nil

      nil ->
        nil
    end
  end

  defp span(label, end_on, sale, security, benchmark, today) do
    if Date.compare(end_on, today) == :gt do
      base(label, end_on, sale, :pending)
    else
      measure(label, end_on, sale, security, benchmark)
    end
  end

  defp measure(label, end_on, sale, security, benchmark) do
    case WindowReturn.price_return(security, sale.date, end_on) do
      {:ok, own} ->
        own_side = side(own)

        case benchmark_side(benchmark, own, sale.date, end_on) do
          {:ok, nil} ->
            %{base(label, end_on, sale, :complete) | security: own_side}

          {:ok, bench_side} ->
            %{
              base(label, end_on, sale, :complete)
              | security: own_side,
                benchmark: bench_side,
                difference: Decimal.sub(own.return, bench_side.return)
            }

          {:error, reason} ->
            incomplete(label, end_on, sale, reason, own_side)
        end

      {:error, reason} ->
        incomplete(label, end_on, sale, reason, nil)
    end
  end

  defp benchmark_side(nil, _own, _start_on, _end_on), do: {:ok, nil}

  defp benchmark_side({:rate, rate}, own, _start_on, _end_on) do
    return = WindowReturn.fixed_rate_return(rate, own.start.stands_for, own.end.stands_for)
    {:ok, %{return: return, start: nil, end: nil}}
  end

  defp benchmark_side({:security, %Security{} = bench}, _own, start_on, end_on) do
    case WindowReturn.price_return(bench, start_on, end_on) do
      {:ok, result} ->
        {:ok, side(result)}

      {:error, reason} when reason in [:no_start_close, :no_end_close] ->
        {:error, :no_benchmark_close}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp side(result), do: %{return: result.return, start: result.start, end: result.end}

  defp incomplete(label, end_on, sale, reason, own_side) do
    %{base(label, end_on, sale, :incomplete) | reason: reason, security: own_side}
  end

  defp base(label, end_on, sale, status) do
    %{
      span: label,
      end_on: end_on,
      days: end_on && Date.diff(end_on, sale.date),
      status: status,
      reason: nil,
      security: nil,
      benchmark: nil,
      difference: nil
    }
  end

  # AGENTS.md: every metric of ladder levels (a)-(c) states its computation
  # basis in its payload: input series, window, reference and gaps, plus what
  # the figure leaves out.
  defp computation_basis(benchmark) do
    staleness = WindowReturn.staleness_days()

    %{
      input_series:
        "each sale booking's sold security: its stored closes in the current display basis " <>
          "(ADR-0028, split-adjusted), each converted to EUR at the most recent stored EUR-hub " <>
          "rate on or before the close's own date, as valuation converts; " <>
          benchmark_series(benchmark),
      window:
        "every span starts on the sale day; 1m, 3m and 12m end on the sale day shifted by 1, " <>
          "3 and 12 calendar months (a day the month lacks becomes its last day), latest on " <>
          "the date of the security's latest stored close (today when that close is dated " <>
          "after today); a span whose end is after today is pending, with no figure. " <>
          "return = end close in EUR / start close in EUR - 1, unrounded; days counts the " <>
          "calendar days from the sale day to end_on",
      reference: reference(benchmark),
      gaps:
        "the close standing for a date is the last positive stored close on or before it, at " <>
          "most #{staleness} calendar days older; the start is the close standing for the " <>
          "sale day and the end the close standing for end_on, for the security and a " <>
          "benchmark security alike. A span without one is incomplete with its reason, never " <>
          "estimated: no_start_close, no_end_close (also a latest span with no close after " <>
          "the sale), no_fx_rate (a close with no stored rate path to EUR, either side), " <>
          "no_benchmark_close (the benchmark security has no close for either end; the " <>
          "security's own figure is kept)",
      price_only:
        "a price return on both sides: distributions after the sale are not booked, so a " <>
          "dividend payer's miss is understated by the dividends it paid after the sale",
      sales:
        "one row per sale booking (type sell with a security), not per FIFO lot; a sell " <>
          "with no buy before it counts. An outbound delivery is not a sale: it moves shares " <>
          "without a price. Newest sale first",
      booked_price:
        "price is the sale as booked, in currency_code, before fees and taxes and not " <>
          "split-adjusted; it is shown beside the start close and enters no figure, so both " <>
          "sides are measured from a close"
    }
  end

  defp benchmark_series(nil), do: "no benchmark"

  defp benchmark_series({:rate, rate}),
    do:
      "a fixed annual rate of #{Decimal.to_string(rate, :normal)} compounding daily, by a " <>
        "daily factor derived once as a float, (1 + rate)^(1/365), and compounded in decimal " <>
        "arithmetic over the span's days"

  defp benchmark_series({:security, %Security{} = security}),
    do:
      "the stored closes of #{security_reference(security)} by the same rule, from the " <>
        "close standing for the sale day to the close standing for end_on"

  defp reference(nil),
    do: "none: each span answers the security's own return; benchmark and difference are null"

  defp reference({:rate, rate}),
    do:
      "fixed rate #{Decimal.to_string(rate, :normal)} p.a.; difference = security return - " <>
        "benchmark return"

  defp reference({:security, %Security{} = security}),
    do: "#{security_reference(security)}; difference = security return - benchmark return"

  # E25 S7, F75: a basis names a benchmark security by its id and currency
  # only; its stored name is free text and travels as data.
  defp security_reference(%Security{id: id, currency_code: currency}),
    do: "security #{id} (#{currency})"
end
