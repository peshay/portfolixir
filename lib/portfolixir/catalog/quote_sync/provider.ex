defmodule Portfolixir.Catalog.QuoteSync.Provider do
  @moduledoc """
  Behaviour every quote-feed adapter must implement.

  Implementations live under `Portfolixir.Catalog.QuoteSync.*` and are
  dispatched based on `Security.provider`. The test suite registers an
  in-memory `Fake` adapter so it never makes real HTTP calls.
  """

  alias Portfolixir.Catalog.Security

  @type quote_row :: %{date: Date.t(), close: Decimal.t()}

  @callback id() :: atom()
  @typedoc """
  What an answer stated beside its rows (#1415): `currency`, the currency the
  provider gave for the series, which the sync keeps on the security.
  """
  @type answer_meta :: %{optional(:currency) => String.t()}

  @doc """
  The security's daily closes. An adapter that reads the provider's currency
  answers `{:ok, rows, %{currency: currency}}`, and one whose provider stated
  another currency than the security's answers `{:error, {:currency_mismatch,
  currency}}` and no rows (#1411); the sync keeps the currency in both cases.
  """
  @callback fetch(security :: Security.t(), opts :: keyword()) ::
              {:ok, [quote_row()]} | {:ok, [quote_row()], answer_meta()} | {:error, term()}

  @doc """
  Whether the adapter can ask its feed for `security` at all — the
  precondition `fetch/2` answers with a skip reason (`:missing_ticker`,
  `:missing_currency`) when it does not hold. Optional: an adapter without it
  is taken to ask for every security (closing act, γ D7).
  """
  @callback fetchable?(security :: Security.t()) :: boolean()

  @optional_callbacks fetchable?: 1
end
