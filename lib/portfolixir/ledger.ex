defmodule Portfolixir.Ledger do
  @moduledoc """
  Transaction ledger.

  Tracks the full set of Portfolio-Performance transaction kinds (see
  `Portfolixir.Ledger.Transaction.kinds/0`): manual `buy`/`sell` trades
  plus the cash-, dividend-, fee-, tax- and transfer-flavoured events
  required to ingest external exports.

  Held quantities — `positions_for_portfolio/1` and the holdings views —
  move with trades, deliveries and security transfers (the projection's
  quantity legs, ADR-0011), and scale with `split` events (ADR-0028). The
  moving-average cost basis follows the shares through the same kinds
  (`cost_lots/1`): only priced acquisitions add cost, removals take it out
  at the running average, a transfer carries it into the counter depot, and
  a split scales quantity while leaving total cost invariant. The FIFO trade
  matcher still considers only the priced `buy`/`sell` kinds for matching;
  a split scales its open lots.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Catalog.QuoteAdjustment
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Fx
  alias Portfolixir.Journal
  alias Portfolixir.Ledger.PnlDecomposition
  alias Portfolixir.Ledger.Positions
  alias Portfolixir.Ledger.Projection
  alias Portfolixir.Ledger.TradeMatcher
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.Portfolio
  alias Portfolixir.Portfolios.SecuritiesAccount
  alias Portfolixir.Repo

  @zero Decimal.new("0")
  @one Decimal.new("1")
  @hub "EUR"

  def list_transactions(opts \\ []) when is_list(opts) do
    ordered_transactions()
    |> filter_transactions(opts)
    |> preload([:security, :cash_account, :securities_account])
    |> Repo.all()
  end

  defp filter_transactions(query, opts) do
    query
    |> filter_transaction_eq(:portfolio_id, opts[:portfolio_id])
    |> filter_transaction_eq(:security_id, opts[:security_id])
    |> filter_transaction_eq(:securities_account_id, opts[:securities_account_id])
    |> filter_transaction_from(opts[:from])
    |> filter_transaction_to(opts[:to])
    |> filter_transaction_limit(opts[:limit])
  end

  defp filter_transaction_limit(query, nil), do: query

  defp filter_transaction_limit(query, n) when is_integer(n) and n > 0,
    do: limit(query, ^n)

  defp filter_transaction_eq(query, _field, nil), do: query

  defp filter_transaction_eq(query, :portfolio_id, id),
    do: where(query, [t], t.portfolio_id == ^id)

  defp filter_transaction_eq(query, :security_id, id),
    do: where(query, [t], t.security_id == ^id)

  defp filter_transaction_eq(query, :securities_account_id, id),
    do: where(query, [t], t.securities_account_id == ^id)

  defp filter_transaction_from(query, nil), do: query
  defp filter_transaction_from(query, %Date{} = from), do: where(query, [t], t.date >= ^from)

  defp filter_transaction_to(query, nil), do: query
  defp filter_transaction_to(query, %Date{} = to), do: where(query, [t], t.date <= ^to)

  def list_transactions_for_portfolio(portfolio_id) when is_integer(portfolio_id) do
    Repo.all(
      from(transaction in ordered_transactions(),
        where: transaction.portfolio_id == ^portfolio_id,
        preload: [:security, :cash_account, :securities_account]
      )
    )
  end

  def list_transactions_for_security(security_id) when is_integer(security_id) do
    Repo.all(
      from(transaction in Transaction,
        where: transaction.security_id == ^security_id,
        order_by: [asc: transaction.date, asc: transaction.id],
        preload: [
          :portfolio,
          :securities_account,
          :cash_account,
          :counter_securities_account,
          :security
        ]
      )
    )
  end

  @doc """
  Returns the current cash balance of each cash account, keyed by
  `cash_account_id`, derived on read from the stored transactions (balances are
  not persisted; see ADR-0004).

  Amounts are stored as positive magnitudes and the transaction `type` implies
  the direction of the cash flow; the per-kind semantics live in
  `Portfolixir.Ledger.Projection` (ADR-0011). Each balance is in its own
  account's currency; no FX conversion is applied here. Pass `:portfolio_id` to
  scope the calculation to one portfolio. Accounts with no cash-affecting
  transaction are omitted and should be treated as a zero balance by callers.

  A `balance_adjustment` (see ADR-0009) is an absolute-balance snapshot, not a
  delta: it anchors the account to a stated balance as of its date, and only
  bookings dated strictly after it adjust the result. This lets an external
  account be kept current by stating its balance now and then, without mirroring
  every booking. An anchored account always appears in the result (even with no
  later bookings).
  """
  def cash_balances(opts \\ []) when is_list(opts) do
    Transaction
    |> scope_portfolio(opts[:portfolio_id])
    |> Repo.all()
    |> Projection.cash_balances()
  end

  defp scope_portfolio(query, nil), do: query

  defp scope_portfolio(query, portfolio_id) when is_integer(portfolio_id),
    do: where(query, [t], t.portfolio_id == ^portfolio_id)

  @doc """
  Lists FIFO-matched trades for a security: closed round-trips, open
  remaining lots (with unrealised P&L vs. the latest known quote close),
  and any orphan sells.

  Open lots carry their basis in the security's own currency
  (`buy_price_native`, derived from the ADR-0015 settlement legs for
  cross-currency bookings) and the ADR-0033 price/currency decomposition
  against the EUR hub; a lot whose native leg is not derivable is reported
  honestly unavailable (`decomposed: false`, `undecomposed_reason`), never
  compared blindly across currencies.

  Pass `:latest_price` (Decimal) to inject the comparison price for
  tests; otherwise the function reads it from `Catalog.Quotes.adjusted_latest/1`
  (the split-adjusted display basis, ADR-0028 §2). Pass `:fx_rates`
  (`%{currency => Decimal}`, EUR per 1 unit) to inject the current hub rate
  for tests; otherwise it resolves from the stored rates.
  """
  def list_trades_for_security(security_id, opts \\ []) when is_integer(security_id) do
    latest_price =
      Keyword.get_lazy(opts, :latest_price, fn -> adjusted_latest_close(security_id) end)

    fx_rates = Keyword.get(opts, :fx_rates, %{})
    security = Repo.get(Security, security_id)
    security_currency = security && security.currency_code

    transactions =
      security_id
      |> list_transactions_for_security()
      |> Enum.map(&transaction_for_matcher(&1, security_currency))

    result = TradeMatcher.match(transactions)

    %{
      result
      | open_lots:
          Enum.map(
            result.open_lots,
            &decorate_open_lot(&1, latest_price, security_currency, fx_rates)
          )
    }
  end

  @doc """
  Returns the current holdings of a whole portfolio, one row per
  (depot, security), enriched with a moving-average cost basis and the
  unrealised P&L against each security's latest known quote close.

  Quantities are the canonical position quantities (`Ledger.Positions`,
  ADR-0011): they move with trades, deliveries and security transfers, so a
  position that left the depot without a sell (e.g. a takeover booked as an
  outbound delivery) does not linger as a phantom holding. The cost basis
  follows the shares through the same kinds (see `cost_lots/1`): buys and
  priced inbound deliveries add cost, sells and outbound deliveries remove
  it at the running average, a security transfer carries it into the counter
  depot, and unpriced deliveries move quantity at zero cost. Fees and taxes
  are not folded into the basis. A holding whose security has no quote is
  returned with `nil` price, market value and P&L, so a missing price never
  distorts the rest of the list.

  Currency basis (ADR-0033): `cost_basis`, `avg_cost`, `latest_price`,
  `market_value` and the unrealized P&L are in the security's **own**
  currency — enforced by the cost pair the fold carries, no longer assumed.
  Each row additionally carries the base-currency decomposition: `base_cost`
  (the settlement-leg amount actually paid, with its `base_currency`),
  `price_return_abs/pct`, `currency_return_abs/pct` and
  `total_return_base_abs/pct`, which satisfy `total = price + currency`
  Decimal-exactly (`Portfolixir.Ledger.PnlDecomposition`). A row whose
  decomposition is not derivable (no native leg, settlement leg outside the
  portfolio base currency, or no current rate) is reported honestly
  unavailable via `decomposed: false` and `undecomposed_reason` — never a
  guessed number; when the native leg itself is missing,
  `cost_basis`/`avg_cost`/unrealized P&L are nil too.

  Pass `:prices` (`%{security_id => Decimal}`) to inject comparison prices for
  tests; missing securities fall back to `Catalog.Quotes.adjusted_latest/1`
  (the split-adjusted display basis, ADR-0028 §2). Pass `:fx_rates`
  (`%{currency => Decimal}`, base units per 1 security-currency unit) to
  inject the current hub rate for tests; otherwise rates resolve from the
  stored EUR-hub rates exactly like the valuation.
  """
  def holdings_for_portfolio(portfolio_id, opts \\ []) when is_integer(portfolio_id) do
    prices = Keyword.get(opts, :prices, %{})
    fx_rates = Keyword.get(opts, :fx_rates, %{})
    base_currency = portfolio_base_currency(portfolio_id)
    transactions = portfolio_transactions_with_security(portfolio_id)
    lots = cost_lots(transactions)
    securities = securities_by_id(transactions)

    transactions
    |> Positions.calculate()
    |> Enum.map(fn {{account_id, security_id} = key, quantity} ->
      build_holding_row(
        account_id,
        security_id,
        Map.get(securities, security_id),
        quantity,
        lot_for(lots, key),
        holding_price(security_id, prices),
        base_currency,
        fx_rates
      )
    end)
    |> Enum.sort_by(&{&1.security_id, &1.securities_account_id})
  end

  defp portfolio_base_currency(portfolio_id) do
    case Repo.get(Portfolio, portfolio_id) do
      %Portfolio{base_currency_code: code} -> code
      _missing -> nil
    end
  end

  # All transactions of one portfolio in chronological order, with the
  # security preloaded so each holding can carry its name and currency, and
  # the cash account so the fold can name the settlement-leg currency of an
  # ADR-0015 booking. Ordering ascending is required for the moving-average
  # fold to be correct.
  defp portfolio_transactions_with_security(portfolio_id) do
    Repo.all(
      from(transaction in Transaction,
        where: transaction.portfolio_id == ^portfolio_id,
        order_by: [asc: transaction.date, asc: transaction.id],
        preload: [:security, :cash_account]
      )
    )
  end

  defp securities_by_id(transactions) do
    for %{security: %Security{} = security} <- transactions,
        into: %{},
        do: {security.id, security}
  end

  defp build_holding_row(
         account_id,
         security_id,
         security,
         quantity,
         lot,
         latest_price,
         base_currency,
         fx_rates
       ) do
    security_currency = security && security.currency_code
    cost_basis = if lot.cost_known, do: lot.cost, else: nil

    base =
      %{
        securities_account_id: account_id,
        security_id: security_id,
        security_name: security && security.name,
        # Stable external identifiers so API/MCP consumers can reconcile against
        # broker data without joining the securities list (FR-30).
        isin: security && security.isin,
        wkn: security && security.wkn,
        currency_code: security_currency,
        quantity: quantity,
        avg_cost: cost_basis && average_unit_cost(quantity, cost_basis),
        cost_basis: cost_basis
      }
      |> Map.merge(base_cost_fields(lot, base_currency))

    base
    |> put_holding_valuation(latest_price)
    |> put_decomposition(:market_value, lot, security_currency, base_currency, fx_rates)
  end

  # The settlement-leg cost and the single currency it is denominated in. A
  # zero-cost lot constrains no currency, so it reports the row's base
  # currency; a mixed or unknown settlement leg reports nil (honesty over
  # availability, ADR-0033 requirement 4).
  defp base_cost_fields(%{base: %{known: false}}, _base_currency),
    do: %{base_cost: nil, base_currency: nil}

  defp base_cost_fields(%{base: base}, base_currency),
    do: %{base_cost: base.amount, base_currency: base.currency || base_currency}

  # The ADR-0033 decomposition of one holding row, over the lot's cost pair
  # and the current hub rate (the same rate source the valuation uses; rates
  # are looked up at decoration time only — the fold stays pure).
  defp put_decomposition(row, value_key, lot, security_currency, base_currency, fx_rates) do
    market_value = Map.get(row, value_key)

    decomposition =
      cond do
        not lot.cost_known ->
          PnlDecomposition.unavailable(:missing_native_cost)

        is_nil(market_value) ->
          PnlDecomposition.unavailable(:no_price)

        not base_leg_in_base_currency?(lot, base_currency) ->
          PnlDecomposition.unavailable(:missing_base_cost)

        true ->
          case base_rate(security_currency, base_currency, fx_rates) do
            {:ok, rate} ->
              PnlDecomposition.decompose(market_value, lot.cost, lot.base.amount, rate)

            {:error, :no_rate} ->
              PnlDecomposition.unavailable(:missing_fx)
          end
      end

    Map.merge(row, decomposition)
  end

  defp base_leg_in_base_currency?(%{base: base}, base_currency) do
    base.known and not is_nil(base_currency) and
      (base.currency == nil or base.currency == base_currency)
  end

  # The current rate converting one security-currency unit into the base
  # currency: identity for same-currency rows (exactly 1, no lookup), an
  # injected test override, or the stored EUR-hub triangulation (ADR-0007).
  defp base_rate(nil, _base_currency, _fx_rates), do: {:error, :no_rate}
  defp base_rate(currency, currency, _fx_rates), do: {:ok, @one}

  defp base_rate(security_currency, base_currency, fx_rates) do
    case Map.get(fx_rates, security_currency) do
      %Decimal{} = rate -> {:ok, rate}
      _none -> Fx.rate(security_currency, base_currency)
    end
  end

  # The displayed per-unit cost is derived from the folded total, never the
  # other way round; a non-positive quantity carries a zero basis by the
  # `cost_lots/1` invariant, so its average is zero too.
  defp average_unit_cost(quantity, cost_basis) do
    if Decimal.compare(quantity, @zero) == :gt do
      Decimal.div(cost_basis, quantity)
    else
      @zero
    end
  end

  defp put_holding_valuation(row, nil) do
    Map.merge(row, %{
      latest_price: nil,
      market_value: nil,
      unrealized_pnl_abs: nil,
      unrealized_pnl_pct: nil
    })
  end

  # A row without a derivable security-currency cost basis (ADR-0033
  # requirement 4) keeps its price-derived market value but reports no P&L —
  # a blind cross-currency comparison is never resurrected.
  defp put_holding_valuation(%{cost_basis: nil} = row, %Decimal{} = latest_price) do
    Map.merge(row, %{
      latest_price: latest_price,
      market_value: Decimal.mult(row.quantity, latest_price),
      unrealized_pnl_abs: nil,
      unrealized_pnl_pct: nil
    })
  end

  defp put_holding_valuation(row, %Decimal{} = latest_price) do
    market_value = Decimal.mult(row.quantity, latest_price)
    abs_pnl = Decimal.sub(market_value, row.cost_basis)

    pct_pnl =
      if Decimal.equal?(row.cost_basis, 0),
        do: Decimal.new(0),
        else: Decimal.div(abs_pnl, row.cost_basis)

    Map.merge(row, %{
      latest_price: latest_price,
      market_value: market_value,
      unrealized_pnl_abs: abs_pnl,
      unrealized_pnl_pct: pct_pnl
    })
  end

  defp holding_price(security_id, prices) do
    case Map.get(prices, security_id) do
      %Decimal{} = price -> price
      _ -> adjusted_latest_close(security_id)
    end
  end

  # Latest close in the current display basis (ADR-0028 §2): a stale raw
  # close from before a split's effective date is divided by the cumulative
  # later ratio before it prices a post-split quantity.
  defp adjusted_latest_close(security_id) do
    case Quotes.adjusted_latest(security_id) do
      %{close: %Decimal{} = close} -> close
      _ -> nil
    end
  end

  @doc """
  Returns the current holdings of a single security, split by
  (portfolio, depot).

  Quantities are the canonical position quantities (`Ledger.Positions`,
  ADR-0011), so trades, deliveries and security transfers all move them.
  The moving-average cost basis follows the shares through the same kinds
  (see `cost_lots/1`), per depot.

  Rows carry the same security-currency basis and ADR-0033 base-currency
  decomposition as `holdings_for_portfolio/2` (each row against its own
  portfolio's base currency), so the two surfaces cannot disagree.

  Pass `:latest_price` to inject the comparison price for tests; otherwise
  reads it from `Catalog.Quotes.adjusted_latest/1` (the split-adjusted
  display basis, ADR-0028 §2). Pass `:fx_rates` to inject current hub rates
  for tests (see `holdings_for_portfolio/2`).
  """
  def holdings_for_security(security_id, opts \\ []) when is_integer(security_id) do
    latest_price =
      Keyword.get_lazy(opts, :latest_price, fn -> adjusted_latest_close(security_id) end)

    fx_rates = Keyword.get(opts, :fx_rates, %{})
    security = Repo.get(Security, security_id)
    security_currency = security && security.currency_code
    transactions = list_transactions_for_security(security_id)
    lots = cost_lots(transactions)
    depots = depots_by_id(transactions)

    transactions
    |> Positions.calculate()
    |> Enum.map(fn {{account_id, _security_id} = key, quantity} ->
      %{portfolio: portfolio, depot: depot} = Map.fetch!(depots, account_id)
      lot = lot_for(lots, key)
      cost_basis = if lot.cost_known, do: lot.cost, else: nil
      base_currency = portfolio.base_currency_code

      %{
        portfolio: portfolio,
        depot: depot,
        quantity: quantity,
        avg_cost: cost_basis && average_unit_cost(quantity, cost_basis),
        cost_basis: cost_basis
      }
      |> Map.merge(base_cost_fields(lot, base_currency))
      |> decorate_holding(latest_price)
      |> put_decomposition(:current_value, lot, security_currency, base_currency, fx_rates)
    end)
    |> Enum.sort_by(& &1.portfolio.name)
  end

  # Depot (and owning portfolio) structs per securities-account id, taken from
  # the preloaded transactions. The counter account of a `security_transfer`
  # belongs to the same portfolio (enforced by FK), so the transaction's
  # portfolio serves both legs.
  defp depots_by_id(transactions) do
    Enum.reduce(transactions, %{}, fn tx, acc ->
      acc
      |> put_depot(tx.securities_account, tx.portfolio)
      |> put_depot(tx.counter_securities_account, tx.portfolio)
    end)
  end

  defp put_depot(acc, %SecuritiesAccount{} = depot, portfolio),
    do: Map.put_new(acc, depot.id, %{depot: depot, portfolio: portfolio})

  defp put_depot(acc, _not_loaded_or_nil, _portfolio), do: acc

  # The cash-only kinds that are explicitly cost-neutral: they move no
  # shares, so the moving-average cost fold ignores them by name. Every kind
  # in `Transaction.kinds/0` must be either handled by an `apply_cost_effect`
  # clause or listed here — there is deliberately no catch-all (ADR-0028 §3),
  # enforced by `test/invariants/cost_fold_kind_coverage_test.exs`, so a new
  # kind with cost semantics fails loudly instead of silently folding to
  # a no-op.
  @cost_neutral_kinds [
    "dividend",
    "interest",
    "deposit",
    "removal",
    "fee",
    "tax",
    "tax_refund",
    "cash_transfer",
    "balance_adjustment"
  ]

  # Moving-average cost lots per `{securities_account, security}`, folded in
  # the shared `{date, intra_day_order, id}` replay order (the cost companion
  # of `Positions.calculate/1`; a same-day split applies before the day's
  # trades, ADR-0028 §3). The cost follows the shares: buys and priced inbound
  # deliveries add their cost, sells and outbound deliveries remove at the
  # lot's running average, a `security_transfer` carries the removed cost
  # into the counter depot, and an unpriced delivery moves quantity at zero
  # cost. A `split` scales the lot quantity of its own portfolio and leaves
  # the lot's total cost unchanged, so the per-share average divides. A lot's
  # cost never goes below zero: a removal beyond the held quantity takes out
  # the full remaining cost, so an over-sold or over-delivered (negative) lot
  # always carries a zero basis.
  #
  # ADR-0033: every lot carries a cost PAIR — `cost` in the security's own
  # currency (`cost_known` false when a contributing acquisition had no
  # derivable security-currency leg) and `base` (the settlement-leg cost,
  # its single currency, and whether it is well-defined). Removals slice both
  # proportionally; splits scale quantity and leave both invariant. The fold
  # is pure: the legs come from transaction data (price, ADR-0015
  # `security_amount`/`settlement_amount`, the preloaded cash-account
  # currency) — rates are never looked up inside the reducer.
  defp cost_lots(transactions) do
    ordered = Projection.replay_sort(transactions)
    accounts = Projection.account_portfolios(ordered)
    Enum.reduce(ordered, %{}, &apply_cost_effect(&1, &2, accounts))
  end

  defp apply_cost_effect(%{type: "buy"} = tx, lots, _accounts),
    do: add_cost(lots, lot_key(tx), tx.quantity, acquisition_legs(tx, tx.price))

  defp apply_cost_effect(%{type: "inbound_delivery"} = tx, lots, _accounts),
    do: add_cost(lots, lot_key(tx), tx.quantity, acquisition_legs(tx, tx.price || @zero))

  defp apply_cost_effect(%{type: type} = tx, lots, _accounts)
       when type in ["sell", "outbound_delivery"],
       do: lots |> remove_cost(lot_key(tx), tx.quantity) |> elem(0)

  defp apply_cost_effect(%{type: "security_transfer"} = tx, lots, _accounts) do
    {lots, moved_cost} = remove_cost(lots, lot_key(tx), tx.quantity)
    add_cost(lots, {tx.counter_securities_account_id, tx.security_id}, tx.quantity, moved_cost)
  end

  # ADR-0028 §3: the lot's quantity scales by the ratio (quantized once at
  # volume scale 6), its total cost basis is invariant, so the per-share
  # average cost divides. Scoped to the split row's own portfolio.
  defp apply_cost_effect(%{type: "split"} = tx, lots, accounts) do
    ratio = {tx.split_ratio_numerator, tx.split_ratio_denominator}

    Map.new(lots, fn {key, lot} ->
      {key, maybe_scale_lot(key, lot, tx, ratio, accounts)}
    end)
  end

  defp apply_cost_effect(%{type: type}, lots, _accounts) when type in @cost_neutral_kinds,
    do: lots

  # The two legs of an acquisition (ADR-0033), from transaction data only.
  #
  # Security-currency leg: `quantity * price` when the booking is in the
  # security's own currency (manual ADR-0015 bookings and the same-currency
  # majority), else the stored ADR-0015 `security_amount`; a cross-currency
  # booking without one has no derivable native leg — flagged, never guessed.
  #
  # Settlement leg: the stored `settlement_amount` in the cash account's
  # currency, else `quantity * price` in the transaction currency (the
  # degenerate same-currency pair). A zero-cost contribution constrains no
  # currency.
  defp acquisition_legs(tx, price) do
    gross = Decimal.mult(tx.quantity, price)
    security_currency = transaction_security_currency(tx)

    {native_cost, native_known} =
      cond do
        is_nil(security_currency) or tx.currency_code == security_currency -> {gross, true}
        match?(%Decimal{}, tx.security_amount) -> {tx.security_amount, true}
        true -> {@zero, false}
      end

    base =
      case tx.settlement_amount do
        %Decimal{} = amount ->
          case settlement_leg_currency(tx, security_currency) do
            :unknown -> %{amount: amount, currency: nil, known: false}
            currency -> normalize_base(%{amount: amount, currency: currency, known: true})
          end

        _none ->
          normalize_base(%{amount: gross, currency: tx.currency_code, known: true})
      end

    %{cost: native_cost, cost_known: native_known, base: base}
  end

  defp transaction_security_currency(%{security: %Security{currency_code: currency}}),
    do: currency

  defp transaction_security_currency(_transaction), do: nil

  # The currency the settlement leg is denominated in: the linked cash
  # account's (preloaded by every fold caller); for a booking already in the
  # account currency (the backfilled import form) the transaction currency is
  # that same currency. Unresolvable is flagged, not guessed.
  defp settlement_leg_currency(%{cash_account: %CashAccount{currency_code: currency}}, _native),
    do: currency

  defp settlement_leg_currency(%{currency_code: currency}, security_currency)
       when currency != security_currency,
       do: currency

  defp settlement_leg_currency(_transaction, _security_currency), do: :unknown

  # A zero settlement leg constrains no currency, so e.g. an unpriced
  # delivery can never poison a lot's settlement currency.
  defp normalize_base(%{amount: amount} = base) do
    if Decimal.equal?(amount, @zero), do: %{base | currency: nil}, else: base
  end

  defp maybe_scale_lot({account_id, security_id}, lot, tx, ratio, accounts) do
    if security_id == tx.security_id and Map.get(accounts, account_id) == tx.portfolio_id do
      %{lot | quantity: Projection.scale_quantity(lot.quantity, ratio)}
    else
      lot
    end
  end

  defp lot_key(tx), do: {tx.securities_account_id, tx.security_id}

  defp lot_for(lots, key), do: Map.get(lots, key, empty_lot())

  # Shares that merely cover a short (negative) lot carry no cost forward;
  # only the portion that ends up above zero enters at the addition's unit
  # cost. A negative lot always has zero cost (see `remove_cost/3`), so the
  # positive branch never mixes in stale cost. Both legs of the cost pair
  # follow the same rule; the availability flags travel with the cost they
  # describe.
  defp add_cost(lots, key, quantity, legs) do
    lot = Map.get(lots, key, empty_lot())
    new_quantity = Decimal.add(lot.quantity, quantity)

    new_lot =
      cond do
        Decimal.compare(lot.quantity, @zero) != :lt ->
          %{
            quantity: new_quantity,
            cost: Decimal.add(lot.cost, legs.cost),
            cost_known: lot.cost_known and legs.cost_known,
            base: merge_base(lot.base, legs.base)
          }

        Decimal.compare(new_quantity, @zero) != :gt ->
          %{empty_lot() | quantity: new_quantity}

        true ->
          %{
            quantity: new_quantity,
            cost: legs.cost |> Decimal.mult(new_quantity) |> Decimal.div(quantity),
            cost_known: legs.cost_known,
            base:
              normalize_base(%{
                legs.base
                | amount: legs.base.amount |> Decimal.mult(new_quantity) |> Decimal.div(quantity)
              })
          }
      end

    Map.put(lots, key, new_lot)
  end

  # Two settlement legs merge only when they are denominated in one single
  # currency (a zero leg constrains none); anything else is a mixed —
  # ill-defined — base cost and is flagged, never summed into a number
  # denominated in no currency at all (ADR-0033 requirement 5).
  defp merge_base(a, b) do
    case merged_base_currency(a, b) do
      :mixed ->
        %{amount: Decimal.add(a.amount, b.amount), currency: nil, known: false}

      currency ->
        %{amount: Decimal.add(a.amount, b.amount), currency: currency, known: a.known and b.known}
    end
  end

  defp merged_base_currency(%{currency: nil}, %{currency: currency}), do: currency
  defp merged_base_currency(%{currency: currency}, %{currency: nil}), do: currency
  defp merged_base_currency(%{currency: currency}, %{currency: currency}), do: currency
  defp merged_base_currency(_a, _b), do: :mixed

  # Removes shares at the lot's running average and returns the removed cost
  # pair (a `security_transfer` hands it to the receiving depot). Removing
  # the whole lot — or more — takes the exact remaining cost, so closing a
  # position never leaves a rounding residue behind; a closed or negative
  # lot's zero basis is a defined, exact value, so its flags reset clean.
  defp remove_cost(lots, key, quantity) do
    lot = Map.get(lots, key, empty_lot())

    {removed_cost, removed_base} =
      if Decimal.compare(lot.quantity, quantity) == :gt do
        {quantity |> Decimal.mult(lot.cost) |> Decimal.div(lot.quantity),
         quantity |> Decimal.mult(lot.base.amount) |> Decimal.div(lot.quantity)}
      else
        {lot.cost, lot.base.amount}
      end

    new_quantity = Decimal.sub(lot.quantity, quantity)

    updated =
      if Decimal.compare(new_quantity, @zero) != :gt do
        %{empty_lot() | quantity: new_quantity}
      else
        %{
          quantity: new_quantity,
          cost: Decimal.sub(lot.cost, removed_cost),
          cost_known: lot.cost_known,
          base: normalize_base(%{lot.base | amount: Decimal.sub(lot.base.amount, removed_base)})
        }
      end

    moved = %{
      cost: removed_cost,
      cost_known: lot.cost_known,
      base:
        normalize_base(%{
          amount: removed_base,
          currency: lot.base.currency,
          known: lot.base.known
        })
    }

    {Map.put(lots, key, updated), moved}
  end

  defp empty_lot do
    %{
      quantity: @zero,
      cost: @zero,
      cost_known: true,
      base: %{amount: @zero, currency: nil, known: true}
    }
  end

  defp decorate_holding(row, nil) do
    Map.merge(row, %{
      latest_price: nil,
      current_value: nil,
      unrealized_pnl_abs: nil,
      unrealized_pnl_pct: nil
    })
  end

  # See `put_holding_valuation/2` — a missing native leg reports no P&L.
  defp decorate_holding(%{cost_basis: nil} = row, %Decimal{} = latest_price) do
    Map.merge(row, %{
      latest_price: latest_price,
      current_value: Decimal.mult(row.quantity, latest_price),
      unrealized_pnl_abs: nil,
      unrealized_pnl_pct: nil
    })
  end

  defp decorate_holding(row, %Decimal{} = latest_price) do
    current_value = Decimal.mult(row.quantity, latest_price)
    abs_pnl = Decimal.sub(current_value, row.cost_basis)

    pct_pnl =
      if Decimal.equal?(row.cost_basis, 0),
        do: Decimal.new(0),
        else: Decimal.div(abs_pnl, row.cost_basis)

    Map.merge(row, %{
      latest_price: latest_price,
      current_value: current_value,
      unrealized_pnl_abs: abs_pnl,
      unrealized_pnl_pct: pct_pnl
    })
  end

  defp transaction_for_matcher(%Transaction{} = tx, security_currency) do
    %{
      id: tx.id,
      portfolio_id: tx.portfolio_id,
      type: tx.type,
      date: tx.date,
      quantity: tx.quantity,
      price: tx.price,
      fees: tx.fees,
      taxes: tx.taxes,
      currency_code: tx.currency_code,
      split_ratio_numerator: tx.split_ratio_numerator,
      split_ratio_denominator: tx.split_ratio_denominator,
      # ADR-0033 lot legs: the per-unit security-currency price (nil when no
      # native leg is derivable) and the per-unit settlement leg with its
      # currency, so open lots carry the same cost pair as the holdings fold.
      native_unit_price: native_unit_price(tx, security_currency),
      settlement_unit_price: settlement_unit_price(tx),
      settlement_currency: matcher_settlement_currency(tx, security_currency)
    }
  end

  defp native_unit_price(tx, security_currency) do
    cond do
      is_nil(security_currency) or tx.currency_code == security_currency ->
        tx.price

      match?(%Decimal{}, tx.security_amount) and positive_decimal?(tx.quantity) ->
        Decimal.div(tx.security_amount, tx.quantity)

      true ->
        nil
    end
  end

  defp settlement_unit_price(tx) do
    case tx.settlement_amount do
      %Decimal{} = amount ->
        if positive_decimal?(tx.quantity), do: Decimal.div(amount, tx.quantity), else: nil

      _none ->
        tx.price
    end
  end

  defp matcher_settlement_currency(tx, security_currency) do
    case tx.settlement_amount do
      %Decimal{} ->
        case settlement_leg_currency(tx, security_currency) do
          :unknown -> nil
          currency -> currency
        end

      _none ->
        tx.currency_code
    end
  end

  defp positive_decimal?(%Decimal{} = value), do: Decimal.compare(value, @zero) == :gt
  defp positive_decimal?(_other), do: false

  # Open-lot decoration (ADR-0033): the unrealised P&L compares the latest
  # close against the lot's SECURITY-currency basis (`buy_price_native`), and
  # each lot carries the same price/currency decomposition as the holdings —
  # against the EUR hub, since FIFO lots are matched per security across
  # portfolios. A lot without a derivable native leg, a hub-currency
  # settlement leg or a current rate is honestly unavailable.
  defp decorate_open_lot(lot, latest_price, security_currency, fx_rates) do
    base_cost = lot.settlement_unit_price && Decimal.mult(lot.quantity, lot.settlement_unit_price)

    lot =
      Map.merge(lot, %{
        latest_price: latest_price,
        base_cost: base_cost,
        base_currency: lot.settlement_currency
      })

    cond do
      is_nil(lot.buy_price_native) ->
        lot
        |> Map.merge(%{unrealized_pnl_abs: nil, unrealized_pnl_pct: nil})
        |> Map.merge(PnlDecomposition.unavailable(:missing_native_cost))

      is_nil(latest_price) ->
        lot
        |> Map.merge(%{unrealized_pnl_abs: nil, unrealized_pnl_pct: nil})
        |> Map.merge(PnlDecomposition.unavailable(:no_price))

      true ->
        current_value = Decimal.mult(lot.quantity, latest_price)
        cost = Decimal.mult(lot.quantity, lot.buy_price_native)
        abs_pnl = Decimal.sub(current_value, cost)
        pct_pnl = if Decimal.equal?(cost, 0), do: Decimal.new(0), else: Decimal.div(abs_pnl, cost)

        lot
        |> Map.merge(%{unrealized_pnl_abs: abs_pnl, unrealized_pnl_pct: pct_pnl})
        |> Map.merge(
          open_lot_decomposition(lot, current_value, cost, security_currency, fx_rates)
        )
    end
  end

  defp open_lot_decomposition(lot, current_value, cost, security_currency, fx_rates) do
    cond do
      is_nil(lot.base_cost) or lot.settlement_currency != @hub ->
        PnlDecomposition.unavailable(:missing_base_cost)

      true ->
        case base_rate(security_currency, @hub, fx_rates) do
          {:ok, rate} -> PnlDecomposition.decompose(current_value, cost, lot.base_cost, rate)
          {:error, :no_rate} -> PnlDecomposition.unavailable(:missing_fx)
        end
    end
  end

  def count_transactions do
    Repo.aggregate(Transaction, :count, :id)
  end

  @doc """
  The set of security ids referenced by at least one booking. The import
  preview's pre-apply inverse check (ADR-0029 §2) uses it to scope leftover
  surfacing to securities affected by imports — a watch-only security without
  bookings legitimately matches no export row and must not drown the signal.
  """
  def security_ids_with_transactions do
    from(t in Transaction,
      where: not is_nil(t.security_id),
      distinct: true,
      select: t.security_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Records a transaction on behalf of `actor` (FR-28). The `transactions` row and
  its audit-journal entry commit in one transaction (ADR-0017); the table is
  guard-armed, so every ledger write is attributable.
  """
  def create_transaction(%Actor{} = actor, attrs) when is_map(attrs) do
    with {:ok, attrs} <- maybe_derive_linked_cash_account(attrs) do
      changeset =
        %Transaction{}
        |> Transaction.changeset(derive_settlement_fx_rate(attrs))
        |> validate_cash_account_currency()

      Multi.new()
      |> Multi.insert(:transaction, changeset)
      |> Journal.record(actor,
        resource_type: "transaction",
        operation: :create,
        source: :transaction
      )
      |> Repo.transaction()
      |> transaction_write_result()
    end
  end

  @doc """
  Records an absolute cash-balance snapshot for one cash account (see ADR-0009).

  Stores a `balance_adjustment` transaction anchoring the account to `amount`
  (the absolute balance, which may be negative) as of `date`. The portfolio and
  currency are taken from the cash account. Returns `{:ok, transaction}` or
  `{:error, changeset}`.
  """
  def set_cash_balance(%Actor{} = actor, %CashAccount{} = cash_account, attrs)
      when is_map(attrs) do
    create_transaction(actor, %{
      type: "balance_adjustment",
      portfolio_id: cash_account.portfolio_id,
      cash_account_id: cash_account.id,
      currency_code: cash_account.currency_code,
      date: get_attr(attrs, :date),
      gross_amount: get_attr(attrs, :amount),
      notes: get_attr(attrs, :notes)
    })
  end

  def get_transaction(id) when is_integer(id), do: Repo.get(Transaction, id)

  @doc """
  Updates a transaction on behalf of `actor` (FR-28). The update and its audit
  journal entry (with the pre-image as `before`) commit in one transaction.
  """
  def update_transaction(%Actor{} = actor, %Transaction{} = transaction, attrs)
      when is_map(attrs) do
    changeset =
      transaction
      |> Transaction.changeset(derive_settlement_fx_rate(attrs))
      |> validate_cash_account_currency()

    Multi.new()
    |> Multi.update(:transaction, changeset)
    |> Journal.record(actor,
      resource_type: "transaction",
      operation: :update,
      source: :transaction,
      before: transaction
    )
    |> Repo.transaction()
    |> transaction_write_result()
  end

  @doc """
  Deletes a transaction on behalf of `actor` (FR-28). The deletion is journaled
  with the full `before` snapshot so a removed booking stays traceable.
  """
  def delete_transaction(%Actor{} = actor, %Transaction{} = transaction) do
    Multi.new()
    |> Multi.delete(:transaction, transaction)
    |> Journal.record(actor,
      resource_type: "transaction",
      operation: :delete,
      source: :transaction,
      before: transaction
    )
    |> Repo.transaction()
    |> transaction_write_result()
  end

  defp transaction_write_result({:ok, %{transaction: transaction}}), do: {:ok, transaction}

  defp transaction_write_result({:error, :transaction, %Ecto.Changeset{} = changeset, _changes}),
    do: {:error, changeset}

  # Cross-record currency check (issue #343): a transaction is booked in
  # its cash account's currency, so its `currency_code` must equal the
  # linked cash account's currency and, for a `cash_transfer`, the counter
  # cash account's currency too. The cash account currencies are not on the
  # changeset, so they are loaded here (mirroring
  # `derive_linked_cash_account/1`) and handed to the pure validator on the
  # schema. This is validation only: no stored amount is FX-converted
  # (ADR-0007 FX derivation stays out of scope). A changeset that is
  # already invalid is left untouched so the currency error never masks a
  # more fundamental one.
  defp validate_cash_account_currency(%Ecto.Changeset{valid?: false} = changeset),
    do: changeset

  defp validate_cash_account_currency(%Ecto.Changeset{} = changeset) do
    cash_account_id = Ecto.Changeset.get_field(changeset, :cash_account_id)
    counter_cash_account_id = Ecto.Changeset.get_field(changeset, :counter_cash_account_id)
    currencies = cash_account_currencies([cash_account_id, counter_cash_account_id])

    Transaction.validate_cash_account_currency(changeset, currencies)
  end

  defp cash_account_currencies(ids) do
    ids
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> case do
      [] ->
        %{}

      present ->
        Repo.all(
          from(c in CashAccount,
            where: c.id in ^present,
            select: {c.id, c.currency_code}
          )
        )
        |> Map.new()
    end
  end

  # Cross-currency settlement (issue #388, ADR-0015): when the broker confirms
  # both legs (security-currency trade amount and settlement-currency cash
  # amount) but no explicit rate, derive the settlement FX rate as
  # settlement_amount / security_amount, the broker's actual rate. This is the
  # most accurate source; it is never a direct cross rate (it relates the two
  # amounts the broker already provided). An explicitly supplied rate wins.
  # Derivation runs at full Decimal precision; the 20,6 column stores it at the
  # column scale. Pure arithmetic — the reducer never looks a rate up.
  defp derive_settlement_fx_rate(attrs) do
    with nil <- decimal_attr(attrs, :settlement_fx_rate),
         %Decimal{} = security_amount <- decimal_attr(attrs, :security_amount),
         %Decimal{} = settlement_amount <- decimal_attr(attrs, :settlement_amount),
         false <- Decimal.equal?(security_amount, 0) do
      rate = settlement_amount |> Decimal.div(security_amount) |> Decimal.round(6)
      put_attr(attrs, :settlement_fx_rate, rate)
    else
      _no_derivation -> attrs
    end
  end

  defp decimal_attr(attrs, field) do
    case get_attr(attrs, field) do
      %Decimal{} = value -> value
      value when is_binary(value) -> parse_decimal(value)
      _other -> nil
    end
  end

  defp parse_decimal(value) do
    case Decimal.parse(value) do
      {decimal, ""} -> decimal
      _invalid -> nil
    end
  end

  defp maybe_derive_linked_cash_account(attrs) do
    case get_attr(attrs, :type) do
      type when type in ["buy", "sell"] -> derive_linked_cash_account(attrs)
      _other -> {:ok, attrs}
    end
  end

  @doc """
  Held quantities per `{securities_account, security}` of one portfolio,
  derived from the ledger (ADR-0004). Pass `as_of:` (a `%Date{}`) to project
  only transactions up to that date — the historical position set a depot
  snapshot marks (ADR-0027); omit it for the current holdings.
  """
  def positions_for_portfolio(portfolio_id, opts \\ []) when is_integer(portfolio_id) do
    portfolio_id
    |> list_transactions_for_portfolio()
    |> filter_up_to(Keyword.get(opts, :as_of))
    |> Positions.calculate()
  end

  defp filter_up_to(transactions, nil), do: transactions

  defp filter_up_to(transactions, %Date{} = as_of),
    do: Enum.filter(transactions, &(Date.compare(&1.date, as_of) != :gt))

  @doc """
  Currently held quantity per security, summed across every securities account
  of every portfolio.

  Derived on read from all transactions (ADR-0004) in one pass, so callers that
  need a global per-security view (e.g. the classification tree) avoid an
  N+1 query per node. Returns `%{security_id => Decimal}`; securities that net
  to zero are omitted by `Positions.calculate/1`.
  """
  def positions_by_security do
    list_transactions()
    |> Positions.calculate()
    |> Enum.reduce(%{}, fn {{_account_id, security_id}, quantity}, acc ->
      Map.update(acc, security_id, quantity, &Decimal.add(&1, quantity))
    end)
  end

  @doc """
  Data-quality report of impossible negative holdings (#570).

  An imported history can leave a derived holding quantity below zero — an
  unmodeled corporate action or rename chain booked more units out of a
  depot than ever went in. Such positions are import debris to repair, not
  data to classify, so this report surfaces them instead of letting them
  flow silently into holdings, allocation and valuation.

  Returns `%{as_of, note, rows, totals}`: `rows` is every (depot, security)
  position with a negative derived quantity (depot and security names
  included, sorted by security name then depot name), and `totals` carries
  each listed security's total quantity across **all** depots — so
  transfer debris (negative in one depot, positive in another) is
  distinguishable from a truly negative total. Quantities are Decimals.
  There is no repair wizard beyond splits (ADR-0028); the UI links to the
  security's transactions instead.
  """
  def negative_holdings_report do
    rows =
      list_transactions()
      |> Positions.calculate()
      |> Enum.group_by(
        fn {{_account_id, security_id}, _quantity} -> security_id end,
        fn {{account_id, _security_id}, quantity} -> {account_id, quantity} end
      )
      |> Enum.flat_map(&negative_rows_for_security/1)

    security_ids = rows |> Enum.map(& &1.security_id) |> Enum.uniq()
    securities = load_securities_by_id(security_ids)
    depots = securities_accounts_by_id(Enum.map(rows, & &1.securities_account_id))

    rows =
      rows
      |> Enum.map(fn row ->
        security = Map.get(securities, row.security_id)
        depot = Map.get(depots, row.securities_account_id)

        row
        |> Map.put(:security_name, security && security.name)
        |> Map.put(:isin, security && security.isin)
        |> Map.put(:depot_name, depot && depot.name)
        |> Map.put(:portfolio_id, depot && depot.portfolio_id)
      end)
      |> Enum.sort_by(&{&1.security_name, &1.depot_name})

    totals =
      rows
      |> Enum.map(&{&1.security_id, &1.security_name})
      |> Enum.uniq()
      |> Enum.map(fn {security_id, security_name} ->
        %{
          security_id: security_id,
          security_name: security_name,
          total_quantity: total_quantity_for(rows, security_id)
        }
      end)
      |> Enum.sort_by(& &1.security_name)

    %{
      as_of: Date.utc_today(),
      note:
        "Positions whose derived holding quantity is negative — import " <>
          "debris from unmodeled corporate actions, listed per depot with " <>
          "each security's total across all depots. Repair the security's " <>
          "transaction history; nothing is changed automatically.",
      rows: rows,
      totals: totals
    }
  end

  # Per-security fold: keeps the negative depot rows and remembers the total
  # across all depots so the report can show both.
  defp negative_rows_for_security({security_id, account_quantities}) do
    total =
      Enum.reduce(account_quantities, @zero, fn {_account_id, quantity}, acc ->
        Decimal.add(acc, quantity)
      end)

    account_quantities
    |> Enum.filter(fn {_account_id, quantity} -> Decimal.compare(quantity, @zero) == :lt end)
    |> Enum.map(fn {account_id, quantity} ->
      %{
        securities_account_id: account_id,
        security_id: security_id,
        quantity: quantity,
        total_quantity: total
      }
    end)
  end

  defp total_quantity_for(rows, security_id) do
    rows
    |> Enum.find(&(&1.security_id == security_id))
    |> Map.fetch!(:total_quantity)
  end

  defp load_securities_by_id([]), do: %{}

  defp load_securities_by_id(ids) do
    Repo.all(from(s in Portfolixir.Catalog.Security, where: s.id in ^ids))
    |> Map.new(&{&1.id, &1})
  end

  defp securities_accounts_by_id([]), do: %{}

  defp securities_accounts_by_id(ids) do
    Repo.all(from(a in SecuritiesAccount, where: a.id in ^Enum.uniq(ids)))
    |> Map.new(&{&1.id, &1})
  end

  @doc """
  The most recent own trade price per security across all portfolios.

  Like `latest_trade_prices/1` but global: the classification view values
  positions held in any portfolio, so the price fallback must not be scoped to
  one portfolio. Returns
  `%{security_id => %{price: Decimal, currency: String.t(), date: Date.t()}}`.
  """
  def latest_trade_prices do
    Repo.all(
      from(t in Transaction,
        where: t.type in ["buy", "sell"] and not is_nil(t.price),
        order_by: [asc: t.security_id, desc: t.date, desc: t.id],
        distinct: t.security_id,
        select: {t.security_id, %{price: t.price, currency: t.currency_code, date: t.date}}
      )
    )
    |> adjust_trade_prices()
  end

  @doc """
  The most recent own trade price per security in one portfolio.

  A buy or sell is a price observation; the valuation and the performance
  walk fall back to it when a security has no quote yet (Portfolio
  Performance seeds prices from bookings the same way). Returns
  `%{security_id => %{price: Decimal, currency: String.t(), date: Date.t()}}`.
  """
  def latest_trade_prices(portfolio_id) when is_integer(portfolio_id) do
    Repo.all(
      from(t in Transaction,
        where:
          t.portfolio_id == ^portfolio_id and t.type in ["buy", "sell"] and not is_nil(t.price),
        order_by: [asc: t.security_id, desc: t.date, desc: t.id],
        distinct: t.security_id,
        select: {t.security_id, %{price: t.price, currency: t.currency_code, date: t.date}}
      )
    )
    |> adjust_trade_prices()
  end

  # A fallback trade price is always raw basis (ADR-0028 §2): divide it by
  # the cumulative ratio of splits effective after the trade's date so it
  # prices post-split quantities in the current basis.
  defp adjust_trade_prices(rows) do
    events_by_security = rows |> Enum.map(&elem(&1, 0)) |> Quotes.split_events_by_security()

    Map.new(rows, fn {security_id, entry} ->
      case Map.get(events_by_security, security_id) do
        nil ->
          {security_id, entry}

        events ->
          price = QuoteAdjustment.display_trade_price(entry.price, entry.date, events)
          {security_id, %{entry | price: price}}
      end
    end)
  end

  defp ordered_transactions do
    from(transaction in Transaction,
      order_by: [desc: transaction.date, desc: transaction.id]
    )
  end

  defp derive_linked_cash_account(attrs) do
    with {:ok, securities_account_id} <- fetch_integer(attrs, :securities_account_id),
         %SecuritiesAccount{} = securities_account <-
           Repo.get(SecuritiesAccount, securities_account_id) do
      validate_selected_portfolio(attrs, securities_account)
    else
      :missing -> {:ok, attrs}
      :invalid -> {:ok, attrs}
      nil -> {:ok, attrs}
    end
  end

  defp validate_selected_portfolio(attrs, securities_account) do
    case fetch_integer(attrs, :portfolio_id) do
      {:ok, portfolio_id} when portfolio_id != securities_account.portfolio_id ->
        {:error,
         invalid_transaction(
           attrs,
           :securities_account_id,
           "must belong to the selected portfolio"
         )}

      _portfolio_ok ->
        validate_selected_cash_account(attrs, securities_account)
    end
  end

  defp validate_selected_cash_account(attrs, securities_account) do
    case fetch_integer(attrs, :cash_account_id) do
      {:ok, cash_account_id} when cash_account_id != securities_account.cash_account_id ->
        {:error, invalid_transaction(attrs, :cash_account_id, "must match the selected depot")}

      _missing_or_matching ->
        {:ok, put_attr(attrs, :cash_account_id, securities_account.cash_account_id)}
    end
  end

  defp invalid_transaction(attrs, field, message) do
    %Transaction{}
    |> Transaction.changeset(attrs)
    |> Ecto.Changeset.add_error(field, message)
    |> Map.put(:action, :insert)
  end

  defp fetch_integer(attrs, field) do
    value = get_attr(attrs, field)

    cond do
      is_integer(value) ->
        {:ok, value}

      is_binary(value) ->
        case Integer.parse(value) do
          {integer, ""} -> {:ok, integer}
          _invalid -> :invalid
        end

      is_nil(value) ->
        :missing

      true ->
        :invalid
    end
  end

  defp get_attr(attrs, field) do
    Map.get(attrs, field) || Map.get(attrs, Atom.to_string(field))
  end

  defp put_attr(attrs, field, value) do
    if Enum.any?(Map.keys(attrs), &is_binary/1) do
      Map.put(attrs, Atom.to_string(field), value)
    else
      Map.put(attrs, field, value)
    end
  end
end
