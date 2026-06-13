defmodule Portfolixir.AllocationExcludeFixtures do
  @moduledoc """
  Shared fixtures for the allocation-exclude flag tests.

  Builds the small world (portfolio, cash account, securities depot and a
  two-category "Strategy" classification) that the context, controller and
  LiveView tests around `excluded_from_allocation_targets` all rely on, so the
  setup is defined once instead of inlined per test module.
  """

  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Classifications
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  @doc """
  Creates a EUR portfolio with a cash account, a securities depot and a
  "Strategy" classification holding "Equities" and "Crypto" categories.

  Returns a context map with `:portfolio`, `:cash`, `:depot`,
  `:classification`, `:equities` and `:crypto`.
  """
  def exclude_world do
    {:ok, portfolio} =
      Portfolios.create_portfolio(%{name: "Local Portfolio", base_currency_code: "EUR"})

    {:ok, cash} =
      Portfolios.create_cash_account(%{
        portfolio_id: portfolio.id,
        name: "Local Cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(%{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Main Depot"
      })

    {:ok, classification} = Classifications.create_classification(%{name: "Strategy"})

    {:ok, equities} =
      Classifications.create_category(%{classification_id: classification.id, name: "Equities"})

    {:ok, crypto} =
      Classifications.create_category(%{classification_id: classification.id, name: "Crypto"})

    %{
      portfolio: portfolio,
      cash: cash,
      depot: depot,
      classification: classification,
      equities: equities,
      crypto: crypto
    }
  end

  @doc """
  Records a buy of `security_id` into the world's depot, paid from its cash
  account, for `quantity` shares at `price` EUR with no fees or taxes.

  `security_id` may be a struct id or the string id returned over the API.
  `date` defaults to `~D[2026-01-02]`.
  """
  def buy!(
        %{portfolio: portfolio, depot: depot, cash: cash},
        security_id,
        quantity,
        price,
        date \\ ~D[2026-01-02]
      ) do
    {:ok, tx} =
      Ledger.create_transaction(%{
        portfolio_id: portfolio.id,
        securities_account_id: depot.id,
        cash_account_id: cash.id,
        security_id: security_id,
        type: "buy",
        date: date,
        quantity: quantity,
        price: price,
        fees: "0",
        taxes: "0",
        currency_code: "EUR"
      })

    tx
  end

  @doc """
  Stores a single manual `close` quote for `security_id` on `date`
  (default: today).
  """
  def manual_quote!(security_id, close, date \\ Date.utc_today()) do
    {:ok, quotes} =
      Quotes.upsert_many(security_id, [%{date: date, close: close, source: "manual"}])

    quotes
  end
end
