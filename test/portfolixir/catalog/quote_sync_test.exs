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

  # Q1 (#1410): an adapter that must never be asked. It tells the test it was
  # called (the sync runs it in the test's own process, under its
  # single-flight key, and rescues what it raises, so a raise would only turn
  # into an :error result) and hands back a close, so a call would also leave
  # a stored row behind; the tests refute both.
  defmodule TripwireAdapter do
    @moduledoc false
    @behaviour Portfolixir.Catalog.QuoteSync.Provider

    @impl true
    def id, do: :tripwire

    @impl true
    def fetch(security, _opts) do
      send(self(), {:tripwire_fetched, security.id})
      {:ok, [%{date: ~D[2026-05-15], close: Decimal.new("999.00")}]}
    end
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

    {result, log} =
      ExUnit.CaptureLog.with_log(fn -> QuoteSync.sync_all(adapter_for: %{"manual" => Fake}) end)

    assert {:ok, %{ok: 1, error: 1, skipped: 0, results: results}} = result
    assert Enum.any?(results, &(&1.status == :error and &1.reason == :timeout))
    assert log =~ "quote fetch failed for security ##{sec_a.id} via #{inspect(Fake)}: :timeout"
    assert Quotes.latest(sec_b.id).date == ~D[2026-05-15]
    assert Quotes.latest(sec_a.id) == nil
  end

  # User story:
  # As a local portfolio maintainer,
  # I want the background sync to never overwrite my hand-entered quote rows,
  # so that a manual correction survives every sync cycle instead of being
  # silently replaced by provider history.
  #
  # Acceptance criteria:
  # - A stored row with source "manual" on a provider-covered date keeps its
  #   close and source after a sync.
  # - The sync's remaining rows are still written, the per-security result
  #   reports the skipped-manual count, and a warning is logged.
  test "sync does not overwrite manual rows and reports the skipped count" do
    sec = security_fixture(name: "Gamma", provider: "coingecko")

    {:ok, 1} =
      Quotes.upsert_many(sec.id, [
        %{date: ~D[2026-05-15], close: Decimal.new("100"), source: "manual"}
      ])

    Fake.put_response(
      sec.id,
      {:ok,
       [
         %{date: ~D[2026-05-14], close: Decimal.new("90.00")},
         %{date: ~D[2026-05-15], close: Decimal.new("110.00")}
       ]}
    )

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:ok, %{ok: 1, skipped: 0, error: 0, results: [result]}} =
                 QuoteSync.sync_all(adapter_for: %{"coingecko" => Fake})

        assert %{status: :ok, upserted: 1, skipped_manual: 1} = result
      end)

    assert log =~ "skipped 1 manual quote row"

    by_date =
      Quotes.range(sec.id, ~D[2026-01-01], ~D[2026-12-31])
      |> Map.new(&{&1.date, &1})

    assert Decimal.equal?(by_date[~D[2026-05-15]].close, Decimal.new("100"))
    assert by_date[~D[2026-05-15]].source == "manual"
    assert Decimal.equal?(by_date[~D[2026-05-14]].close, Decimal.new("90.00"))
    assert by_date[~D[2026-05-14]].source == "coingecko"
  end

  test "sync still replaces its own previously synced rows" do
    sec = security_fixture(name: "Delta", provider: "coingecko")

    Fake.put_response(
      sec.id,
      {:ok, [%{date: ~D[2026-05-15], close: Decimal.new("100.00")}]}
    )

    assert {:ok, %{ok: 1}} = QuoteSync.sync_all(adapter_for: %{"coingecko" => Fake})

    Fake.put_response(
      sec.id,
      {:ok, [%{date: ~D[2026-05-15], close: Decimal.new("105.00")}]}
    )

    assert {:ok, %{ok: 1, results: [%{upserted: 1, skipped_manual: 0}]}} =
             QuoteSync.sync_all(adapter_for: %{"coingecko" => Fake})

    latest = Quotes.latest(sec.id)
    assert Decimal.equal?(latest.close, Decimal.new("105.00"))
    assert latest.source == "coingecko"
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

  # User story:
  # As a local portfolio maintainer who keeps a security's quotes by hand,
  # I want the scheduled run and "sync all" to leave a security alone whose
  # feed is Manual or None, and a retired one,
  # so that no provider row lands behind a feed the screen says is manual,
  # or on a sold-out or delisted security nobody prices any more (#1410).
  #
  # Acceptance criteria:
  # - A security whose feed is MANUAL or NONE is skipped with reason
  #   `:manual_feed`; its adapter is never called and no quote is stored.
  # - A retired security is skipped with reason `:retired`, the same way.
  # - Both are counted as skipped, as `:missing_ticker` is; the other
  #   securities of the run are synced as before.
  for feed <- ~w(MANUAL NONE) do
    test "the full sync skips a security whose feed is #{feed} and calls no provider" do
      stopped = security_fixture(name: "Stopped", provider: "manual", feed: unquote(feed))
      synced = security_fixture(name: "Synced", provider: "manual", feed: "PORTFOLIO_PERFORMANCE")
      stopped_id = stopped.id
      synced_id = synced.id

      assert {:ok, %{ok: 1, skipped: 1, error: 0, results: results}} =
               QuoteSync.sync_all(adapter_for: %{"manual" => TripwireAdapter})

      assert %{status: :skipped, reason: :manual_feed} =
               Enum.find(results, &(&1.security_id == stopped_id))

      refute_received {:tripwire_fetched, ^stopped_id}
      assert_received {:tripwire_fetched, ^synced_id}
      assert Quotes.latest(stopped_id) == nil
      assert Decimal.equal?(Quotes.latest(synced_id).close, Decimal.new("999.00"))
    end
  end

  test "the full sync skips a retired security and calls no provider" do
    retired = security_fixture(name: "Retired", provider: "manual", is_retired: true)
    retired_id = retired.id

    assert {:ok, %{ok: 0, skipped: 1, error: 0, results: [result]}} =
             QuoteSync.sync_all(adapter_for: %{"manual" => TripwireAdapter})

    assert %{security_id: ^retired_id, status: :skipped, reason: :retired} = result
    refute_received {:tripwire_fetched, _id}
    assert Quotes.latest(retired_id) == nil
  end

  # User story:
  # As a local portfolio maintainer,
  # I want an explicit sync of one security to still fetch a retired one, and
  # never one whose feed is Manual or None,
  # so that I can refill a retired security's history on purpose while a
  # manual feed stays a stop on every path (#1410).
  #
  # Acceptance criteria:
  # - `sync_security/2` of a retired security calls its adapter and stores
  #   the rows.
  # - `sync_security/2` of a security whose feed is MANUAL skips it with
  #   `:manual_feed` and calls no provider.
  # - `adapter?/2` is false for a security whose feed is MANUAL or NONE, so
  #   the release of manual quotes says no sync refills the days.
  test "an explicit sync runs for a retired security and stops at a manual feed" do
    retired = security_fixture(name: "Retired", provider: "manual", is_retired: true)
    retired_id = retired.id

    Fake.put_response(retired_id, {:ok, [%{date: ~D[2026-05-15], close: Decimal.new("12.50")}]})

    assert %{status: :ok, upserted: 1} =
             QuoteSync.sync_security(retired, adapter_for: %{"manual" => Fake})

    assert Decimal.equal?(Quotes.latest(retired_id).close, Decimal.new("12.50"))

    manual = security_fixture(name: "Manual", provider: "manual", feed: "MANUAL")
    manual_id = manual.id

    assert %{security_id: ^manual_id, status: :skipped, reason: :manual_feed} =
             QuoteSync.sync_security(manual, adapter_for: %{"manual" => TripwireAdapter})

    refute_received {:tripwire_fetched, ^manual_id}
    assert Quotes.latest(manual_id) == nil

    refute QuoteSync.adapter?(manual, adapter_for: %{"manual" => Fake})

    none = security_fixture(name: "None", provider: "manual", feed: "NONE")
    refute QuoteSync.adapter?(none, adapter_for: %{"manual" => Fake})
    assert QuoteSync.adapter?(retired, adapter_for: %{"manual" => Fake})
  end
end
