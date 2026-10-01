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
  @callback fetch(security :: Security.t(), opts :: keyword()) ::
              {:ok, [quote_row()]} | {:error, term()}

  @doc """
  Whether the adapter can ask its feed for `security` at all — the
  precondition `fetch/2` answers with a skip reason (`:missing_ticker`,
  `:missing_currency`) when it does not hold. Optional: an adapter without it
  is taken to ask for every security (closing act, γ D7).
  """
  @callback fetchable?(security :: Security.t()) :: boolean()

  @optional_callbacks fetchable?: 1
end
