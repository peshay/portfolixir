defmodule Portfolixir.Fx.RateSyncTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Fx
  alias Portfolixir.Fx.RateSync
  alias Portfolixir.Fx.RateSync.Ecb
  alias Portfolixir.Fx.RateSync.Fake

  # A provider that pings the test process when fetched, so we can observe that
  # the scheduler runs a sync shortly after startup — without real HTTP (#435).
  defmodule StartupProbe do
    @moduledoc false
    @behaviour Portfolixir.Fx.RateSync.Provider
    @impl true
    def id, do: :startup_probe
    @impl true
    def fetch(_opts) do
      send(:fx_startup_probe, :synced)
      {:ok, []}
    end
  end

  setup do
    Fake.clear_response()
    :ok
  end

  # Issue #435: with enabled?, the first sync runs after startup_delay_ms, not
  # interval_ms (12 h) — otherwise foreign cash is uncounted until the first
  # 12 h tick. Uses a unique name so it doesn't touch the app's scheduler.
  test "runs an initial sync shortly after startup when enabled" do
    Process.register(self(), :fx_startup_probe)

    start_supervised!(
      {RateSync,
       name: :ratesync_startup_test, enabled?: true, startup_delay_ms: 0, provider: StartupProbe}
    )

    assert_receive :synced, 1_000
  end

  defp row(quote, value, date \\ ~D[2026-06-04]) do
    %{base_currency: "EUR", quote_currency: quote, date: date, rate: value, source: "ecb"}
  end

  # User story:
  # As a self-hosting maintainer,
  # I want exchange rates refreshed from a provider into the local store,
  # so that conversions stay current without manual entry — and tests never
  # make real HTTP calls.

  test "fetches from the provider and upserts the rates" do
    Fake.put_response({:ok, [row("USD", "1.25"), row("GBP", "0.8")]})

    assert {:ok, %{provider: :fake, status: :ok, upserted: 2}} = RateSync.sync(provider: Fake)

    assert {:ok, usd} = Fx.convert(Decimal.new("100"), "EUR", "USD")
    assert Decimal.equal?(usd, Decimal.new("125"))
  end

  test "surfaces provider errors and writes nothing" do
    Fake.put_response({:error, :boom})

    assert {:error, :boom} = RateSync.sync(provider: Fake)
    assert Fx.list_rates() == []
  end

  test "parses the ECB daily XML into EUR-hub rows, dropping unsupported codes" do
    xml = """
    <gesmes:Envelope>
      <Cube>
        <Cube time='2026-06-04'>
          <Cube currency='USD' rate='1.0856'/>
          <Cube currency='GBP' rate='0.8412'/>
          <Cube currency='XYZ' rate='9.9'/>
        </Cube>
      </Cube>
    </gesmes:Envelope>
    """

    rows = Ecb.parse(xml)

    assert row("USD", "1.0856") in rows
    assert Enum.any?(rows, &(&1.quote_currency == "GBP"))
    refute Enum.any?(rows, &(&1.quote_currency == "XYZ"))
  end

  # User story (issue #737, Sprint 9 D-1):
  # As a local portfolio maintainer whose realized gain was excluded for a
  # missing close-date rate,
  # I want a one-shot backfill of the historical ECB series through the same
  # sync path,
  # so that every past published date gains its rate at once — and a date the
  # ECB never published stays absent, exactly as the exclusion rule requires.
  #
  # Acceptance criteria:
  # - parse_history/1 reads every dated <Cube time> block into EUR-hub rows,
  #   dropping unsupported currencies.
  # - backfill/1 fetches the provider's history and upserts it; the result
  #   states scope: :history.
  # - A provider without a history answers {:error, :history_unsupported}.
  test "parses the ECB historical XML into one row per published day and currency" do
    xml = """
    <gesmes:Envelope>
      <Cube>
        <Cube time='2026-02-20'>
          <Cube currency='USD' rate='1.0812'/>
          <Cube currency='GBP' rate='0.8500'/>
        </Cube>
        <Cube time='2026-02-19'>
          <Cube currency='USD' rate='1.0790'/>
          <Cube currency='XYZ' rate='9.9'/>
        </Cube>
      </Cube>
    </gesmes:Envelope>
    """

    rows = Ecb.parse_history(xml)

    assert row("GBP", "0.8500", ~D[2026-02-20]) in rows
    assert row("USD", "1.0812", ~D[2026-02-20]) in rows
    assert row("USD", "1.0790", ~D[2026-02-19]) in rows
    refute Enum.any?(rows, &(&1.quote_currency == "XYZ"))
    assert length(rows) == 3
  end

  test "backfill/1 upserts the provider's historical series and says so" do
    Fake.put_history_response(
      {:ok, [row("GBP", "0.85", ~D[2026-02-20]), row("GBP", "0.86", ~D[2026-02-19])]}
    )

    assert {:ok, %{provider: :fake, status: :ok, upserted: 2, scope: :history}} =
             RateSync.backfill(provider: Fake)

    # The exact booking-date rate is now stored — the strict rate_on/3 finds it.
    assert {:ok, rate} = Fx.rate_on("GBP", "EUR", ~D[2026-02-20])
    assert Decimal.equal?(rate, Decimal.div(Decimal.new(1), Decimal.new("0.85")))

    # A date the series does not carry stays absent: the rule is unchanged.
    assert {:error, :no_rate} = Fx.rate_on("GBP", "EUR", ~D[2026-02-21])

    # The daily sync's own result says which feed it ran.
    Fake.put_response({:ok, [row("USD", "1.25")]})
    assert {:ok, %{scope: :latest}} = RateSync.sync(provider: Fake)
  end

  defmodule NoHistory do
    @moduledoc false
    @behaviour Portfolixir.Fx.RateSync.Provider
    @impl true
    def id, do: :no_history
    @impl true
    def fetch(_opts), do: {:ok, []}
  end

  test "backfill/1 names a provider without a history" do
    assert {:error, :history_unsupported} = RateSync.backfill(provider: NoHistory)
  end
end
