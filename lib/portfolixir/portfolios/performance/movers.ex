defmodule Portfolixir.Portfolios.Performance.Movers do
  @moduledoc """
  Tops and flops per calendar window (FR-59, idea I32, ADR-0061; scope
  ladder levels (a) and (b)): for a view, or everything, two rankings over
  one window, side by side, derived at every read and never stored (§8).

    * `price_return` — each security the scope holds at the window's end by
      its EUR price return over the window, by
      `Portfolixir.Portfolios.Performance.WindowReturn.price_return/3`, the
      one window-return function sale hindsight, the crash rankings and the
      prediction resolution call. A security's week here and its return over
      the same dates there agree to the last digit.
    * `contribution` — every position ADR-0051's contribution read lists for
      the window, a position sold inside it included (`held_at_end: false`),
      by its money contribution in EUR
      (`Portfolixir.Portfolios.Performance.Contribution.for_view/2`, the read
      Wealth's contribution table makes for a custom range).

  ## The windows (§3)

  Every window ends on the as-of day `T` (`:today`, default
  `Portfolixir.Clock.today/0`). Its start day `S` is the day whose close
  stands for the window's start (`start_on/2`):

    * `week` — the day before this ISO week's Monday;
    * `month` — the last day of the previous month;
    * `quarter` — the last day of the previous calendar quarter;
    * `ytd` — 31 December of the previous year;
    * `1y` — `T` one year back (29 February maps to 28 February);
    * `day` — no single start day, see below.

  The price side measures `WindowReturn.price_return(security, S, T)`; the
  money side reads ADR-0051's window from `S + 1` to `T`, whose baseline is
  the close of `S`, so both start from the same day.

  `day` is per security on the price side: the security's latest close `E`
  (the close standing for `T`, at most 7 days old) against the stored
  positive close before it, `P`, whatever its age, by
  `WindowReturn.price_return(security, P, E)`; the row carries both dates.
  On the money side `day` is the window `[D, D]`, `D` the latest day on or
  before `T`, and at most 7 days before it, as `E` is, on which a positive
  close of any security the scope holds at `T` is stored (no such close:
  no window, an empty ranking; ADR-0061's amendment of 2026-11-19).

  ## The rankings (§4)

  Each ranking is cut into `highest` (the largest figures, descending) and
  `lowest` (the smallest, ascending) from one sorted list, so a name is
  never in both: with `n` answered entries and the limit `k`, `highest`
  takes `min(k, ceil(n / 2))` and `lowest` `min(k, floor(n / 2))` of the
  rest. Equal figures are ordered by ADR-0058 G1's full order: the name
  case-folded, the ISIN, the ticker, the WKN and the currency (a missing one
  after those with one), then the security's creation time; an id decides
  nothing but two rows created in the same instant.

  **No answer is never a zero.** A security without a price return is
  counted under its reason, `no_close_at_start`, `no_close_at_end`,
  `no_fx_rate`, and for `day` also `one_close_only`; a position the walk
  valued on no day of the window (`valued_days` 0 with unvalued days) is
  counted `no_valuation`, and one whose contribution is exactly 0 is counted
  `zero_contribution` and stands in neither half (board 04 ②: an unpriced
  fund, valued at its trade price every day, would otherwise fill the
  lowest; ADR-0061's amendment of 2026-11-19). An exact zero price return
  stays ranked. `include_unanswered: true` lists them in the tie order. A
  position with some unvalued days stays ranked under ADR-0051 §10's rule,
  its `unvalued_days` in its row.

  ## The basis (§5) and no verdict (§7)

  Each ranking carries its `computation_basis`: the input series, the window
  with its dates, the scope, the universe, the figure, the close lookup, the
  currency, the tie order, the split into halves and the treatment of gaps;
  `reference` is `nil`. The contribution basis states ADR-0051's terms
  itself rather than nesting the table's basis, which describes the table
  (its totals, remainder lines and order), not a ranking. The keys say
  `highest` and `lowest` and nothing that rates.
  """

  import Ecto.Query

  alias Portfolixir.Catalog.Quote, as: SecurityQuote
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Clock
  alias Portfolixir.Ledger.HeldSecurities
  alias Portfolixir.Portfolios.Performance.Contribution
  alias Portfolixir.Portfolios.Performance.WindowReturn
  alias Portfolixir.Repo

  @windows ~w(day week month quarter ytd 1y)
  @default_limit 5
  @max_limit 50
  @price_reasons [:no_close_at_start, :no_close_at_end, :no_fx_rate]
  @day_reasons @price_reasons ++ [:one_close_only]
  @money_reasons [:no_valuation, :zero_contribution]

  @type window :: String.t()
  @type refusal :: :invalid_window | :invalid_limit | :view_not_found

  @doc "The windows a read answers, in the order the screen shows them."
  @spec windows() :: [window()]
  def windows, do: @windows

  @doc "The limit per half when none is named."
  @spec default_limit() :: pos_integer()
  def default_limit, do: @default_limit

  @doc "The largest limit per half a read may name."
  @spec max_limit() :: pos_integer()
  def max_limit, do: @max_limit

  @doc """
  The start day `S` of `window` ending on `today` (ADR-0061 §3): the day
  whose close stands for the window's start. `nil` for `day`, whose start is
  per security.
  """
  @spec start_on(window(), Date.t()) :: Date.t() | nil
  def start_on("day", %Date{}), do: nil
  def start_on("week", %Date{} = today), do: today |> Date.beginning_of_week() |> Date.add(-1)
  def start_on("month", %Date{} = today), do: today |> Date.beginning_of_month() |> Date.add(-1)

  def start_on("quarter", %Date{year: year, month: month}) do
    first_month = div(month - 1, 3) * 3 + 1
    year |> Date.new!(first_month, 1) |> Date.add(-1)
  end

  def start_on("ytd", %Date{year: year}), do: Date.new!(year - 1, 12, 31)
  def start_on("1y", %Date{} = today), do: Date.shift(today, year: -1)

  @doc """
  Both rankings of `window` for the view `view_id`, or for everything when
  it is `nil`.

  Options: `:limit` (per half, 1 to #{@max_limit}, default
  #{@default_limit}), `:include_unanswered` (default false) and `:today`
  (the as-of day `T`, default `Portfolixir.Clock.today/0`).

  `{:ok, result}` with `view_id`, `window`, `start_on` (`S`, `nil` for
  `day`), `end_on` (`T`), `limit`, and the two rankings `price_return` and
  `contribution` (see the module doc), or `{:error, :invalid_window |
  :invalid_limit | :view_not_found}`.
  """
  @spec read(integer() | nil, window(), keyword()) :: {:ok, map()} | {:error, refusal()}
  def read(view_id, window, opts \\ [])
      when (is_integer(view_id) or is_nil(view_id)) and is_list(opts) do
    today = Keyword.get_lazy(opts, :today, &Clock.today/0)
    include_unanswered = Keyword.get(opts, :include_unanswered, false) == true

    with {:ok, window} <- checked_window(window),
         {:ok, limit} <- checked_limit(Keyword.get(opts, :limit, @default_limit)),
         {:ok, held_ids} <- HeldSecurities.in_scope_on(view_id, today) do
      request = %{
        view_id: view_id,
        window: window,
        start_on: start_on(window, today),
        end_on: today,
        limit: limit,
        include_unanswered: include_unanswered
      }

      held = securities(held_ids)

      with {:ok, contribution} <- contribution_ranking(held, request) do
        {:ok,
         %{
           view_id: view_id,
           window: window,
           start_on: request.start_on,
           end_on: today,
           limit: limit,
           price_return: price_ranking(held, request),
           contribution: contribution
         }}
      end
    end
  end

  defp checked_window(window) when window in @windows, do: {:ok, window}
  defp checked_window(_window), do: {:error, :invalid_window}

  defp checked_limit(limit) when is_integer(limit) and limit in 1..@max_limit, do: {:ok, limit}
  defp checked_limit(_limit), do: {:error, :invalid_limit}

  defp securities([]), do: []
  defp securities(ids), do: Repo.all(from(s in Security, where: s.id in ^ids))

  # -- the price side ------------------------------------------------------------

  defp price_ranking(held, request) do
    {answered, unanswered} =
      held
      |> Enum.map(&measure(&1, request))
      |> Enum.split_with(&match?({:ok, _entry}, &1))

    answered = Enum.map(answered, fn {:ok, entry} -> entry end)
    unanswered = Enum.map(unanswered, fn {:error, security, reason} -> {security, reason} end)
    reasons = if request.window == "day", do: @day_reasons, else: @price_reasons

    answered
    |> halves(:return, request.limit)
    |> Map.merge(%{answered: length(answered), unanswered: count(unanswered, reasons)})
    |> with_unanswered(unanswered, request.include_unanswered)
    |> Map.put(:computation_basis, price_basis(request))
  end

  defp measure(security, %{window: "day", end_on: today}) do
    with {:ok, latest} <- latest_close(security, today),
         {:ok, previous_on} <- previous_close_on(security, latest.date),
         {:ok, result} <- price_return(security, previous_on, latest.date) do
      {:ok, price_entry(security, result)}
    else
      {:error, reason} -> {:error, security, reason}
    end
  end

  defp measure(security, %{start_on: start_on, end_on: today}) do
    case price_return(security, start_on, today) do
      {:ok, result} -> {:ok, price_entry(security, result)}
      {:error, reason} -> {:error, security, reason}
    end
  end

  defp price_return(security, start_on, end_on) do
    case WindowReturn.price_return(security, start_on, end_on) do
      {:ok, result} -> {:ok, result}
      {:error, :no_start_close} -> {:error, :no_close_at_start}
      {:error, :no_end_close} -> {:error, :no_close_at_end}
      {:error, :no_fx_rate} -> {:error, :no_fx_rate}
    end
  end

  # E: the close standing for T, by WindowReturn's own lookup.
  defp latest_close(security, today) do
    case WindowReturn.close_on_or_before(security, today) do
      {:ok, close} -> {:ok, close}
      {:error, :no_close} -> {:error, :no_close_at_end}
    end
  end

  # P: the last positive stored close dated before E, whatever its age.
  defp previous_close_on(%Security{id: id}, before) do
    from(q in SecurityQuote,
      where: q.security_id == ^id and q.date < ^before and q.close > 0,
      order_by: [desc: q.date],
      limit: 1,
      select: q.date
    )
    |> Repo.one()
    |> case do
      nil -> {:error, :one_close_only}
      date -> {:ok, date}
    end
  end

  defp price_entry(security, result),
    do: %{security: security, return: result.return, start: result.start, end: result.end}

  # -- the money side ------------------------------------------------------------

  @contribution_terms [
    :contribution,
    :start_value,
    :end_value,
    :net_flows,
    :income,
    :costs,
    :held_at_start,
    :held_at_end,
    :unvalued_days,
    :unvalued_reason,
    :valued_days
  ]

  defp contribution_ranking(held, request) do
    {from, to} = money_window(held, request)

    with {:ok, positions} <- positions(request.view_id, from, to, request.end_on) do
      {:ok, contribution_halves(positions, from, to, request)}
    end
  end

  defp contribution_halves(positions, from, to, request) do
    labels = labels(positions)

    {ranked, unanswered} =
      Enum.reduce(positions, {[], []}, fn row, {ranked, unanswered} ->
        case money_reason(row) do
          nil -> {[contribution_entry(row, labels) | ranked], unanswered}
          reason -> {ranked, [{Map.fetch!(labels, row.security_id), reason} | unanswered]}
        end
      end)

    ranked
    |> halves(:contribution, request.limit)
    |> Map.merge(%{
      from: from,
      to: to,
      answered: length(ranked),
      unanswered: count(unanswered, @money_reasons)
    })
    |> with_unanswered(unanswered, request.include_unanswered)
    |> Map.put(:computation_basis, contribution_basis(request, from, to))
  end

  # Why a position stands in neither half, or nil when it is ranked: valued
  # on no day of the window, or a contribution of exactly 0 (board 04 ②:
  # „ein Beitrag 0,00 steht in keiner Hälfte, sonst füllen ungepreiste
  # Fonds die Niedrigsten“; ADR-0061's amendment of 2026-11-19).
  defp money_reason(row) do
    cond do
      valued_on_no_day?(row) -> :no_valuation
      Decimal.eq?(row.contribution, 0) -> :zero_contribution
      true -> nil
    end
  end

  # week to 1y: S + 1 to T. day: [D, D], or no window without a close
  # standing for T.
  defp money_window(held, %{window: "day", end_on: today}) do
    case last_close_day(held, today) do
      nil -> {nil, nil}
      day -> {day, day}
    end
  end

  defp money_window(_held, %{start_on: start_on, end_on: today}),
    do: {Date.add(start_on, 1), today}

  defp last_close_day([], _today), do: nil

  # D is bounded as E is (ADR-0061's amendment of 2026-11-19): a close older
  # than the staleness bound stands for no day of T's, so it moves nothing
  # on the money side either.
  defp last_close_day(held, today) do
    ids = Enum.map(held, & &1.id)
    oldest = Date.add(today, -WindowReturn.staleness_days())

    Repo.one(
      from(q in SecurityQuote,
        where: q.security_id in ^ids and q.date <= ^today and q.date >= ^oldest and q.close > 0,
        select: max(q.date)
      )
    )
  end

  defp positions(_view_id, nil, nil, _today), do: {:ok, []}

  # The read Wealth's contribution table makes for a custom range, in EUR.
  # A view deleted between the holdings read and this one is not found.
  defp positions(view_id, from, to, today) do
    with {:ok, table} <- Contribution.for_view(view_id, period: {:range, from, to}, today: today) do
      {:ok, table.positions}
    end
  end

  defp valued_on_no_day?(row), do: row.unvalued_days > 0 and row.valued_days == 0

  # The catalogue's rows behind the table's positions, for the tie order.
  defp labels(positions) do
    stored = positions |> Enum.map(& &1.security_id) |> securities() |> Map.new(&{&1.id, &1})

    Map.new(positions, fn row ->
      {row.security_id,
       Map.get_lazy(stored, row.security_id, fn ->
         %Security{id: row.security_id, name: row.name, isin: row.isin, wkn: row.wkn}
       end)}
    end)
  end

  defp contribution_entry(row, labels),
    do:
      row
      |> Map.take(@contribution_terms)
      |> Map.put(:security, Map.fetch!(labels, row.security_id))

  # -- the halves and the order (§4) -----------------------------------------------

  defp halves(entries, figure, limit) do
    n = length(entries)

    {highest, rest} =
      entries
      |> Enum.sort(&before?(&1, &2, figure, :desc))
      |> Enum.split(min(limit, div(n + 1, 2)))

    lowest =
      rest
      |> Enum.sort(&before?(&1, &2, figure, :asc))
      |> Enum.take(min(limit, div(n, 2)))

    %{highest: Enum.map(highest, &rendered/1), lowest: Enum.map(lowest, &rendered/1)}
  end

  defp before?(a, b, figure, direction) do
    case {Decimal.compare(Map.fetch!(a, figure), Map.fetch!(b, figure)), direction} do
      {:eq, _direction} -> tie_before?(a.security, b.security)
      {:gt, :desc} -> true
      {:lt, :asc} -> true
      _other -> false
    end
  end

  # ADR-0058 G1's full order, as the crash rankings apply it: the name
  # case-folded, the ISIN, the ticker, the WKN and the currency (a missing
  # one after those with one), then the creation time; the id only keeps
  # two rows created in the same instant in one order.
  defp tie_before?(a, b) do
    case {tie_key(a), tie_key(b)} do
      {same, same} -> created_before?(a, b)
      {key_a, key_b} -> key_a < key_b
    end
  end

  defp tie_key(%Security{} = security) do
    {String.downcase(security.name || ""), missing_last(security.isin),
     missing_last(security.ticker_symbol), missing_last(security.wkn),
     security.currency_code || ""}
  end

  defp missing_last(nil), do: {true, ""}
  defp missing_last(value), do: {false, value}

  defp created_before?(
         %Security{inserted_at: %NaiveDateTime{} = a} = x,
         %Security{inserted_at: %NaiveDateTime{} = b} = y
       ) do
    case NaiveDateTime.compare(a, b) do
      :lt -> true
      :gt -> false
      :eq -> x.id <= y.id
    end
  end

  defp created_before?(a, b), do: a.id <= b.id

  defp rendered(entry), do: Map.update!(entry, :security, &security_read/1)

  defp security_read(%Security{} = security),
    do: Map.take(security, [:id, :name, :isin, :wkn, :ticker_symbol, :currency_code])

  # -- the unanswered ------------------------------------------------------------

  defp count(unanswered, reasons) do
    Enum.reduce(unanswered, Map.new(reasons, &{&1, 0}), fn {_security, reason}, acc ->
      Map.update!(acc, reason, &(&1 + 1))
    end)
  end

  defp with_unanswered(ranking, _unanswered, false), do: ranking

  defp with_unanswered(ranking, unanswered, true) do
    listed =
      unanswered
      |> Enum.sort(fn {a, _reason_a}, {b, _reason_b} -> tie_before?(a, b) end)
      |> Enum.map(fn {security, reason} ->
        %{security: security_read(security), reason: Atom.to_string(reason)}
      end)

    Map.put(ranking, :unanswered_entries, listed)
  end

  # -- the computation basis (§5) ----------------------------------------------------

  defp price_basis(request) do
    staleness = WindowReturn.staleness_days()

    %{
      input_series:
        "each security's stored closes in the current display basis (ADR-0028 §2), " <>
          "positive closes only, and the stored EUR-hub rates; distributions are not " <>
          "counted: a price return",
      window: %{
        key: request.window,
        start_on: request.start_on,
        end_on: request.end_on,
        rule: price_window_text(request.window)
      },
      scope: scope(request.view_id),
      universe:
        "the securities the scope holds at the window's end: a positive quantity summed " <>
          "over the scope's positions on the end date, a flagged benchmark included; a " <>
          "security sold inside the window is not ranked by price",
      figure:
        "each security's EUR price return by WindowReturn.price_return/3, the function " <>
          "sale hindsight, the crash rankings and the prediction resolution share: " <>
          "(end close x start hub rate) / (start close x end hub rate) - 1, one division " <>
          "at 34 significant digits",
      close_lookup:
        "the close standing for a date is the last positive stored close on or before " <>
          "it, at most #{staleness} calendar days older",
      staleness_days: staleness,
      split_adjustment:
        "both closes in the current display basis: a booked split divides the raw closes " <>
          "before its effective date, so a split inside the window is not a move",
      fx:
        "each close converts at the stored EUR-hub rate of its own date, carried forward " <>
          "without a bound, never a later one",
      currency: "EUR",
      ties: ties_text(),
      halves: halves_text(request.limit, ""),
      gaps:
        "a security without a figure is counted under its reason and never ranked as a " <>
          "zero: no_close_at_start (no close standing for the start), no_close_at_end (none " <>
          "standing for the end), no_fx_rate (a close without a stored rate path to EUR)" <>
          if(request.window == "day",
            do: ", one_close_only (no stored close before the latest)",
            else: ""
          ),
      reference: nil
    }
  end

  defp price_window_text("day") do
    "per security: its latest close E, the close standing for the end day, against the " <>
      "stored positive close before it, P, whatever its age; each row names P (start.date) " <>
      "and E (end.date), so a share and a coin can stand on different days"
  end

  defp price_window_text(_window) do
    "from the close standing for start_on to the close standing for end_on; each row " <>
      "names the dates its closes stand on"
  end

  defp contribution_basis(request, from, to) do
    %{
      input_series:
        "the daily valuation walk of ADR-0010 per position (ADR-0051 §5): recorded " <>
          "transactions, stored quotes and stored EUR-hub rates, valued in EUR",
      window: %{
        key: request.window,
        start_on: request.start_on,
        end_on: request.end_on,
        from: from,
        to: to,
        day_on: if(request.window == "day", do: from, else: nil),
        rule: contribution_window_text(request.window)
      },
      scope: scope(request.view_id),
      universe:
        "every position ADR-0051's contribution read lists for the window, a position " <>
          "sold inside it included (held_at_end false)",
      figure:
        "each position's contribution in EUR by ADR-0051 (Contribution.for_view/2, the read " <>
          "Wealth's table makes for a custom range): end_value - start_value - net_flows + " <>
          "income - costs (ADR-0051 §1). start_value is the close of the day before from " <>
          "(0 when not held then) and end_value the close of to (0 when sold out); " <>
          "net_flows counts a buy + price × quantity and a sell - price × quantity at the " <>
          "booking day's rate, a delivery ± the value the walk gives it, a split and a " <>
          "transfer inside the scope 0, and a leg crossing a view's edge as its boundary " <>
          "flow (ADR-0019); income is the dividends and interest bookings that name the " <>
          "security, as credited; costs are the fees and taxes on the position's own " <>
          "trades. The currency move is inside the figure, not split out (ADR-0051 §7); " <>
          "exact in Decimal while every conversion quotient terminates, else rounded at " <>
          "34 significant digits; each day's value converts at that day's stored EUR-hub rate, " <>
          "so a close older than end_on converts at end_on's rate where the price side " <>
          "converts it at its own date's",
      currency: "EUR",
      ties: ties_text(),
      halves:
        halves_text(
          request.limit,
          "; a contribution of exactly 0 is in neither half and counted zero_contribution"
        ),
      gaps:
        "a day on which a held position has no price or no rate path counts zero and the " <>
          "position stays ranked with its unvalued_days and unvalued_reason (ADR-0051 §10); " <>
          "prices and rates carry the most recent stored point on or before each day " <>
          "forward (a stored close of 0 or below is not a price), and a security with no " <>
          "quote yet is priced by its own latest trade " <>
          "(ADR-0010); " <>
          "a position valued on no day of the window (valued_days 0) is counted " <>
          "no_valuation and never ranked as a zero; a position whose contribution is " <>
          "exactly 0, such as a fund with no stored quote valued at its trade price every " <>
          "day, is counted zero_contribution and stands in neither half, so such positions " <>
          "do not fill lowest (board 04; ADR-0061's amendment of 2026-11-19)" <>
          if(request.window == "day" and is_nil(from),
            do:
              "; no security the scope holds has a positive close stored on or before " <>
                "end_on and within #{WindowReturn.staleness_days()} calendar days of it, so " <>
                "there is no day D",
            else: ""
          ),
      reference: nil
    }
  end

  defp contribution_window_text("day") do
    "the one day D (from = to = day_on): the latest day on or before end_on, and at most " <>
      "#{WindowReturn.staleness_days()} calendar days before it, as the price side's E, on " <>
      "which a positive close of any security the scope holds at end_on is stored; on a " <>
      "Monday before the shares' closes, D is the Sunday and only what closed then moved"
  end

  defp contribution_window_text(_window) do
    "from start_on + 1 to end_on: ADR-0051's baseline is the close of start_on, the day " <>
      "the price side starts from"
  end

  defp scope(nil),
    do: %{view_id: nil, rule: "everything: every depot and cash account of every portfolio"}

  defp scope(view_id) when is_integer(view_id),
    do: %{
      view_id: view_id,
      rule: "the view's depots and cash accounts across every portfolio, overrides included"
    }

  defp ties_text do
    "equal figures are ordered by the security's name, case-folded, then by its ISIN, its " <>
      "ticker, its WKN and its currency (a security without one after those with one), then " <>
      "by its creation time; an id decides no rank (ADR-0058 G1)"
  end

  defp halves_text(limit, excluded) do
    "one list sorted by the figure: highest takes min(#{limit}, ceil(n / 2)) of the " <>
      "largest, descending; lowest min(#{limit}, floor(n / 2)) of the rest, ascending; " <>
      "n is the answered entries, and a name is never in both" <> excluded
  end
end
