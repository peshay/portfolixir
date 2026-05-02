defmodule Portfolixir.Quotes.FakeProvider do
  @moduledoc "Deterministic fake provider for quote tests."

  @behaviour Portfolixir.Quotes.Provider

  @impl true
  def historical_quotes(_config, %{symbol: symbol}) when is_binary(symbol) do
    {:ok,
     [
       %{date: ~D[2024-01-02], close: "101.25", source: "fake", currency_code: "EUR"},
       %{date: ~D[2024-01-03], close: "103.10", source: "fake", currency_code: "EUR"}
     ]}
  end

  def historical_quotes(_config, _security_ref), do: {:error, :invalid_security_ref}

  @impl true
  def latest_quote(_config, %{symbol: symbol}) when is_binary(symbol) do
    {:ok, %{date: ~D[2024-01-03], close: "103.10", source: "fake", currency_code: "EUR"}}
  end

  def latest_quote(_config, _security_ref), do: {:error, :invalid_security_ref}

  @impl true
  def capabilities(_config), do: {:ok, ["read_latest_quote", "read_historical_quotes"]}
end
