defmodule Portfolixir.Interleave do
  @moduledoc """
  Runs another writer at an exact point of a call under test, for the race
  tests of the closing act's patch-coverage pass (ADR-0050 §10, E25 S6 F49).

  A real interleaving needs two connections, which the SQL sandbox
  serializes. So the other writer runs in the test's own process, from a
  handler on the repo's query event, right after the first query that
  `at?` matches has returned and before the call sends its next one. Outside
  the call's transaction the other writer commits (to the sandbox) as
  another connection's would; inside it, its writes are rolled back with the
  call's, and a test that relies on that says so.
  """

  import ExUnit.Assertions, only: [flunk: 1]

  @doc """
  Runs `call` and, once, right after the first query of this process whose
  telemetry metadata `at?` matches, `other_writer`. Answers `{call's result,
  other_writer's result}`; fails the test when the other writer never ran.
  """
  @spec run((map() -> boolean()), (-> term()), (-> term())) :: {term(), term()}
  def run(at?, other_writer, call)
      when is_function(at?, 1) and is_function(other_writer, 0) and is_function(call, 0) do
    test_pid = self()
    handler = "interleave-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler,
        [:portfolixir, :repo, :query],
        fn _event, _measurements, metadata, _config ->
          if self() == test_pid and at?.(metadata) do
            :telemetry.detach(handler)
            Process.put(handler, {:ran, other_writer.()})
          end
        end,
        nil
      )

    try do
      result = call.()

      case Process.get(handler) do
        {:ran, other} -> {result, other}
        nil -> flunk("the other writer never ran")
      end
    after
      :telemetry.detach(handler)
      Process.delete(handler)
    end
  end
end
