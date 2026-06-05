defmodule Portfolixir.Fx.RateSyncTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Fx
  alias Portfolixir.Fx.RateSync
  alias Portfolixir.Fx.RateSync.Ecb
  alias Portfolixir.Fx.RateSync.Fake

  setup do
    Fake.clear_response()
    :ok
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
end
