defmodule Portfolixir.SingleFlight do
  @moduledoc """
  At most one run per key across the node (E25 S3, G04).

  A provider sync of one security and the one-shot FX backfill each hold a key
  for as long as they run; a second request for the same key while one runs
  gets `{:error, :in_progress}` at once and makes no provider call, which the
  API answers `409`. The key is registered by the running process in a unique
  `Registry`, so it is released when the run returns, raises or its process
  dies — a crashed run never leaves a key held.
  """

  @registry Portfolixir.SingleFlight.Registry

  @doc "The registry child the application starts."
  @spec child_spec(term()) :: Supervisor.child_spec()
  def child_spec(_opts), do: Registry.child_spec(keys: :unique, name: @registry)

  @doc """
  Runs `fun` while holding `key`: `{:ok, fun_result}`, or `{:error,
  :in_progress}` when another process holds it.
  """
  @spec run(term(), (-> result)) :: {:ok, result} | {:error, :in_progress} when result: term()
  def run(key, fun) when is_function(fun, 0) do
    case Registry.register(@registry, key, nil) do
      {:ok, _owner} ->
        try do
          {:ok, fun.()}
        after
          Registry.unregister(@registry, key)
        end

      {:error, {:already_registered, _holder}} ->
        {:error, :in_progress}
    end
  end
end
