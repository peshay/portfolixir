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

  # A LiveView test drives the backfill from another process (the LiveView
  # and its `start_async` task), where the test's process dictionary is out of
  # reach — so the history response also honours an application-env override
  # set by `put_shared_history_response/1` (tests using it run `async: false`).
  @impl true
  def fetch_history(_opts) do
    case Process.get({__MODULE__, :history}) ||
           Application.get_env(:portfolixir, {__MODULE__, :history}) do
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

  @doc "Registers the response (per process) the next history fetch should return."
  def put_history_response(response) do
    Process.put({__MODULE__, :history}, response)
    :ok
  end

  @doc """
  Registers a history response visible to EVERY process (application env) —
  for LiveView tests whose backfill runs in the view's own task. Pair it with
  `clear_shared_history_response/0` in `on_exit`, and run the test `async: false`.
  """
  def put_shared_history_response(response) do
    Application.put_env(:portfolixir, {__MODULE__, :history}, response)
    :ok
  end

  @doc "Removes the shared history response."
  def clear_shared_history_response do
    Application.delete_env(:portfolixir, {__MODULE__, :history})
    :ok
  end

  @doc "Clears the per-process overrides (latest and history)."
  def clear_response do
    Process.delete(__MODULE__)
    Process.delete({__MODULE__, :history})
    :ok
  end
end
