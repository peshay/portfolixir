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

  # User story (#1411, Sprint 28 Q2):
  # As a local portfolio maintainer,
  # I want the sync to store nothing for a security whose provider answers
  # in another currency, and to name it in the sync's result,
  # so that a wrong listing never writes a series every figure then reads,
  # and the one security it concerns is named while the others sync.
  #
  # Acceptance criteria:
  # - Through the shipped Yahoo adapter, a USD answer for a EUR security and
  #   a GBp answer for a GBP security are each that security's error,
  #   `{:currency_mismatch, provider_currency}`, with no quote stored.
  # - An answer in the security's own currency, and one that states none,
  #   are stored as before; the run counts them ok and the two above errors.
  test "the sync stores nothing for an answer in another currency and names it per security" do
    usd_for_eur =
      security_fixture(name: "Listing USD", currency_code: "EUR", ticker_symbol: "ALSD")

    pence = security_fixture(name: "Listing GBp", currency_code: "GBP", ticker_symbol: "ALGB")
    own = security_fixture(name: "Listing EUR", currency_code: "EUR", ticker_symbol: "ALEU")
    unstated = security_fixture(name: "Listing none", currency_code: "EUR", ticker_symbol: "ALNO")

    stated = %{"ALSD" => "USD", "ALGB" => "GBp", "ALEU" => "EUR", "ALNO" => nil}

    plug = fn conn ->
      ticker = conn.path_info |> List.last()

      meta =
        case Map.fetch!(stated, ticker) do
          nil -> %{}
          currency -> %{"currency" => currency}
        end

      body = %{
        "chart" => %{
          "result" => [
            %{
              "meta" => meta,
              "timestamp" => [1_715_001_600],
              "indicators" => %{"quote" => [%{"close" => [100.10]}]}
            }
          ]
        }
      }

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(body))
    end

    {result, _log} =
      ExUnit.CaptureLog.with_log(fn ->
        QuoteSync.sync_all(
          adapter_for: %{"manual" => Portfolixir.Catalog.QuoteSync.Yahoo},
          req: [plug: plug]
        )
      end)

    assert {:ok, %{ok: 2, skipped: 0, error: 2, results: results}} = result
    by_id = Map.new(results, &{&1.security_id, &1})

    assert %{status: :error, reason: {:currency_mismatch, "USD"}} = by_id[usd_for_eur.id]
    assert %{status: :error, reason: {:currency_mismatch, "GBp"}} = by_id[pence.id]
    assert %{status: :ok, upserted: 1} = by_id[own.id]
    assert %{status: :ok, upserted: 1} = by_id[unstated.id]

    assert Quotes.latest(usd_for_eur.id) == nil
    assert Quotes.latest(pence.id) == nil
    assert Decimal.equal?(Quotes.latest(own.id).close, Decimal.new("100.1"))
    assert Decimal.equal?(Quotes.latest(unstated.id).close, Decimal.new("100.1"))
  end

  # User story (#1415, Sprint 28 Q3):
  # As a local portfolio maintainer,
  # I want every sync that reads the provider's currency to keep it on the
  # security, a refused one too,
  # so that a series stored before the check, or a ticker that moved to
  # another listing, can be named later without fetching anything.
  #
  # Acceptance criteria:
  # - A refused answer (USD for a EUR security) stores no quote but stores
  #   `provider_currency` "USD" and `provider_currency_at`, the time of the
  #   sync that read it.
  # - An answer in the security's own currency stores it too; an answer that
  #   states none leaves `provider_currency` as it was (nil: not yet known).
  # - A later sync that reads the same currency writes nothing (the time
  #   stays the first read's, no journal entry); one that reads another
  #   currency replaces both, journaled under the system job "quote_sync".
  test "the sync stores the currency the provider stated, a refused answer's too" do
    refused = security_fixture(name: "Listing USD", currency_code: "EUR", ticker_symbol: "PCUS")
    own = security_fixture(name: "Listing EUR", currency_code: "EUR", ticker_symbol: "PCEU")
    unstated = security_fixture(name: "Listing none", currency_code: "EUR", ticker_symbol: "PCNO")

    stated = %{"PCUS" => "USD", "PCEU" => "EUR", "PCNO" => nil}
    before_sync = DateTime.utc_now() |> DateTime.truncate(:second)

    sync = fn ->
      ExUnit.CaptureLog.with_log(fn ->
        QuoteSync.sync_all(
          adapter_for: %{"manual" => Portfolixir.Catalog.QuoteSync.Yahoo},
          req: [plug: chart_plug(stated)]
        )
      end)
    end

    {{:ok, %{ok: 2, error: 1}}, _log} = sync.()

    first = Catalog.get_security(refused.id)
    assert first.provider_currency == "USD"
    assert %DateTime{} = first.provider_currency_at
    assert DateTime.compare(first.provider_currency_at, before_sync) != :lt
    assert Quotes.latest(refused.id) == nil

    assert Catalog.get_security(own.id).provider_currency == "EUR"

    assert %{provider_currency: nil, provider_currency_at: nil} =
             Catalog.get_security(unstated.id)

    journaled = fn id ->
      Portfolixir.Journal.list_entries(resource_type: "security", resource_id: to_string(id))
      |> Enum.filter(&(&1.actor_type == :system_job and &1.actor_label == "quote_sync"))
    end

    assert [%{operation: :update}] = journaled.(refused.id)

    # The same answer again: nothing written.
    {{:ok, %{ok: 2, error: 1}}, _log} = sync.()
    again = Catalog.get_security(refused.id)
    assert again.provider_currency_at == first.provider_currency_at
    assert length(journaled.(refused.id)) == 1

    # The ticker fixed: the provider now states the security's own currency.
    {{:ok, %{ok: 3, error: 0}}, _log} =
      ExUnit.CaptureLog.with_log(fn ->
        QuoteSync.sync_all(
          adapter_for: %{"manual" => Portfolixir.Catalog.QuoteSync.Yahoo},
          req: [plug: chart_plug(Map.put(stated, "PCUS", "EUR"))]
        )
      end)

    assert Catalog.get_security(refused.id).provider_currency == "EUR"
    assert length(journaled.(refused.id)) == 2
  end

  # User story (Sprint 28 Q, coverage):
  # As a local portfolio maintainer whose adapter's answer carries a currency
  # the security cannot store,
  # I want the closes stored and the failed record logged, never the sync
  # failed for it,
  # so that the stated currency, a record about the security, never costs a
  # quote.
  #
  # Acceptance criteria:
  # - An adapter answering its rows with `%{currency: "EURO"}` (not three
  #   letters) has its rows stored and the sync ok; nothing is kept as the
  #   provider currency, and the log names the security.
  # - An answer whose meta carries no currency string stores its rows and
  #   keeps nothing.
  test "a stated currency the writer refuses costs no quote and is logged" do
    unstorable = security_fixture(name: "Unstorable", currency_code: "EUR")
    unstated = security_fixture(name: "Unstated", currency_code: "EUR")
    row = %{date: ~D[2026-05-14], close: Decimal.new("100.00")}

    Fake.put_response(unstorable.id, {:ok, [row], %{currency: "EURO"}})
    Fake.put_response(unstated.id, {:ok, [row], %{currency: nil}})

    {{:ok, %{ok: 2, error: 0}}, log} =
      ExUnit.CaptureLog.with_log(fn -> QuoteSync.sync_all(adapter_for: %{"manual" => Fake}) end)

    assert log =~ "quote sync kept no provider currency for security ##{unstorable.id}"

    for security <- [unstorable, unstated] do
      assert Decimal.equal?(Quotes.latest(security.id).close, Decimal.new("100.00"))
      assert %{provider_currency: nil} = Catalog.get_security(security.id)
    end
  end

  defp chart_plug(stated) do
    fn conn ->
      meta =
        case Map.fetch!(stated, List.last(conn.path_info)) do
          nil -> %{}
          currency -> %{"currency" => currency}
        end

      body = %{
        "chart" => %{
          "result" => [
            %{
              "meta" => meta,
              "timestamp" => [1_715_001_600],
              "indicators" => %{"quote" => [%{"close" => [100.10]}]}
            }
          ]
        }
      }

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(body))
    end
  end
end
