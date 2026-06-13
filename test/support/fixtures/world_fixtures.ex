defmodule Portfolixir.WorldFixtures do
  @moduledoc """
  Shared "world" fixtures for context, controller and LiveView tests.

  Most ledger/valuation/allocation/performance tests start from the same small
  world (a portfolio with a cash account and a securities depot) and book the
  same handful of transactions and quotes against it. Each module used to
  inline its own `setup_world`/`buy!`/`deposit!`/`quote!` copies, which is
  legitimate-but-repetitive test setup that SonarCloud's copy-paste detector
  flags on feature PRs (issue #368).

  These helpers consolidate that arrange step into one place while keeping the
  call sites intention-revealing: tests still create exactly the world they
  need and still assert everything they asserted before. Every helper takes
  keyword options so a module can tune names, currencies or dates without
  forking the builder.
  """

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  @doc """
  Builds a portfolio with one cash account and one securities depot.

  Returns a context map with `:portfolio`, `:cash` and `:depot`.

  Options:

    * `:name` - portfolio name (default `"Local Portfolio"`)
    * `:currency` - base currency code (default `"EUR"`)
    * `:cash_currency` - cash account currency (default: `:currency`), for the
      few tests that book a portfolio whose cash account trades in another
      currency than the portfolio base
    * `:cash_name` - cash account name (default `"Local Cash"`)
    * `:depot_name` - securities account name (default `"Main Depot"`)
  """
  def base_world(opts \\ []) do
    name = Keyword.get(opts, :name, "Local Portfolio")
    currency = Keyword.get(opts, :currency, "EUR")

    {:ok, portfolio} =
      Portfolios.create_portfolio(%{name: name, base_currency_code: currency})

    %{cash: cash, depot: depot} = add_depot(portfolio, opts)

    %{portfolio: portfolio, cash: cash, depot: depot}
  end

  @doc """
  Creates a cash account plus a securities depot for `portfolio`.

  Returns `%{cash: cash, depot: depot}`. Useful for tests that need a second
  depot (e.g. security transfers between own depots).

  Options: `:currency` (default `"EUR"`), `:cash_currency` (default:
  `:currency`), `:cash_name` (default `"Local Cash"`), `:depot_name`
  (default `"Main Depot"`).
  """
  def add_depot(portfolio, opts \\ []) do
    currency = Keyword.get(opts, :currency, "EUR")
    cash_currency = Keyword.get(opts, :cash_currency, currency)
    cash_name = Keyword.get(opts, :cash_name, "Local Cash")
    depot_name = Keyword.get(opts, :depot_name, "Main Depot")

    {:ok, cash} =
      Portfolios.create_cash_account(%{
        portfolio_id: portfolio.id,
        name: cash_name,
        currency_code: cash_currency
      })

    {:ok, depot} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: depot_name
      })

    %{cash: cash, depot: depot}
  end

  @doc """
  Creates a security and returns the struct.

  Options:

    * `:name` (default `"World ETF"`)
    * `:ticker` (default `"WLD"`; pass `nil` to omit the ticker entirely)
    * `:currency` (default `"EUR"`)
    * `:asset_class` (default `"etf"`)
    * `:isin` (optional)
  """
  def create_security!(opts \\ []) do
    attrs =
      %{
        name: Keyword.get(opts, :name, "World ETF"),
        currency_code: Keyword.get(opts, :currency, "EUR"),
        asset_class: Keyword.get(opts, :asset_class, "etf")
      }
      |> maybe_put(:ticker_symbol, Keyword.get(opts, :ticker, "WLD"))
      |> maybe_put(:isin, Keyword.get(opts, :isin))

    {:ok, security} = Catalog.create_security(attrs)
    security
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @doc """
  Records a buy of `security` into `world`'s depot, paid from its cash account.

  `security` may be a struct, a struct id or the string id returned over the
  API. Options:

    * `:quantity` (default `"1"`)
    * `:price` (default `"100"`)
    * `:date` (default `~D[2026-01-02]`)
    * `:fees` (default `"0"`)
    * `:taxes` (default `"0"`)
    * `:currency` (default `"EUR"`)
  """
  def buy!(%{portfolio: portfolio, depot: depot, cash: cash}, security, opts \\ []) do
    {:ok, tx} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: depot.id,
        cash_account_id: cash.id,
        security_id: security_id(security),
        type: "buy",
        date: Keyword.get(opts, :date, ~D[2026-01-02]),
        quantity: Keyword.get(opts, :quantity, "1"),
        price: Keyword.get(opts, :price, "100"),
        fees: Keyword.get(opts, :fees, "0"),
        taxes: Keyword.get(opts, :taxes, "0"),
        currency_code: Keyword.get(opts, :currency, "EUR")
      })

    tx
  end

  @doc """
  Records a deposit of `amount` into `world`'s cash account on `date`.
  """
  def deposit!(%{portfolio: portfolio, cash: cash}, amount, date, opts \\ []) do
    {:ok, tx} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        type: "deposit",
        date: date,
        gross_amount: amount,
        currency_code: Keyword.get(opts, :currency, "EUR")
      })

    tx
  end

  @doc """
  Stores manual `close` quotes for `security` on the given `date`, or for a
  list of `{date, close}` pairs.
  """
  def put_quote!(security, date, close) do
    {:ok, quotes} =
      Quotes.upsert_many(security_id(security), [%{date: date, close: close, source: "manual"}])

    quotes
  end

  def put_quotes!(security, points) when is_list(points) do
    rows = Enum.map(points, fn {date, close} -> %{date: date, close: close, source: "manual"} end)
    {:ok, quotes} = Quotes.upsert_many(security_id(security), rows)
    quotes
  end

  defp security_id(%{id: id}), do: id
  defp security_id(id), do: id
end
