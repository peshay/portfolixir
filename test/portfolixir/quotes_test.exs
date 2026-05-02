defmodule Portfolixir.QuotesTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Quotes
  alias Portfolixir.Quotes.FakeProvider
  alias Portfolixir.Repo

  test "fake provider returns latest quote" do
    assert {:ok, quote} = FakeProvider.latest_quote(%{}, %{symbol: "MSCI"})

    assert quote == %{
             date: ~D[2024-01-03],
             close: "103.10",
             source: "fake",
             currency_code: "EUR"
           }
  end

  test "fake provider returns historical quotes" do
    assert {:ok, quotes} = FakeProvider.historical_quotes(%{}, %{symbol: "MSCI"})

    assert quotes == [
             %{date: ~D[2024-01-02], close: "101.25", source: "fake", currency_code: "EUR"},
             %{date: ~D[2024-01-03], close: "103.10", source: "fake", currency_code: "EUR"}
           ]
  end

  test "wrapper validates read capabilities" do
    assert {:ok, [%{date: ~D[2024-01-02]}, %{date: ~D[2024-01-03]}]} =
             Quotes.historical_quotes(FakeProvider, %{}, %{symbol: "MSCI"})

    assert {:ok, %{date: ~D[2024-01-03], close: "103.10"}} =
             Quotes.latest_quote(FakeProvider, %{}, %{symbol: "MSCI"})
  end

  test "unsupported write capabilities return explicit error" do
    for capability <- ["place_order", "create_payment", "withdraw", "transfer", "trade"] do
      assert {:error, {:unsupported_capability, ^capability}} =
               Quotes.call(FakeProvider, capability, %{}, %{symbol: "MSCI"})
    end
  end

  test "arbitrary unsupported capability returns explicit error" do
    assert {:error, {:unsupported_capability, "unsupported_capability_name"}} =
             Quotes.call(FakeProvider, "unsupported_capability_name", %{}, %{symbol: "MSCI"})
  end

  test "provider/security input does not create atoms" do
    unknown_capability =
      "unsupported_quote_capability_" <> Integer.to_string(System.unique_integer([:positive]))

    assert_raise ArgumentError, fn ->
      String.to_existing_atom(unknown_capability)
    end

    assert {:error, {:unsupported_capability, ^unknown_capability}} =
             Quotes.call(FakeProvider, unknown_capability, %{}, %{symbol: "MSCI"})

    assert_raise ArgumentError, fn ->
      String.to_existing_atom(unknown_capability)
    end
  end

  test "no ledger transactions are created" do
    initial_transaction_count = Repo.aggregate(Transaction, :count, :id)

    assert {:ok, _quote} = Quotes.latest_quote(FakeProvider, %{}, %{symbol: "MSCI"})
    assert {:ok, _quotes} = Quotes.historical_quotes(FakeProvider, %{}, %{symbol: "MSCI"})

    assert Repo.aggregate(Transaction, :count, :id) == initial_transaction_count
  end
end
