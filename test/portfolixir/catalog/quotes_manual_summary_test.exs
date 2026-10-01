defmodule Portfolixir.Catalog.QuotesManualSummaryTest do
  # Sprint 17 V2 (T-9, pick G3-A): the reads the release of manual quotes
  # needs and nothing had — which of a security's stored quotes are manual,
  # over its whole history, in which stretches, how many a range holds, and
  # whether the quote sync can refill a released day at all. Every name,
  # close and date is synthetic.
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Catalog.QuoteSync
  alias Portfolixir.Catalog.QuoteSync.Fake

  setup do
    %{security: create_security!(name: "Meridian Global Equity ETF", ticker: nil)}
  end

  defp provider!(security, dates) do
    rows = Enum.map(dates, &%{date: &1, close: "100.00", source: "portfolio_performance"})
    {:ok, _count} = Quotes.upsert_many(security.id, rows)
  end

  defp manual!(security, dates) do
    rows = Enum.map(dates, &%{"date" => Date.to_iso8601(&1), "close" => "101.00"})
    {:ok, _} = Quotes.upsert_authored(Actor.api_token_rw("synthetic"), security.id, rows)
  end

  # User story:
  # As the operator about to release manual quotes,
  # I want to know how many of a security's stored quotes are manual, from
  # when to when, and in which stretches, over the whole history,
  # so that I release what I mean and not only what the chart's range shows.
  #
  # Acceptance criteria:
  # - count, first and last cover every stored manual quote; stored_count
  #   every stored quote.
  # - A stretch is a run of manual quotes with no quote of another source
  #   between them: its first and last date and its count, ascending.
  # - stretches: n keeps the newest n stretches, still ascending;
  #   stretch_count counts them all.
  test "summarizes the manual quotes and their stretches over the whole history", ctx do
    provider!(ctx.security, [~D[2026-06-26], ~D[2026-06-29], ~D[2026-07-06], ~D[2026-09-11]])
    provider!(ctx.security, [~D[2026-09-17], ~D[2026-09-18]])
    manual!(ctx.security, [~D[2026-06-30], ~D[2026-07-01], ~D[2026-07-02], ~D[2026-07-03]])
    manual!(ctx.security, [~D[2026-09-14], ~D[2026-09-15], ~D[2026-09-16]])
    manual!(ctx.security, [~D[2026-09-21]])

    assert Quotes.manual_summary(ctx.security.id) == %{
             count: 8,
             first: ~D[2026-06-30],
             last: ~D[2026-09-21],
             stored_count: 14,
             stretch_count: 3,
             stretches: [
               %{from: ~D[2026-06-30], to: ~D[2026-07-03], count: 4},
               %{from: ~D[2026-09-14], to: ~D[2026-09-16], count: 3},
               %{from: ~D[2026-09-21], to: ~D[2026-09-21], count: 1}
             ]
           }

    assert %{stretch_count: 3, stretches: [%{from: ~D[2026-09-14]}, %{from: ~D[2026-09-21]}]} =
             Quotes.manual_summary(ctx.security.id, stretches: 2)
  end

  # User story:
  # As the operator of a security with no manual quote, or no quote at all,
  # I want the summary to say none,
  # so that the page shows no note and no control (G3-A, A7).
  #
  # Acceptance criteria:
  # - No manual quote: count 0, first and last nil, no stretch.
  # - A security whose quotes are all manual is one stretch over all of them.
  test "says none when nothing is manual, and one stretch when everything is", ctx do
    assert Quotes.manual_summary(ctx.security.id) == %{
             count: 0,
             first: nil,
             last: nil,
             stored_count: 0,
             stretch_count: 0,
             stretches: []
           }

    provider!(ctx.security, [~D[2026-09-01]])
    assert %{count: 0, stored_count: 1, stretches: []} = Quotes.manual_summary(ctx.security.id)

    other = create_security!(name: "Halvorsen Shipping Bond 2031", ticker: nil)
    manual!(other, [~D[2026-08-03], ~D[2026-08-04], ~D[2026-08-10]])

    assert %{count: 3, stored_count: 3, stretches: [%{count: 3}]} =
             Quotes.manual_summary(other.id)
  end

  # User story:
  # As the operator choosing a range in the release dialog,
  # I want the count of manual quotes in exactly that range,
  # so that the confirm names what the release would remove (G3-A ⑥).
  #
  # Acceptance criteria:
  # - Both bounds inclusive; provider quotes never counted.
  # - A range with no manual quote counts 0.
  test "counts the manual quotes of a range, bounds included", ctx do
    provider!(ctx.security, [~D[2026-07-06]])
    manual!(ctx.security, [~D[2026-06-30], ~D[2026-07-01], ~D[2026-09-14]])

    assert Quotes.manual_count(ctx.security.id, ~D[2026-06-30], ~D[2026-07-01]) == 2
    assert Quotes.manual_count(ctx.security.id, ~D[2026-07-02], ~D[2026-09-13]) == 0
    assert Quotes.manual_count(ctx.security.id, ~D[2026-01-01], ~D[2026-12-31]) == 3
  end

  # User story:
  # As the operator whose security has no quote provider the sync can call,
  # I want the page to know so before I release,
  # so that it can say the released days stay empty (G3-A, A3).
  #
  # Acceptance criteria:
  # - QuoteSync.adapter?/2 is true exactly when the configured adapter map
  #   (or :adapter_for) has an adapter for the security's provider — the
  #   check the sync makes before it fetches anything.
  # - A security without a provider has none.
  test "says whether the quote sync has an adapter for the security's provider", ctx do
    {:ok, manual} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Northwind Utilities",
        currency_code: "EUR",
        asset_class: "equity",
        provider: "manual"
      })

    assert QuoteSync.adapter?(manual, adapter_for: %{"manual" => Fake})
    refute QuoteSync.adapter?(manual, adapter_for: %{"portfolio_performance" => Fake})
    refute QuoteSync.adapter?(ctx.security, adapter_for: %{"manual" => Fake})

    # The test configuration names no adapter at all.
    refute QuoteSync.adapter?(manual)
  end

  # User story:
  # As the operator releasing the manual quotes of a security the sync's
  # adapter cannot ask for,
  # I want the page to know that too,
  # so that it never promises a refill the sync will skip (closing act,
  # γ D7: a provider-linked security without a ticker).
  #
  # Acceptance criteria:
  # - With the Yahoo adapter configured for its provider, a security without
  #   a ticker has none it can fetch with; with a ticker it has.
  # - A CoinGecko-linked security fetches only with a ticker and a currency.
  test "an adapter that cannot ask for the security is no adapter for it", ctx do
    yahoo = %{"portfolio_performance" => QuoteSync.Yahoo, "coingecko" => QuoteSync.Yahoo}
    linked = %{ctx.security | provider: "portfolio_performance"}

    refute QuoteSync.adapter?(%{linked | ticker_symbol: nil}, adapter_for: yahoo)
    refute QuoteSync.adapter?(%{linked | ticker_symbol: ""}, adapter_for: yahoo)
    assert QuoteSync.adapter?(%{linked | ticker_symbol: "MGEQ.DE"}, adapter_for: yahoo)

    coin = %{linked | provider: "coingecko", ticker_symbol: "BTC"}
    assert QuoteSync.adapter?(coin, adapter_for: yahoo)
    refute QuoteSync.adapter?(%{coin | currency_code: nil}, adapter_for: yahoo)
  end
end
