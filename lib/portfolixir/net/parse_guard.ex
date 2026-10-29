defmodule Portfolixir.Net.ParseGuard do
  @moduledoc """
  The wall-clock guard for a provider body's parse (security review
  2026-10-12, H50), the same shape `Portfolixir.Net.Http.get/2` puts around
  the request: the parse runs in a task of its own, and one still running at
  its bound is killed and answered `{:error, :parse_timeout}`.

  The request's deadline ends when the body has arrived; the parse comes
  after, in the caller, where it may hold a single-flight key or a
  discovery queue. Every adapter that reads a fetched body runs its parse
  here, so a slow parse fails alone. Each parse is also linear in the body;
  this bound is the defence behind that, not the budget it is sized for.
  """

  @default_timeout_ms 5_000

  @doc """
  Runs `fun` under `timeout_ms` (default 5 s). A parse that returns is
  `{:ok, value}`; one past the bound is `{:error, :parse_timeout}`, its
  process killed; one that raises or exits is
  `{:error, {:parse_failed, reason}}`.
  """
  @spec run((-> result), pos_integer()) ::
          {:ok, result} | {:error, :parse_timeout | {:parse_failed, term()}}
        when result: term()
  def run(fun, timeout_ms \\ @default_timeout_ms)
      when is_function(fun, 0) and is_integer(timeout_ms) and timeout_ms > 0 do
    task =
      Task.async(fn ->
        try do
          {:ok, fun.()}
        rescue
          exception -> {:error, {:parse_failed, exception.__struct__}}
        catch
          :exit, reason -> {:error, {:parse_failed, {:exit, reason}}}
        end
      end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      {:exit, reason} -> {:error, {:parse_failed, {:exit, reason}}}
      nil -> {:error, :parse_timeout}
    end
  end
end
