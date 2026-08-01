defmodule Portfolixir.Portfolios.Valuation do
  @moduledoc """
  Read-time market valuation of a portfolio.

  Prices each currently held position from its latest quote close, converts it
  into the portfolio's `base_currency_code` (see `Portfolixir.Fx`), sums the
  valued positions into a total, and reports each valued position's share
  (weight) of that total.

  Nothing is stored: like holdings and FIFO trades, the valuation is derived
  from transactions, quote history, and exchange rates on read (see ADR-0004,
  ADR-0007).

  A security without any quote is priced at the **latest own trade price
  across all portfolios** (a buy or sell is a price observation — Portfolio
  Performance seeds prices from bookings the same way); such positions carry
  `price_source: :trade` and are counted in `trade_priced_count` so the UI
  can flag the value as stale. The fallback is deliberately global (#406):
  the portfolio totals and the security detail resolve prices with the same
  semantics, so the two surfaces can never disagree about whether a price
  exists.

  A held position is reported as unvalued only when it has neither a quote
  nor a trade price **or** no exchange-rate path to the base currency, so a
  missing price or rate never silently distorts the total or the weights.
  Each position says which of the two it is (#406, owner decision
  2026-07-31): `unvalued_reason` is `:no_price` when no price resolves at
  all, and `:missing_fx` when a native price exists (kept in `latest_price`
  with its `price_currency`) but no stored FX path reaches the base
  currency — such positions count as NOT valued in base-currency totals.
  """

  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  @zero Decimal.new("0")
  @hub "EUR"

  @doc """
  Holdings and EUR-hub market value per security across **all** portfolios.

  Computes the global per-security quantity and its current market value once
  (a single ledger read plus the shared quote/trade-price/FX path), so a view
  that joins valuation onto a security tree never queries per node. Each
  security id maps to `%{quantity: Decimal, market_value: Decimal | nil,
  valued: boolean, latest_price: Decimal | nil, price_currency: String.t()
  | nil, price_source: :quote | :trade | nil, unvalued_reason: :no_price |
  :missing_fx | nil}`; `market_value` is `nil` (and `valued` false) when the
  security has neither a quote nor a trade price (`unvalued_reason:
  :no_price`), or no exchange-rate path to the EUR hub (`:missing_fx`, with
  the native price kept so callers can show it). Securities not currently
  held are absent from the map.

  Options (for tests):
    * `:prices` – `%{security_id => Decimal}` native price overrides; missing
      securities fall back to `Catalog.Quotes.adjusted_latest/1`
      (split-adjusted display basis, ADR-0028 §2).
  """
  def holdings_by_security(opts \\ []) do
    prices = Keyword.get(opts, :prices, %{})
    trade_prices = Ledger.latest_trade_prices()

    Ledger.positions_by_security()
    |> Map.new(fn {security_id, quantity} ->
      {security_id, value_security(security_id, quantity, {prices, trade_prices})}
    end)
  end

  @doc """
  Self-describing wrapper over `holdings_by_security/1` for the JSON API and MCP.

  Returns the global per-security valuation as a flat list sorted by
  `security_id` (each row keeps `security_id`, `quantity`, `market_value` and
  the `valued` flag), wrapped with the fixed hub `currency` (`"EUR"`), an
  `as_of` read date and a `note`. The map-keyed `holdings_by_security/1` stays
  the LiveView contract; this shape is what crosses the API boundary.

  `as_of` is the read date (`Date.utc_today/0`): the valuation is derived on
  read from the latest quote/trade price and FX rate, so there is no single
  stored snapshot date to report.

  Options are forwarded to `holdings_by_security/1` (e.g. `:prices` for tests).
  """
  def holdings_by_security_report(opts \\ []) do
    holdings =
      opts
      |> holdings_by_security()
      |> Enum.map(fn {security_id, valuation} ->
        Map.put(valuation, :security_id, security_id)
      end)
      |> Enum.sort_by(& &1.security_id)

    %{currency: @hub, as_of: Date.utc_today(), note: report_note(), holdings: holdings}
  end

  @doc """
  The global valuation status of one security (#406).

  Resolves the price with exactly the semantics the portfolio totals use
  (latest quote, then the global latest own trade price) and reports whether
  a stored FX path reaches every given base currency — pass the base
  currencies of the portfolios actually holding the security (review fix: a
  USD-base portfolio counts a USD position without any stored rate, so
  checking only the EUR hub could contradict that portfolio's totals). The
  default is the EUR hub. Powers the security detail's "counted in totals?"
  status line, so the detail and the portfolio totals can never disagree.

  Returns `%{latest_price: Decimal | nil, price_currency: String.t() | nil,
  price_source: :quote | :trade | nil, price_date: Date.t() | nil,
  valued: boolean, unvalued_reason: :no_price | :missing_fx | nil,
  missing_rate_currencies: [String.t()]}` — `missing_rate_currencies` lists
  the bases the known price cannot be converted into.
  """
  def security_status(security_id, bases \\ [@hub]) when is_integer(security_id) do
    bases = if bases == [], do: [@hub], else: bases
    security = Catalog.get_security(security_id)
    security_currency = security && security.currency_code
    trade_prices = Ledger.latest_trade_prices()

    {price, price_currency, price_source} =
      price_for(security_id, {%{}, trade_prices}, security_currency)

    # Quantity 1: only the convertibility of the price matters here.
    conversions =
      Enum.map(bases, fn base ->
        {base, market_value(Decimal.new("1"), price, price_currency, base)}
      end)

    missing_rate_currencies =
      for {base, {_value, false, :missing_fx}} <- conversions, do: base

    valued? = Enum.all?(conversions, fn {_base, {_value, valued?, _reason}} -> valued? end)

    unvalued_reason =
      cond do
        valued? -> nil
        is_nil(price) -> :no_price
        true -> :missing_fx
      end

    %{
      latest_price: price,
      price_currency: price_currency,
      price_source: price_source,
      price_date: price_date(security_id, price_source, trade_prices),
      valued: valued?,
      unvalued_reason: unvalued_reason,
      missing_rate_currencies: missing_rate_currencies
    }
  end

  defp price_date(security_id, :quote, _trade_prices) do
    case Quotes.adjusted_latest(security_id) do
      %{date: %Date{} = date} -> date
      _ -> nil
    end
  end

  defp price_date(security_id, :trade, trade_prices) do
    case Map.get(trade_prices, security_id) do
      %{date: %Date{} = date} -> date
      _ -> nil
    end
  end

  defp price_date(_security_id, _source, _trade_prices), do: nil

  defp report_note do
    "Each held security's global quantity and market value converted to the " <>
      "EUR hub at the latest stored rate; valued is false when a quote, trade " <>
      "price or rate path to EUR is missing — unvalued_reason says which " <>
      "(no_price: nothing resolves; missing_fx: latest_price/price_currency " <>
      "are known but no stored rate path reaches EUR)."
  end

  defp value_security(security_id, quantity, price_maps) do
    security = Catalog.get_security(security_id)
    security_currency = security && security.currency_code

    {price, price_currency, price_source} =
      price_for(security_id, price_maps, security_currency)

    {market_value, valued?, unvalued_reason} =
      market_value(quantity, price, price_currency, @hub)

    %{
      quantity: quantity,
      market_value: market_value,
      valued: valued?,
      latest_price: price,
      price_currency: price_currency,
      price_source: price_source,
      unvalued_reason: unvalued_reason
    }
  end

  @doc """
  Returns the live valuation for one portfolio, in the portfolio base currency.

  Options (for tests):
    * `:prices` – `%{security_id => Decimal}` native prices; missing securities
      fall back to `Catalog.Quotes.adjusted_latest/1`
      (split-adjusted display basis, ADR-0028 §2).
    * `:base_currency` – overrides the portfolio's base currency.
  """
  def for_portfolio(portfolio_id, opts \\ []) when is_integer(portfolio_id) do
    # `:view` (a view id) scopes the result to the holdings matching that view.
    # No view -> `:unscoped` -> every check passes -> byte-identical output (#444).
    # A vanished view degrades to `{:error, :view_not_found}` (fix round)
    # instead of raising into an async render or API request.
    case Buckets.load_scope(portfolio_id, Keyword.get(opts, :view)) do
      {:error, :view_not_found} = error -> error
      scope -> for_portfolio_scoped(portfolio_id, scope, opts)
    end
  end

  defp for_portfolio_scoped(portfolio_id, scope, opts) do
    prices = Keyword.get(opts, :prices, %{})

    base_currency =
      Keyword.get_lazy(opts, :base_currency, fn -> base_currency_for(portfolio_id) end)

    # Global trade-price fallback (#406): the portfolio totals resolve prices
    # exactly like the security detail and the global holdings view, so the
    # surfaces can never disagree about whether a price exists. A holding
    # whose only priced trade lives in another portfolio (delivery, transfer)
    # is therefore valued here too.
    trade_prices = Ledger.latest_trade_prices()

    positions =
      portfolio_id
      |> Ledger.positions_for_portfolio()
      |> Enum.filter(fn {{securities_account_id, security_id}, _quantity} ->
        Buckets.position_in_scope?(scope, securities_account_id, security_id)
      end)
      |> Enum.map(fn {{securities_account_id, security_id}, quantity} ->
        build_position(
          securities_account_id,
          security_id,
          quantity,
          {prices, trade_prices},
          base_currency
        )
      end)

    total = total_value(positions)

    positions =
      positions
      |> Enum.map(&put_weight(&1, total))
      |> Enum.sort_by(& &1.security_id)

    cash = cash_for(portfolio_id, base_currency, scope)
    total_with_cash = Decimal.add(total, cash.total)

    %{
      portfolio_id: portfolio_id,
      base_currency: base_currency,
      total_value: total,
      total_cash: cash.total,
      counting_cash: cash.counting_total,
      total_with_cash: total_with_cash,
      cash_quote: cash_quote(cash.counting_total, Decimal.add(total, cash.counting_total)),
      cash_balances: cash.balances,
      positions: positions,
      unvalued_count: Enum.count(positions, &(not &1.valued)),
      trade_priced_count: Enum.count(positions, &(&1.price_source == :trade))
    }
  end

  @doc """
  Returns the live valuation of a bucket **view across all portfolios**
  (ADR-0024), in `:base_currency` (default the EUR hub).

  A view is a global filter over buckets, so its account universe spans every
  portfolio. Portfolios partition the accounts, so iterating each portfolio's
  single-count position universe under one instance-wide scope
  (`Portfolixir.Buckets.load_global_scope/1`) values the deduplicated union of
  the view's accounts — an account tagged into several included buckets counts
  once, by construction. Pricing fallbacks (quote, then the **global** latest
  own trade price, #406) and the EUR-hub FX path are exactly
  `for_portfolio/2`'s, so a quote-less security is valued — or reported
  unvalued — exactly as in the portfolio's own valuation.

  With `view_id == nil` the result is the "everything" scope: the unscoped
  union over all portfolios, Decimal-equal to summing the unscoped
  `for_portfolio/2` totals. A vanished `view_id` returns
  `{:error, :view_not_found}` (fix round) instead of raising.

  The result mirrors `for_portfolio/2` with `view_id` in place of
  `portfolio_id`, plus `overlap` (`Portfolixir.Buckets.scope_overlap/1`): which
  depots/cash accounts carry more than one of the view's included buckets —
  data for UI badges, not a correction (the totals are already deduplicated).

  Options (for tests):
    * `:prices` – `%{security_id => Decimal}` native prices; missing securities
      fall back to `Catalog.Quotes.adjusted_latest/1`
      (split-adjusted display basis, ADR-0028 §2).
    * `:base_currency` – overrides the EUR-hub default.
  """
  def for_view(view_id, opts \\ []) when is_integer(view_id) or is_nil(view_id) do
    case Buckets.load_global_scope(view_id) do
      {:error, :view_not_found} = error -> error
      scope -> for_view_scoped(view_id, scope, opts)
    end
  end

  defp for_view_scoped(view_id, scope, opts) do
    prices = Keyword.get(opts, :prices, %{})
    base_currency = Keyword.get(opts, :base_currency, @hub)

    # Global trade-price fallback (#406), shared across the portfolio loop:
    # the same resolution as `for_portfolio/2` and `holdings_by_security/1`,
    # so `for_view(nil)` stays Decimal-equal to the sum of the unscoped
    # `for_portfolio/2` totals even for quote-less securities held in one
    # portfolio but traded only in another.
    trade_prices = Ledger.latest_trade_prices()

    positions =
      Portfolios.list_portfolios()
      |> Enum.flat_map(fn portfolio ->
        portfolio.id
        |> Ledger.positions_for_portfolio()
        |> Enum.filter(fn {{securities_account_id, security_id}, _quantity} ->
          Buckets.position_in_scope?(scope, securities_account_id, security_id)
        end)
        |> Enum.map(fn {{securities_account_id, security_id}, quantity} ->
          build_position(
            securities_account_id,
            security_id,
            quantity,
            {prices, trade_prices},
            base_currency
          )
        end)
      end)

    total = total_value(positions)

    positions =
      positions
      |> Enum.map(&put_weight(&1, total))
      |> Enum.sort_by(&{&1.security_id, &1.securities_account_id})

    cash =
      cash_summary(Portfolios.list_cash_accounts(), Ledger.cash_balances(), base_currency, scope)

    total_with_cash = Decimal.add(total, cash.total)

    %{
      view_id: view_id,
      base_currency: base_currency,
      total_value: total,
      total_cash: cash.total,
      counting_cash: cash.counting_total,
      total_with_cash: total_with_cash,
      cash_quote: cash_quote(cash.counting_total, Decimal.add(total, cash.counting_total)),
      cash_balances: cash.balances,
      positions: positions,
      unvalued_count: Enum.count(positions, &(not &1.valued)),
      trade_priced_count: Enum.count(positions, &(&1.price_source == :trade)),
      overlap: Buckets.scope_overlap(scope),
      # "Matches no accounts" hint data (fix round): a view whose resolution
      # matches nothing should say so instead of showing a silent 0 total.
      matches_no_accounts: not Buckets.scope_matches_any_account?(scope)
    }
  end

  # Cash as a share of the whole portfolio, the "Cashquote". Only deployable
  # cash enters the quote (free_cash accounts with a non-negative balance, FR6) —
  # numerator and denominator are computed as if the other accounts did not
  # exist, so a reserve account or a drawn credit line never inflates the
  # private quote (see ADR-0009). Reported alongside the totals so callers do
  # not have to divide themselves; `0` when there is nothing to value yet.
  defp cash_quote(%Decimal{} = counting_cash, %Decimal{} = counting_total) do
    if Decimal.equal?(counting_total, @zero) do
      @zero
    else
      Decimal.div(counting_cash, counting_total)
    end
  end

  # Per-account cash balances (in account currency) plus their sum converted to
  # the portfolio base currency. An account whose currency has no rate path to
  # the base is reported unvalued and left out of `total_cash`, mirroring how
  # unpriceable positions are handled. `total` spans all valued accounts (so a
  # drawn credit line's negative balance still reduces net worth, FR7);
  # `counting_total` is the deployable cash only (FR6).
  defp cash_for(portfolio_id, base_currency, scope) do
    balances = Ledger.cash_balances(portfolio_id: portfolio_id)
    accounts = Portfolios.list_cash_accounts_for_portfolio(portfolio_id)
    cash_summary(accounts, balances, base_currency, scope)
  end

  defp cash_summary(accounts, balances, base_currency, scope) do
    entries =
      accounts
      |> Enum.filter(&Buckets.cash_in_scope?(scope, &1.id))
      |> Enum.map(fn account ->
        balance = Map.get(balances, account.id, @zero)
        {base_value, valued?} = convert_cash(balance, account.currency_code, base_currency)

        %{
          cash_account_id: account.id,
          name: account.name,
          currency: account.currency_code,
          balance: balance,
          base_value: base_value,
          valued: valued?,
          liquidity_role: account.liquidity_role,
          deployable: deployable?(account.liquidity_role, balance)
        }
      end)
      |> Enum.sort_by(& &1.cash_account_id)

    valued = Enum.filter(entries, & &1.valued)
    total = sum_base_values(valued)
    counting_total = valued |> Enum.filter(& &1.deployable) |> sum_base_values()

    %{balances: entries, total: total, counting_total: counting_total}
  end

  # FR6/FR7: deployable cash is genuine spendable cash only. A `free_cash`
  # account counts when its balance is non-negative; an overdrawn `free_cash`
  # account contributes nothing to deployable cash. `credit_line` never counts
  # (type beats sign — even a positive balance is not free cash, and a drawn
  # negative balance is a liability, not headroom). `reserve` is excluded.
  defp deployable?("free_cash", %Decimal{} = balance),
    do: Decimal.compare(balance, @zero) != :lt

  defp deployable?(_role, _balance), do: false

  defp sum_base_values(entries) do
    Enum.reduce(entries, @zero, fn entry, acc -> Decimal.add(acc, entry.base_value) end)
  end

  defp convert_cash(%Decimal{} = balance, from, base) when is_binary(from) and is_binary(base) do
    case Fx.convert(balance, from, base) do
      {:ok, converted} -> {converted, true}
      {:error, _reason} -> {nil, false}
    end
  end

  defp convert_cash(_balance, _from, _base), do: {nil, false}

  defp build_position(securities_account_id, security_id, quantity, price_maps, base_currency) do
    security = Catalog.get_security(security_id)
    security_currency = security && security.currency_code

    {price, price_currency, price_source} =
      price_for(security_id, price_maps, security_currency)

    {market_value, valued?, unvalued_reason} =
      market_value(quantity, price, price_currency, base_currency)

    %{
      securities_account_id: securities_account_id,
      security_id: security_id,
      security_name: security && security.name,
      asset_class: security && Security.effective_asset_class(security),
      security_currency: security_currency,
      quantity: quantity,
      latest_price: price,
      price_currency: price_currency,
      price_source: price_source,
      market_value: market_value,
      weight: nil,
      valued: valued?,
      unvalued_reason: unvalued_reason
    }
  end

  defp market_value(quantity, %Decimal{} = price, from, base)
       when is_binary(from) and is_binary(base) do
    native = Decimal.mult(quantity, price)

    case Fx.convert(native, from, base) do
      {:ok, converted} -> {converted, true, nil}
      {:error, _reason} -> {nil, false, :missing_fx}
    end
  end

  # No resolvable price at all — distinct from a priced position that only
  # lacks a rate path (#406). A resolved price with a nil currency cannot be
  # converted either; it is reported as :missing_fx because a price exists.
  defp market_value(_quantity, nil, _from, _base), do: {nil, false, :no_price}
  defp market_value(_quantity, _price, _from, _base), do: {nil, false, :missing_fx}

  # Price resolution order: explicit test override, latest quote, latest own
  # trade (each with the currency the price is denominated in).
  defp price_for(security_id, {prices, trade_prices}, security_currency) do
    override_price(security_id, prices, security_currency) ||
      quote_price(security_id, security_currency) ||
      trade_price(security_id, trade_prices) ||
      {nil, security_currency, nil}
  end

  defp override_price(security_id, prices, security_currency) do
    case Map.get(prices, security_id) do
      %Decimal{} = price -> {price, security_currency, :quote}
      _ -> nil
    end
  end

  # The latest close in the current display basis (ADR-0028 §2): a stale raw
  # close from before a split's effective date is divided by the cumulative
  # later ratio, so it never prices the post-split quantity at the unsplit
  # value. The trade fallback below is already basis-adjusted by
  # `Ledger.latest_trade_prices`.
  defp quote_price(security_id, security_currency) do
    case Quotes.adjusted_latest(security_id) do
      %{close: %Decimal{} = close} -> {close, security_currency, :quote}
      _ -> nil
    end
  end

  defp trade_price(security_id, trade_prices) do
    case Map.get(trade_prices, security_id) do
      %{price: %Decimal{} = price, currency: currency} -> {price, currency, :trade}
      _ -> nil
    end
  end

  defp base_currency_for(portfolio_id) do
    case Portfolios.get_portfolio(portfolio_id) do
      %{base_currency_code: code} -> code
      _ -> nil
    end
  end

  defp total_value(positions) do
    positions
    |> Enum.filter(& &1.valued)
    |> Enum.reduce(@zero, fn position, acc -> Decimal.add(acc, position.market_value) end)
  end

  defp put_weight(%{valued: false} = position, _total), do: position

  defp put_weight(%{valued: true} = position, total) do
    weight =
      if Decimal.equal?(total, @zero) do
        @zero
      else
        Decimal.div(position.market_value, total)
      end

    %{position | weight: weight}
  end
end
