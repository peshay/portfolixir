defmodule Portfolixir.Catalog.SecuritySearch.Provider do
  @moduledoc """
  Behaviour every security-search adapter must implement.

  Implementations live under `Portfolixir.Catalog.SecuritySearch.*` and are
  registered via `config :portfolixir, Portfolixir.Catalog.SecuritySearch, providers: [...]`.
  In tests the registry is replaced with the in-memory `Fake` adapter so the
  test suite never makes real HTTP calls.
  """

  alias Portfolixir.Catalog.SecuritySearch.SearchResult

  @callback id() :: atom()
  @callback search(query :: String.t(), opts :: keyword()) ::
              {:ok, [SearchResult.t()]} | {:error, term()}
end
