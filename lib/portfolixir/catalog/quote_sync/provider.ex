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
end
