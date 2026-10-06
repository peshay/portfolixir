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

  import Ecto.Query

  alias Portfolixir.Actor
  alias Portfolixir.Buckets.Bucket
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Journal
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Repo

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
      Portfolios.create_portfolio(Actor.owner_ui(), %{name: name, base_currency_code: currency})

    %{cash: cash, depot: depot} = add_depot(portfolio, opts)

    %{portfolio: portfolio, cash: cash, depot: depot}
  end

  @doc """
  Creates a cash account plus a securities depot for `portfolio`.

  Returns `%{cash: cash, depot: depot}`. Useful for tests that need a second
  depot (e.g. security transfers between own depots).

  Options: `:currency` (default `"EUR"`), `:cash_currency` (default:
  `:currency`), `:cash_name` (default `"Local Cash"`), `:depot_name`
  (default `"Main Depot"`), `:liquidity_role` (default `"free_cash"`).
  """
  def add_depot(portfolio, opts \\ []) do
    currency = Keyword.get(opts, :currency, "EUR")
    cash_currency = Keyword.get(opts, :cash_currency, currency)
    cash_name = Keyword.get(opts, :cash_name, "Local Cash")
    depot_name = Keyword.get(opts, :depot_name, "Main Depot")
    liquidity_role = Keyword.get(opts, :liquidity_role, "free_cash")

    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: cash_name,
        currency_code: cash_currency,
        liquidity_role: liquidity_role
      })

    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
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

    {:ok, security} = Catalog.create_security(Actor.owner_ui(), attrs)
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
      Ledger.create_transaction(Actor.owner_ui(), %{
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
  Records a sell of `security` from `world`'s depot, crediting its cash account.

  Mirrors `buy!/3`: `security` may be a struct, a struct id or the string id
  returned over the API. Options match `buy!/3` (`:quantity` default `"1"`,
  `:price` default `"100"`, `:date` default `~D[2026-01-02]`, `:fees`/`:taxes`
  default `"0"`, `:currency` default `"EUR"`).
  """
  def sell!(%{portfolio: portfolio, depot: depot, cash: cash}, security, opts \\ []) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        securities_account_id: depot.id,
        cash_account_id: cash.id,
        security_id: security_id(security),
        type: "sell",
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
  Records a cross-currency trade (ADR-0015): `security`, priced in its own
  currency, bought into `world`'s depot or sold from it, settled through
  `world`'s cash account in another currency. The cash agrees with the
  settlement (#395), so `:gross` is `settled + fees + taxes` on a buy and
  `settled − fees − taxes` on a sell, all in the account's currency.

  Options (Decimal strings): `:type` (default `"buy"`), `:quantity`,
  `:price` (in the security's currency), `:settled` (the trade amount in the
  account's currency, before fees and taxes), `:gross` (the cash the account
  moved), `:date`, and `:fees` and `:taxes` (default `"0"`, in the account's
  currency, the cash leg they are part of).
  """
  def cross_trade!(%{portfolio: portfolio, depot: depot, cash: cash}, security, opts) do
    quantity = Decimal.new(Keyword.fetch!(opts, :quantity))
    price = Decimal.new(Keyword.fetch!(opts, :price))
    settled = Decimal.new(Keyword.fetch!(opts, :settled))
    amount = Decimal.mult(quantity, price)

    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        securities_account_id: depot.id,
        cash_account_id: cash.id,
        security_id: security.id,
        type: Keyword.get(opts, :type, "buy"),
        date: Keyword.fetch!(opts, :date),
        quantity: quantity,
        price: price,
        fees: Keyword.get(opts, :fees, "0"),
        taxes: Keyword.get(opts, :taxes, "0"),
        currency_code: security.currency_code,
        security_amount: amount,
        settlement_amount: settled,
        settlement_fx_rate: Decimal.div(settled, amount),
        gross_amount: Keyword.fetch!(opts, :gross)
      })

    tx
  end

  @doc """
  Records a deposit of `amount` into `world`'s cash account on `date`.
  """
  def deposit!(%{portfolio: portfolio, cash: cash}, amount, date, opts \\ []) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
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

  @doc """
  Resolves a security struct, struct id or string id to its id, for tests that
  book non-trade kinds (e.g. dividends) against a security directly.
  """
  def security_id_for(security), do: security_id(security)

  defp security_id(%{id: id}), do: id
  defp security_id(id), do: id

  @doc """
  Creates a bucket under an id in the printable ASCII range: the lowest of
  `?A..?Z` no bucket the test can see holds yet.

  `inspect/1` prints a list of such ids as a charlist (`[65, 66]` reads
  `~c"AB"`), so a sentence that names buckets is pinned with them (#978). The
  row is written as `Portfolixir.Buckets.create_bucket/2` writes one, with its
  journal entry under the owner. Create these after every bucket the test
  makes through the id sequence, which could otherwise hand the same id out
  later in the same test.

  Async tests run in separate sandbox transactions and cannot see each
  other's uncommitted buckets, so two of them could pick the same free id and
  the second insert would wait on the first test's row until that test ends
  (#947's hazard). Each candidate id is therefore claimed with a transaction
  advisory lock that does not wait: an id another running test claimed is
  skipped, and the claim ends with the test's sandbox transaction.
  """
  def printable_bucket!(attrs) when is_map(attrs) do
    printable = Enum.to_list(?A..?Z)
    taken = Repo.all(from(b in Bucket, where: b.id in ^printable, select: b.id))

    id =
      Enum.find(printable, &(&1 not in taken and claim_printable_id?(&1))) ||
        raise "no printable bucket id is free"

    {:ok, %{bucket: bucket}} =
      Ecto.Multi.new()
      |> Ecto.Multi.insert(
        :bucket,
        %Bucket{} |> Bucket.changeset(attrs) |> Ecto.Changeset.put_change(:id, id)
      )
      |> Journal.record(Actor.owner_ui(),
        resource_type: "bucket",
        operation: :create,
        source: :bucket
      )
      |> Repo.transaction()

    bucket
  end

  # The advisory key pairs a namespace (the issue that introduced printable
  # ids) with the candidate id; the two-key form never collides with the
  # one-key locks the application takes.
  @printable_bucket_lock 978

  defp claim_printable_id?(id) do
    %{rows: [[claimed?]]} =
      Repo.query!("SELECT pg_try_advisory_xact_lock($1, $2)", [@printable_bucket_lock, id])

    claimed?
  end
end
