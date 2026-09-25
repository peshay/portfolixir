defmodule Portfolixir.Catalog.BoundedUpsertsTest do
  # E25 S3, F28 (#888): a provider's whole daily history — decades of closes,
  # or the ECB series across every currency — is written in chunks below the
  # database's bind-parameter limit, inside one transaction, and a failure to
  # persist one security's quotes is that security's error, not the end of the
  # whole sync run.
  use PortfolixirWeb.ConnCase, async: true

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quote
  alias Portfolixir.Catalog.QuoteSync
  alias Portfolixir.Catalog.QuoteSync.Fake
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Clock
  alias Portfolixir.Fx
  alias Portfolixir.Fx.ExchangeRate
  alias Portfolixir.Repo

  import Ecto.Query

  # More rows than one INSERT can bind for either table (65,535 parameters;
  # six per quote row, seven per rate row).
  @long_history 12_000

  defp security!(name, ticker) do
    {:ok, security} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: name,
        currency_code: "USD",
        provider: "coingecko",
        ticker_symbol: ticker,
        asset_class: "crypto"
      })

    security
  end

  defp history(count, fun) do
    today = Clock.today()
    for back <- 1..count, do: fun.(Date.add(today, -back), back)
  end

  # User story:
  # As an operator whose provider serves decades of daily closes for one
  # security, and the full ECB series for the backfill,
  # I want the whole history stored in one sync,
  # so that a long history is not the one thing the sync cannot store.
  #
  # Acceptance criteria:
  # - A quote history above one insert's bind limit upserts fully, on the
  #   manual and on the sync path, and reports the full count.
  # - An FX history above the limit upserts fully and reports the full count.
  test "histories above the bind limit upsert fully" do
    security = security!("Synthetic Long History", "SYNL")

    rows =
      history(@long_history, fn date, back ->
        %{date: date, close: "#{back}.5", source: "auto"}
      end)

    assert {:ok, @long_history, 0} = Quotes.upsert_many(security.id, rows, protect_manual: true)

    assert Repo.aggregate(from(q in Quote, where: q.security_id == ^security.id), :count) ==
             @long_history

    assert {:ok, @long_history} = Quotes.upsert_many(security.id, rows)

    rates =
      history(div(@long_history, 2), fn date, back ->
        [
          %{
            base_currency: "EUR",
            quote_currency: "USD",
            date: date,
            rate: "1.#{back}",
            source: "ecb"
          },
          %{
            base_currency: "EUR",
            quote_currency: "GBP",
            date: date,
            rate: "0.#{back}",
            source: "ecb"
          }
        ]
      end)
      |> List.flatten()

    assert {:ok, @long_history} = Fx.upsert_many(rates)
    assert Repo.aggregate(ExchangeRate, :count) == @long_history
  end

  # User story:
  # As an operator syncing every security on a schedule,
  # I want one security whose quotes cannot be stored reported as that
  # security's error,
  # so that the rest of the catalog is still synced in the same run.
  #
  # Acceptance criteria:
  # - When persisting one security's quotes fails in the database, that
  #   security's result is an error with a fixed reason, and every other
  #   security's quotes are stored.
  test "one failing security does not stop the rest" do
    failing = security!("Synthetic Overflow", "SYNO")
    healthy = security!("Synthetic Healthy", "SYNH")
    today = Clock.today()

    # Plausible (positive, not in the future), but wider than the column holds.
    Fake.put_response(
      failing.id,
      {:ok, [%{date: Date.add(today, -1), close: Decimal.new("1E+15")}]}
    )

    Fake.put_response(healthy.id, {:ok, [%{date: Date.add(today, -1), close: Decimal.new("42")}]})

    assert {:ok, %{ok: 1, error: 1, results: results}} =
             QuoteSync.sync_all(adapter_for: %{"coingecko" => Fake})

    assert %{status: :error, reason: :persist_failed} =
             Enum.find(results, &(&1.security_id == failing.id))

    assert %{status: :ok, upserted: 1} = Enum.find(results, &(&1.security_id == healthy.id))
    assert %Quote{} = Quotes.latest(healthy.id)
    assert Quotes.latest(failing.id) == nil
  end

  # User story:
  # As the operator or the agent running the one-shot FX backfill,
  # I want a backfill whose rows cannot be stored answered as a failed
  # upstream operation,
  # so that the API names it the way it names an unreachable provider,
  # instead of failing with an internal error.
  #
  # Acceptance criteria:
  # - A history whose persistence fails in the database answers 502 with the
  #   fixed detail, and stores nothing.
  test "a backfill that cannot be stored answers 502", %{conn: conn} do
    Portfolixir.Fx.RateSync.Fake.put_history_response(
      {:ok,
       [
         %{
           base_currency: "EUR",
           quote_currency: "USD",
           date: Date.add(Clock.today(), -2),
           rate: "1.1",
           source: "ecb"
         },
         %{
           base_currency: "EUR",
           quote_currency: "GBP",
           date: Date.add(Clock.today(), -2),
           rate: "1E+20",
           source: "ecb"
         }
       ]}
    )

    conn =
      conn
      |> put_req_header("authorization", "Bearer test-api-token")
      |> post("/api/v1/exchange_rates/sync?scope=history")

    assert %{"errors" => %{"detail" => _}} = json_response(conn, 502)
    assert Repo.aggregate(ExchangeRate, :count) == 0
  end
end
