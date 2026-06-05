defmodule Portfolixir.Fx.RateSync.Provider do
  @moduledoc """
  Behaviour every exchange-rate feed adapter must implement.

  Implementations live under `Portfolixir.Fx.RateSync.*` and return EUR-hub
  rows ready for `Portfolixir.Fx.upsert_many/1`. The test suite registers an
  in-memory `Fake` adapter so it never makes real HTTP calls (see ADR-0005).
  """

  @type rate_row :: %{
          base_currency: String.t(),
          quote_currency: String.t(),
          date: Date.t(),
          rate: Decimal.t() | String.t(),
          source: String.t()
        }

  @callback id() :: atom()
  @callback fetch(opts :: keyword()) :: {:ok, [rate_row()]} | {:error, term()}
end
