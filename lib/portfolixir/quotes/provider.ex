defmodule Portfolixir.Quotes.Provider do
  @moduledoc "Read-only quote provider behaviour."

  @typedoc "Provider configuration (API keys etc. are out of scope for this story)."
  @type config :: map()

  @typedoc "Security selector understood by the provider."
  @type security_ref :: map()

  @typedoc "Normalized quote payload used by Portfolixir."
  @type quote :: %{
          required(:date) => Date.t(),
          required(:close) => Decimal.t() | integer() | float() | String.t(),
          optional(:open) => Decimal.t() | integer() | float() | String.t() | nil,
          optional(:high) => Decimal.t() | integer() | float() | String.t() | nil,
          optional(:low) => Decimal.t() | integer() | float() | String.t() | nil,
          optional(:volume) => integer() | nil,
          optional(:currency_code) => String.t() | nil,
          optional(:source) => String.t() | nil,
          optional(:metadata) => map() | nil
        }

  @callback historical_quotes(config(), security_ref()) :: {:ok, [quote()]} | {:error, term()}
  @callback latest_quote(config(), security_ref()) :: {:ok, quote() | nil} | {:error, term()}
  @callback capabilities(config()) :: {:ok, [String.t()]} | {:error, term()}
end
