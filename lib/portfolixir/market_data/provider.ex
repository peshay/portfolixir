defmodule Portfolixir.MarketData.Provider do
  @moduledoc "Behaviour for security lookup, preview, and historical quote providers."

  @typedoc "Provider configuration."
  @type config :: map()

  @typedoc "Search result or security reference understood by a provider."
  @type security_ref :: map()

  @typedoc "Normalized candidate security payload used by Portfolixir."
  @type candidate :: %{
          required(:name) => String.t(),
          required(:symbol) => String.t(),
          required(:provider_symbol) => String.t(),
          required(:provider_source) => String.t(),
          optional(:currency_code) => String.t() | nil,
          optional(:exchange_code) => String.t() | nil,
          optional(:market) => String.t() | nil,
          optional(:instrument_type) => String.t() | nil,
          optional(:metadata) => map()
        }

  @typedoc "Normalized provider preview payload."
  @type preview :: %{
          required(:name) => String.t(),
          required(:symbol) => String.t(),
          required(:provider_symbol) => String.t(),
          required(:provider_source) => String.t(),
          optional(:currency_code) => String.t() | nil,
          optional(:exchange_code) => String.t() | nil,
          optional(:market) => String.t() | nil,
          optional(:instrument_type) => String.t() | nil,
          optional(:latest_close) => Decimal.t() | integer() | float() | String.t() | nil,
          optional(:latest_close_date) => Date.t() | nil,
          optional(:metadata) => map()
        }

  @typedoc "Normalized quote payload."
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

  @callback search_securities(config(), String.t()) :: {:ok, [candidate()]} | {:error, term()}
  @callback preview_security(config(), security_ref()) :: {:ok, preview()} | {:error, term()}
  @callback historical_quotes(config(), security_ref(), map()) ::
              {:ok, [quote()]} | {:error, term()}
  @callback capabilities(config()) :: {:ok, [String.t()]} | {:error, term()}
end
