defmodule Portfolixir.LogNoiseTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Portfolixir.LogNoise

  require Logger

  # A handler that drops everything: the filter under test runs before it.
  defmodule Sink do
    @moduledoc false
    def log(_event, _config), do: :ok
  end

  # User story (#927):
  # As the maintainer reading a red CI run,
  # I want a run whose console log carries a warning or an error no test
  # captured to fail,
  # so that new log noise is caught when it lands instead of burying the next
  # real failure.
  #
  # Acceptance criteria:
  # - The filter records a warning or an error that reaches its handler, and
  #   leaves the event to the handler unchanged.
  # - An event below :warning is not recorded.
  # - The report names how many events reached the console and lists them.
  test "the filter records a warning that reaches its handler" do
    table = :ets.new(:log_noise_test, [:public, :ordered_set])
    handler = :"log_noise_test_#{System.unique_integer([:positive])}"
    :ok = :logger.add_handler(handler, Sink, %{level: :all})
    on_exit(fn -> :logger.remove_handler(handler) end)
    :ok = LogNoise.attach(handler, table)

    message = "synthetic noise #{System.unique_integer([:positive])}"

    # Captured, so the console handler never sees it; the test handler does.
    assert capture_log(fn -> Logger.warning(message) end) =~ message

    assert {count, events} = LogNoise.recorded(table)
    assert count >= 1
    assert Enum.any?(events, &(&1.level == :warning and inspect(&1.msg) =~ message))
  end

  test "an event below :warning is not recorded, and the filter decides nothing" do
    table = :ets.new(:log_noise_test, [:public, :ordered_set])

    assert LogNoise.record(%{level: :info, msg: {:string, "fine"}, meta: %{}}, table) == :ignore
    assert LogNoise.recorded(table) == {0, []}

    event = %{level: :error, msg: {:string, "boom"}, meta: %{}}
    assert LogNoise.record(event, table) == :ignore
    assert LogNoise.recorded(table) == {1, [event]}
  end

  test "the report counts the events and lists their messages" do
    events = [
      %{level: :error, msg: {:string, "owner exited\nstack line"}, meta: %{time: 0}},
      %{level: :warning, msg: {:string, "fx fetch failed"}, meta: %{time: 0}}
    ]

    report = LogNoise.report(2, events)

    assert report =~ "2 warning or error event(s) reached the console log"
    assert report =~ "[error] owner exited"
    assert report =~ "[warning] fx fetch failed"
  end
end
