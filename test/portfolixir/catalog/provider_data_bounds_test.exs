defmodule Portfolixir.Catalog.ProviderDataBoundsTest do
  # E25 S3, F26 (#888): provider quote and FX rows are bounded before they are
  # stored — a date no later than today (with one day of zone slack, see
  # Portfolixir.Catalog.MarketDataBounds) and a positive value — so one
  # implausible row can neither become the valuation price nor hide a stale
  # one. Adapters drop such points instead of failing the batch, and the
  # latest-quote and latest-rate reads never serve a row dated past the bound.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.DataQuality
  alias Portfolixir.Catalog.MarketDataBounds
  alias Portfolixir.Catalog.Quote
  alias Portfolixir.Catalog.QuoteSync
  alias Portfolixir.Catalog.QuoteSync.Yahoo
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Clock
  alias Portfolixir.Fx
  alias Portfolixir.Fx.ExchangeRate
  alias Portfolixir.Fx.RateSync
  alias Portfolixir.Fx.RateSync.Ecb
  alias Portfolixir.Repo

  defp security!(attrs \\ %{}) do
    {:ok, security} =
      Catalog.create_security(
        Portfolixir.Actor.owner_ui(),
        Map.merge(
          %{
            name: "Synthetic Provider Co",
            currency_code: "EUR",
            provider: "portfolio_performance",
            ticker_symbol: "SYNP",
            asset_class: "equity"
          },
          attrs
        )
      )

    security
  end

  defp unix(%Date{} = date),
    do: date |> DateTime.new!(~T[14:30:00], "Etc/UTC") |> DateTime.to_unix()

  defp yahoo_stub(points) do
    body = %{
      "chart" => %{
        "result" => [
          %{
            "timestamp" => Enum.map(points, &unix(elem(&1, 0))),
            "indicators" => %{"quote" => [%{"close" => Enum.map(points, &elem(&1, 1))}]}
          }
        ]
      }
    }

    [
      plug: fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(body))
      end
    ]
  end

  defp ecb_stub(xml) do
    [
      plug: fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/xml")
        |> Plug.Conn.send_resp(200, xml)
      end
    ]
  end

  defp stored_quote_dates(security_id) do
    Quote
    |> where([q], q.security_id == ^security_id)
    |> order_by([q], asc: q.date)
    |> select([q], q.date)
    |> Repo.all()
  end

  # User story:
  # As an operator whose valuation prices every position from the latest
  # provider close,
  # I want a provider point dated in the future or carrying a zero or negative
  # close dropped at the sync,
  # so that one implausible row can neither become my valuation price nor make
  # a stale security look fresh — and the rest of the batch still lands.
  #
  # Acceptance criteria:
  # - Stubbed Yahoo points dated past the bound, or with a zero or negative
  #   close, store nothing; the plausible points of the same batch are stored.
  # - The sync reports the security as ok, not as a failed batch.
  test "a quote sync drops implausible provider points and keeps the batch" do
    security = security!()
    today = Clock.today()
    good_1 = Date.add(today, -10)
    good_2 = Date.add(today, -3)

    stub =
      yahoo_stub([
        {good_1, 101.5},
        {Date.add(today, -9), 0},
        {Date.add(today, -8), -4.25},
        {good_2, 103.0},
        {Date.add(today, 30), 999.0},
        {Date.add(today, 4000), 1.0e9}
      ])

    result =
      QuoteSync.sync_security(security,
        adapter_for: %{"portfolio_performance" => Yahoo},
        req: stub
      )

    assert %{status: :ok, upserted: 2} = result
    assert stored_quote_dates(security.id) == [good_1, good_2]
  end

  test "the sync writer drops what any adapter returns out of bounds" do
    security = security!(%{provider: "coingecko", ticker_symbol: "SYNC", currency_code: "USD"})
    today = Clock.today()

    Portfolixir.Catalog.QuoteSync.Fake.put_response(
      security.id,
      {:ok,
       [
         %{date: Date.add(today, -2), close: Decimal.new("12.5")},
         %{date: Date.add(today, 9), close: Decimal.new("13")},
         %{date: Date.add(today, -1), close: Decimal.new("0")}
       ]}
    )

    result =
      QuoteSync.sync_security(security,
        adapter_for: %{"coingecko" => Portfolixir.Catalog.QuoteSync.Fake}
      )

    assert %{status: :ok, upserted: 1} = result
    assert stored_quote_dates(security.id) == [Date.add(today, -2)]
  end

  # User story:
  # As an operator whose multi-currency figures convert through the ECB rates,
  # I want a published rate dated in the future or with a zero value dropped,
  # so that no implausible rate converts my positions.
  #
  # Acceptance criteria:
  # - The daily feed dated past the bound stores nothing.
  # - The history feed's implausible cubes store nothing; its plausible ones
  #   are stored.
  test "an FX sync drops implausible provider rates" do
    today = Clock.today()
    future = today |> Date.add(20) |> Date.to_iso8601()
    past = today |> Date.add(-5) |> Date.to_iso8601()

    daily =
      ~s(<Cube><Cube time="#{future}"><Cube currency="USD" rate="1.1"/></Cube></Cube>)

    assert {:ok, %{upserted: 0}} = RateSync.sync(provider: Ecb, req: ecb_stub(daily))

    history = """
    <Cube>
      <Cube time="#{future}"><Cube currency="USD" rate="1.2"/></Cube>
      <Cube time="#{past}"><Cube currency="USD" rate="1.1"/><Cube currency="GBP" rate="0.000"/></Cube>
    </Cube>
    """

    assert {:ok, %{upserted: 1}} = RateSync.backfill(provider: Ecb, req: ecb_stub(history))

    assert [%ExchangeRate{quote_currency: "USD", rate: rate}] = Repo.all(ExchangeRate)
    assert Decimal.equal?(rate, Decimal.new("1.1"))
  end

  # User story:
  # As an operator and as the agent writing quotes and rates by hand,
  # I want the same plausibility bounds on every writer,
  # so that no path stores what the sync refuses.
  #
  # Acceptance criteria:
  # - The Quote and ExchangeRate changesets refuse a date past the bound and a
  #   value that is not positive; today and the slack day are accepted.
  test "the Quote and ExchangeRate changesets bound date and value" do
    bound = MarketDataBounds.latest_date()
    assert bound == Date.add(Clock.today(), 1)

    quote = fn attrs ->
      Quote.changeset(
        %Quote{},
        Map.merge(%{security_id: 1, source: "manual", close: "10", date: Clock.today()}, attrs)
      )
    end

    assert quote.(%{}).valid?
    assert quote.(%{date: bound}).valid?
    assert %{date: [_]} = errors_on(quote.(%{date: Date.add(bound, 1)}))
    assert %{close: [_]} = errors_on(quote.(%{close: "0"}))
    assert %{close: [_]} = errors_on(quote.(%{close: "-1.5"}))

    rate = fn attrs ->
      ExchangeRate.changeset(
        %ExchangeRate{},
        Map.merge(
          %{base_currency: "EUR", quote_currency: "USD", rate: "1.1", date: Clock.today()},
          Map.put(attrs, :source, "manual")
        )
      )
    end

    assert rate.(%{}).valid?
    assert rate.(%{date: bound}).valid?
    assert %{date: [_]} = errors_on(rate.(%{date: Date.add(bound, 1)}))
    assert %{rate: [_]} = errors_on(rate.(%{rate: "0"}))
  end

  # User story:
  # As an operator upgrading an instance that may already hold a row dated in
  # the future,
  # I want the latest-quote and latest-rate reads capped at the bound,
  # so that such a row neither prices my positions nor hides a stale quote.
  #
  # Acceptance criteria:
  # - A stored quote dated past the bound is not the latest quote, in the
  #   single, bulk, last-two and catalog-metrics reads.
  # - A security whose newest plausible quote is stale stays in stale_quote.
  # - A stored rate dated past the bound is not the latest rate.
  test "the latest reads never serve a row dated past the bound" do
    security = security!()
    today = Clock.today()
    old = Date.add(today, -30)
    older = Date.add(today, -31)
    future = Date.add(today, 60)
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    # Rows stored before the bound existed, written past the changeset.
    Repo.insert_all(
      Quote,
      [
        %{security_id: security.id, date: older, close: Decimal.new("9"), source: "auto"},
        %{security_id: security.id, date: old, close: Decimal.new("10"), source: "auto"},
        %{security_id: security.id, date: future, close: Decimal.new("5000"), source: "auto"}
      ]
      |> Enum.map(&Map.merge(&1, %{inserted_at: now, updated_at: now}))
    )

    assert %Quote{date: ^old} = Quotes.latest(security.id)
    assert %{date: ^old} = Quotes.adjusted_latest(security.id)
    assert %{} = latest = Quotes.latest_by_security_ids([security.id])
    assert %Quote{date: ^old} = latest[security.id]
    assert [%Quote{date: ^old}, %Quote{date: ^older}] = Quotes.latest_two(security.id)

    [%{metrics: metrics}] = Quotes.attach_metrics([security])
    assert metrics.latest_price_date == old
    assert Decimal.equal?(metrics.latest_price, Decimal.new("10"))

    assert security.id in Enum.map(DataQuality.list("stale_quote"), & &1.security.id)

    Repo.insert_all(ExchangeRate, [
      %{
        base_currency: "EUR",
        quote_currency: "USD",
        date: old,
        rate: Decimal.new("1.1"),
        source: "ecb",
        inserted_at: now,
        updated_at: now
      },
      %{
        base_currency: "EUR",
        quote_currency: "USD",
        date: future,
        rate: Decimal.new("900"),
        source: "ecb",
        inserted_at: now,
        updated_at: now
      }
    ])

    assert %ExchangeRate{date: ^old} = Fx.latest("EUR", "USD")
    assert Decimal.equal?(Fx.hub_rates(["USD"])["USD"], Decimal.new("1.1"))
    assert {:ok, rate} = Fx.rate("EUR", "USD")
    assert Decimal.equal?(rate, Decimal.new("1.1"))
  end
end
