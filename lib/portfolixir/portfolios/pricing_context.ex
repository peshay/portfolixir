defmodule Portfolixir.Portfolios.PricingContext do
  @moduledoc """
  The market data one read needs, loaded once and threaded through it
  (ADR-0035).

  A dashboard mount used to price the same holdings six times — once view-wide
  and once per portfolio — and each of those passes asked the database for the
  security, the latest quote and the exchange rate **per row**. This struct is
  the answer to those questions, loaded in a handful of batched queries at the
  edge of the read and handed to every valuation and allocation inside it.

  It is **plain data with the lifetime of one read**: not a process, not ETS,
  never persisted, never shared between requests. ADR-0004 is untouched and no
  invalidation rule exists — nothing is remembered, so nothing can go stale.

  ## Coverage, and why it is tracked

  A preloaded map answers "no quote for this security" with an absent key, and
  so does a map that simply never loaded that security. Confusing the two would
  turn a priced position into an unvalued one (ADR-0035 hard requirement 4), so
  the struct records what it actually asked for:

    * `security_ids` – the securities whose `securities` and `quotes` entries
      are authoritative; anything outside falls back to the per-row lookup.
    * `currencies` – the currencies whose hub rate was requested; an absent
      entry inside this set means "no stored rate path", exactly as
      `Portfolixir.Fx.rate/3` reports it.

  `trade_prices` needs no coverage set: the underlying read
  (`Portfolixir.Ledger.latest_trade_prices/0`) is global and complete by
  construction, which is also what makes the #406 fallback consistent across
  surfaces.

  `positions`, `cash_accounts` and `cash_balances` are optional: they are
  carried when several consumers of one read need them (the view valuation and
  the per-portfolio drift loop both walk the same portfolios), and are `nil`
  otherwise.
  """

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  @hub "EUR"

  defstruct securities: %{},
            security_ids: MapSet.new(),
            quotes: %{},
            trade_prices: %{},
            hub_rates: %{},
            currencies: MapSet.new(),
            positions: nil,
            cash_accounts: nil,
            cash_balances: nil,
            cash_scope: nil

  @type t :: %__MODULE__{}

  @doc """
  The context carried in `opts[:pricing_context]`, or the one `builder` makes.

  This is the whole option idiom: a caller that supplies nothing gets a context
  built for that call alone, which is today's behaviour.
  """
  def fetch(opts, builder) when is_list(opts) and is_function(builder, 0) do
    case Keyword.get(opts, :pricing_context) do
      %__MODULE__{} = context -> context
      _none -> builder.()
    end
  end

  @doc """
  A context for the securities in `security_ids`, plus `extra_currencies`.

  Used by the reads that resolve prices without walking portfolios
  (`Valuation.holdings_by_security/1`, `Valuation.security_status/3`).
  """
  def for_securities(security_ids, extra_currencies \\ []) do
    build_pricing(security_ids, extra_currencies)
  end

  @doc """
  A context for one portfolio's read: its positions, cash accounts and cash
  balances alongside the market data for the securities it holds.
  """
  def for_portfolio(portfolio_id, base_currency) when is_integer(portfolio_id) do
    positions = %{portfolio_id => Ledger.positions_for_portfolio(portfolio_id)}
    cash_accounts = Portfolios.list_cash_accounts_for_portfolio(portfolio_id)
    cash_balances = Ledger.cash_balances(portfolio_id: portfolio_id)

    positions
    |> security_ids_of()
    |> build_pricing(currencies_of(cash_accounts, base_currency))
    |> struct!(
      positions: positions,
      cash_accounts: cash_accounts,
      cash_balances: cash_balances,
      cash_scope: portfolio_id
    )
  end

  @doc """
  A context for a read that spans every portfolio — the dashboard's async block
  and the Wealth page, where a view-wide valuation and per-portfolio
  allocations price the same holdings.

  Every portfolio's own base currency is covered too, because the drift loop
  values each portfolio in its own base while the wealth card uses
  `base_currency`.
  """
  def for_all_portfolios(base_currency \\ @hub) do
    portfolios = Portfolios.list_portfolios()

    positions =
      Map.new(portfolios, fn portfolio ->
        {portfolio.id, Ledger.positions_for_portfolio(portfolio.id)}
      end)

    cash_accounts = Portfolios.list_cash_accounts()
    cash_balances = Ledger.cash_balances()
    bases = [base_currency | Enum.map(portfolios, & &1.base_currency_code)]

    positions
    |> security_ids_of()
    |> build_pricing(currencies_of(cash_accounts, bases))
    |> struct!(
      positions: positions,
      cash_accounts: cash_accounts,
      cash_balances: cash_balances,
      cash_scope: :all
    )
  end

  # The market-data half every builder shares: securities and their latest
  # adjusted quotes in two batched queries, the global trade-price fallback in
  # one, and one hub-rate query for every currency that can appear in this read.
  defp build_pricing(security_ids, extra_currencies) do
    security_ids = security_ids |> Enum.uniq() |> Enum.sort()
    securities = Catalog.get_securities_by_ids(security_ids)
    quotes = Quotes.adjusted_latest_by_security_ids(security_ids)
    trade_prices = Ledger.latest_trade_prices()

    currencies =
      [@hub]
      |> Kernel.++(List.wrap(extra_currencies))
      |> Kernel.++(Enum.map(Map.values(securities), & &1.currency_code))
      |> Kernel.++(Enum.map(Map.values(trade_prices), & &1.currency))
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()

    %__MODULE__{
      securities: securities,
      security_ids: MapSet.new(security_ids),
      quotes: quotes,
      trade_prices: trade_prices,
      hub_rates: Fx.hub_rates(currencies),
      currencies: MapSet.new(currencies)
    }
  end

  defp security_ids_of(positions) do
    for {_portfolio_id, held} <- positions,
        {{_securities_account_id, security_id}, _quantity} <- held,
        uniq: true do
      security_id
    end
  end

  defp currencies_of(cash_accounts, bases) do
    Enum.map(cash_accounts, & &1.currency_code) ++ List.wrap(bases)
  end

  @doc """
  The security record for `security_id`, or `:miss` when this context did not
  load it (the caller then falls back to `Catalog.get_security/1`).

  `{:ok, nil}` is a real answer: the id is covered and no such security exists.
  """
  def security(%__MODULE__{} = context, security_id) do
    if MapSet.member?(context.security_ids, security_id) do
      {:ok, Map.get(context.securities, security_id)}
    else
      :miss
    end
  end

  @doc """
  The latest adjusted quote row for `security_id`, or `:miss` when this context
  did not load it. `{:ok, nil}` means "covered, and there is no quote".
  """
  def quote_row(%__MODULE__{} = context, security_id) do
    if MapSet.member?(context.security_ids, security_id) do
      {:ok, Map.get(context.quotes, security_id)}
    else
      :miss
    end
  end

  @doc "The global latest own trade price per security (always complete)."
  def trade_prices(%__MODULE__{} = context), do: context.trade_prices

  @doc """
  `Fx.convert/3` for this read: resolved from the preloaded hub rates when both
  currencies are covered, otherwise delegated to the query path unchanged.
  """
  def convert(%__MODULE__{} = context, %Decimal{} = amount, from, to) do
    if covers_currency?(context, from) and covers_currency?(context, to) do
      Fx.convert_with_hub_rates(amount, from, to, context.hub_rates)
    else
      Fx.convert(amount, from, to)
    end
  end

  @doc "`Fx.rate/2` for this read, with the same coverage rule as `convert/4`."
  def rate(%__MODULE__{} = context, from, to) do
    if covers_currency?(context, from) and covers_currency?(context, to) do
      Fx.rate_from_hub_rates(from, to, context.hub_rates)
    else
      Fx.rate(from, to)
    end
  end

  defp covers_currency?(%__MODULE__{} = context, currency),
    do: is_binary(currency) and MapSet.member?(context.currencies, currency)

  @doc """
  The held quantities of `portfolio_id`, or `:miss` when this context does not
  carry them.
  """
  def positions(%__MODULE__{positions: nil}, _portfolio_id), do: :miss

  def positions(%__MODULE__{} = context, portfolio_id) do
    case Map.fetch(context.positions, portfolio_id) do
      {:ok, held} -> {:ok, held}
      :error -> :miss
    end
  end

  @doc """
  The cash accounts of `portfolio_id` (or every one of them with `:all`), or
  `:miss`. A portfolio's accounts are filtered out of the instance-wide list,
  which preserves the `(name, id)` ordering the per-portfolio query returns.
  """
  def cash_accounts(%__MODULE__{cash_accounts: nil}, _scope), do: :miss

  def cash_accounts(%__MODULE__{cash_scope: :all} = context, :all),
    do: {:ok, context.cash_accounts}

  def cash_accounts(%__MODULE__{cash_scope: :all} = context, portfolio_id),
    do: {:ok, Enum.filter(context.cash_accounts, &(&1.portfolio_id == portfolio_id))}

  def cash_accounts(%__MODULE__{cash_scope: scope} = context, portfolio_id)
      when scope == portfolio_id,
      do: {:ok, context.cash_accounts}

  def cash_accounts(%__MODULE__{}, _scope), do: :miss

  @doc """
  The cash balances covering `portfolio_id` (or every account with `:all`), or
  `:miss`. An instance-wide balance map covers every portfolio: balances are
  per cash account and an account belongs to exactly one portfolio.
  """
  def cash_balances(%__MODULE__{cash_balances: nil}, _scope), do: :miss

  def cash_balances(%__MODULE__{cash_scope: :all} = context, _scope),
    do: {:ok, context.cash_balances}

  def cash_balances(%__MODULE__{cash_scope: scope} = context, portfolio_id)
      when scope == portfolio_id,
      do: {:ok, context.cash_balances}

  def cash_balances(%__MODULE__{}, _scope), do: :miss
end
