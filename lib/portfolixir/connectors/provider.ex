defmodule Portfolixir.Connectors.Provider do
  @moduledoc "Behaviour for read-only portfolio connectors."

  @callback accounts(config :: map()) ::
              {:ok, [map()]} | {:error, term()}

  @callback balances(config :: map()) ::
              {:ok, [map()]} | {:error, term()}

  @callback transactions(config :: map(), opts :: map()) ::
              {:ok, [map()]} | {:error, term()}

  @callback documents(config :: map(), opts :: map()) ::
              {:ok, [map()]} | {:error, term()}

  @callback permissions(config :: map()) ::
              {:ok, [String.t()]} | {:error, term()}
end
