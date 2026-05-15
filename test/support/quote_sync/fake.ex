defmodule Portfolixir.Catalog.QuoteSync.Fake do
  @moduledoc """
  Test-only quote fetcher. Registered via Application config so the test
  suite never makes real HTTP calls. Each test can set its response for a
  given security via `put_response/2`.
  """

  @behaviour Portfolixir.Catalog.QuoteSync.Provider

  alias Portfolixir.Catalog.Security

  @impl true
  def id, do: :fake

  @impl true
  def fetch(%Security{id: id}, _opts) do
    case Process.get({__MODULE__, id}) do
      {:ok, _} = ok -> ok
      {:error, _} = err -> err
      nil -> {:ok, []}
    end
  end

  @doc "Registers a response (per process) for the given security id."
  def put_response(security_id, response) when is_integer(security_id) do
    Process.put({__MODULE__, security_id}, response)
    :ok
  end

  @doc "Clears all per-process overrides."
  def clear_responses do
    Process.get_keys()
    |> Enum.filter(&match?({__MODULE__, _}, &1))
    |> Enum.each(&Process.delete/1)

    :ok
  end
end
