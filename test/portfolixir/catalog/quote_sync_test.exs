defmodule Portfolixir.Catalog.QuoteSyncTest do
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Catalog.QuoteSync
  alias Portfolixir.Catalog.QuoteSync.Fake

  defmodule MissingTickerAdapter do
    @moduledoc false
    @behaviour Portfolixir.Catalog.QuoteSync.Provider

    @impl true
    def id, do: :missing_ticker

    @impl true
    def fetch(_security, _opts), do: {:error, :missing_ticker}
  end

  # User story:
  # As a local portfolio maintainer,
  # I want quote history to keep itself up to date in the background and to
  # be syncable on demand,
  # so that the security list and chart reflect today's market without
  # manual data entry.
  #
  # Acceptance criteria:
  # - `QuoteSync.sync_now/0` triggers fetch+upsert for every security whose
  #   provider has a registered adapter; rows returned by the adapter end up
  #   in `security_quotes` with the right source.
  # - Securities whose provider has no adapter are skipped without raising.
  # - The background scheduler is opt-in (disabled by default in test).

  setup do
    Fake.clear_responses()

    {:ok, _pid} =
      start_supervised(
        {QuoteSync,
         name: :"quote_sync_#{System.unique_integer([:positive])}",
         enabled?: false,
         adapter_for: %{"manual" => Fake},
         interval_ms: 60_000}
      )

    :ok
  end

  defp security_fixture(attrs) do
    base = Enum.into(attrs, %{name: "Sec", currency_code: "USD", provider: "manual"})
    {:ok, sec} = Catalog.create_security(Portfolixir.Actor.owner_ui(), base)
    sec
  end

  test "sync_all/1 fetches via the adapter and upserts quote history" do
    sec = security_fixture(name: "Alpha", provider: "manual")

    Fake.put_response(
      sec.id,
      {:ok,
       [
         %{date: ~D[2026-05-14], close: Decimal.new("100.00")},
         %{date: ~D[2026-05-15], close: Decimal.new("110.00")}
       ]}
    )

    assert {:ok, %{ok: 1, skipped: 0, error: 0}} =
             QuoteSync.sync_all(adapter_for: %{"manual" => Fake})

    quotes = Quotes.range(sec.id, ~D[2026-01-01], ~D[2026-12-31])
    assert length(quotes) == 2
    assert Enum.all?(quotes, &(&1.source == "manual"))
  end

  test "skips securities whose provider has no registered adapter" do
    _alpha = security_fixture(provider: "coingecko")
    _beta = security_fixture(provider: nil)

    assert {:ok, %{ok: 0, skipped: 2, error: 0, results: results}} =
             QuoteSync.sync_all(adapter_for: %{"portfolio_performance" => Fake})

    assert Enum.all?(results, &(&1.status == :skipped))
    assert Enum.all?(results, &(&1.reason == :no_provider_adapter))
  end

  test "isolates a failing fetch — other securities still succeed" do
    sec_a = security_fixture(name: "Alpha", provider: "manual")
    sec_b = security_fixture(name: "Beta", provider: "manual")

    Fake.put_response(sec_a.id, {:error, :timeout})

    Fake.put_response(
      sec_b.id,
      {:ok, [%{date: ~D[2026-05-15], close: Decimal.new("50")}]}
    )

    assert {:ok, %{ok: 1, error: 1, skipped: 0, results: results}} =
             QuoteSync.sync_all(adapter_for: %{"manual" => Fake})

    assert Enum.any?(results, &(&1.status == :error and &1.reason == :timeout))
    assert Quotes.latest(sec_b.id).date == ~D[2026-05-15]
    assert Quotes.latest(sec_a.id) == nil
  end

  # User story:
  # As a local portfolio maintainer,
  # I want quote sync to report skipped and failed securities with reasons,
  # so that missing setup is auditable instead of being counted as success.
  #
  # Acceptance criteria:
  # - Missing ticker is reported as skipped with reason `:missing_ticker`.
  # - Missing adapter is reported as skipped with reason `:no_provider_adapter`.
  # - Aggregate counts still expose ok/skipped/error totals.
  test "sync_security returns detailed skipped reasons" do
    no_ticker = security_fixture(name: "No Ticker", provider: "manual", ticker_symbol: nil)
    no_ticker_id = no_ticker.id

    assert %{
             status: :skipped,
             reason: :missing_ticker,
             security_id: ^no_ticker_id
           } =
             QuoteSync.sync_security(no_ticker, adapter_for: %{"manual" => MissingTickerAdapter})

    no_adapter = security_fixture(name: "No Adapter", provider: "coingecko")
    no_adapter_id = no_adapter.id

    assert %{
             status: :skipped,
             reason: :no_provider_adapter,
             security_id: ^no_adapter_id
           } = QuoteSync.sync_security(no_adapter, adapter_for: %{"manual" => Fake})
  end
end
