defmodule Portfolixir.Fx.RateSync.Fake do
  @moduledoc """
  Test-only exchange-rate fetcher. Registered via Application config so the
  test suite never makes real HTTP calls. Each test can set the response with
  `put_response/1`.
  """

  @behaviour Portfolixir.Fx.RateSync.Provider

  @impl true
  def id, do: :fake

  @impl true
  def fetch(_opts) do
    case Process.get(__MODULE__) do
      {:ok, _} = ok -> ok
      {:error, _} = err -> err
      nil -> {:ok, []}
    end
  end

  @doc "Registers the response (per process) the next fetch should return."
  def put_response(response) do
    Process.put(__MODULE__, response)
    :ok
  end

  @doc "Clears the per-process override."
  def clear_response do
    Process.delete(__MODULE__)
    :ok
  end
end
