defmodule Portfolixir.LoweredHeapCapTest do
  # #1440: the heap-cap tests lower the cap through `Portfolixir.LoweredHeapCap`,
  # which keeps the lowered cap to the call it wraps and returns only once
  # the runtime has logged every kill it caused. Not async: the cap is the
  # application environment, and this file holds the runtime's logger proxy.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Portfolixir.HeapCap
  alias Portfolixir.LoweredHeapCap

  @lowered_bytes 2_048

  # Keeps the runtime's logger proxy busy for `ms`, from the moment this
  # returns: a kill report the runtime sends meanwhile waits in its queue,
  # as it does when the node is under load.
  defp hold_logger_proxy(ms) do
    test = self()

    spawn(fn ->
      :sys.replace_state(:logger_proxy, fn state ->
        send(test, :logger_proxy_held)
        Process.sleep(ms)
        state
      end)
    end)

    assert_receive :logger_proxy_held
  end

  # A process that caps itself under the cap of the moment, grows past
  # 2 KiB and collects, so a lowered cap kills it at that collection.
  defp spawn_growing_process do
    spawn_monitor(fn ->
      HeapCap.cap!()
      list = Enum.to_list(1..10_000)
      :erlang.garbage_collect()
      length(list)
    end)
  end

  # User story (#1440):
  # As the maintainer whose full run must not fail on log noise with no test
  # failed,
  # I want a test that lowers the heap cap to return only once the runtime
  # has logged the kill the lowered cap caused,
  # so that the report lands in the test's own capture, also when the
  # runtime's logger proxy handles it late under load.
  #
  # Acceptance criteria:
  # - A kill report the logger proxy handles after the killed process is
  #   gone is in the capture around the lowered cap, and so never reaches
  #   the console.
  # - The cap is the configured one again once the call returns.
  test "a kill report the runtime logs late still lands in the capture the lowered cap ran in" do
    prior_words = HeapCap.max_heap_words()

    log =
      capture_log(fn ->
        LoweredHeapCap.run(@lowered_bytes, fn ->
          hold_logger_proxy(300)
          {pid, watch} = spawn_growing_process()
          assert_receive {:DOWN, ^watch, :process, ^pid, :killed}, 2_000
        end)
      end)

    assert log =~ "maximum heap size reached"
    assert HeapCap.max_heap_words() == prior_words
  end

  # User story (#1440):
  # As the maintainer of a heap-cap test,
  # I want the lowered cap kept to the call that provokes the kill,
  # so that a process the test did not mean to cap is never killed, and
  # reported, after its capture has closed.
  #
  # Acceptance criteria:
  # - A process still holding the lowered cap when the call has run fails
  #   the call, named in the failure, instead of being left to be killed
  #   later.
  test "a process left holding the lowered cap fails the call, named" do
    test = self()

    holder =
      spawn(fn ->
        receive do
          :go -> HeapCap.cap!()
        end

        send(test, :capped)

        receive do
          :stop -> :ok
        end
      end)

    error =
      assert_raise ExUnit.AssertionError, fn ->
        # 64 KiB: lowered, but more than the holder ever holds, so it lives.
        LoweredHeapCap.run(
          65_536,
          fn ->
            send(holder, :go)
            assert_receive :capped
          end,
          timeout: 100
        )
      end

    send(holder, :stop)
    assert error.message =~ inspect(holder)
  end
end
