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

  @doc """
  The provider's **historical series** — every published date, not only the
  latest — for the one-shot backfill (issue #737, Sprint 9 D-1). Optional: a
  provider without a history returns `{:error, :history_unsupported}` through
  `Portfolixir.Fx.RateSync.backfill/1`.
  """
  @callback fetch_history(opts :: keyword()) :: {:ok, [rate_row()]} | {:error, term()}

  @optional_callbacks fetch_history: 1
end
