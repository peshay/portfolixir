defmodule Portfolixir.Portfolios.Performance.BackgroundWalksCappedTest do
  # K08 (security review 2026-10-12): the warm-up at boot and the refresher
  # after a write run the same performance walk a request runs, so they run
  # it under the same heap cap, each walk in a task of its own that fails
  # alone.
  use Portfolixir.DataCase, async: false

  import ExUnit.CaptureLog
  import Portfolixir.WorldFixtures

  alias Portfolixir.Derived.Memo
  alias Portfolixir.Derived.Refresher
  alias Portfolixir.DerivedConfig
  alias Portfolixir.Portfolios.Performance.Warmup

  @moduletag timeout: 120_000

  defp small_world! do
    world = base_world()
    deposit!(world, "1000", ~D[2025-01-02])
    sec = create_security!(name: "Background Walk", ticker: nil)
    buy!(world, sec, date: ~D[2025-01-02], price: "10")
    put_quotes!(sec, [{~D[2025-01-02], "10"}, {~D[2025-06-02], "12"}])
    world
  end

  # Every process created from here on reports how it ends.
  defp trace_exits! do
    :erlang.trace(:new_processes, true, [:procs, {:tracer, self()}])
    on_exit(fn -> :erlang.trace(:all, false, [:procs]) end)
  end

  # The cap every walk takes as its first act, lowered for this test to
  # 2 KiB, below what any walk holds, so the runtime kills the walk at its
  # first collection.
  defp lower_cap! do
    prior = Application.get_env(:portfolixir, Portfolixir.HeapCap, [])

    Application.put_env(
      :portfolixir,
      Portfolixir.HeapCap,
      Keyword.put(prior, :max_heap_bytes, 2_048)
    )

    on_exit(fn -> Application.put_env(:portfolixir, Portfolixir.HeapCap, prior) end)
  end

  setup do
    Memo.reset()
    DerivedConfig.enable!(lifetimes: [])
    :ok
  end

  # User story (security review 2026-10-12, K08):
  # As the operator whose instance warms its performance figures at boot,
  # I want the warm-up's walk to run under the heap cap a request runs under,
  # in a task of its own,
  # so that a walk grown past the cap is killed and logged while the warm-up
  # itself keeps running, instead of holding the node's memory.
  #
  # Acceptance criteria:
  # - A warm-up walk past the cap is killed with the runtime's heap-cap
  #   reason, in a process other than the warm-up's own.
  # - The warm-up process survives it and logs the skipped scope.
  test "the boot warm-up walks under the heap cap, and a walk past it fails alone" do
    small_world!()
    lower_cap!()
    trace_exits!()

    log =
      capture_log(fn ->
        warmup = start_supervised!({Warmup, []})

        assert_receive {:trace, walker, :exit, :killed}, 10_000
        assert walker != warmup

        # The warm-up runs in handle_continue: a system message is served
        # only after it returns, so this waits for the whole warm.
        _state = :sys.get_state(warmup, 60_000)
        assert Process.alive?(warmup)
        # The runtime's report of the kill is logged by another process.
        Process.sleep(200)
      end)

    assert log =~ "performance warm-up skipped"
  end

  # User story (security review 2026-10-12, K08):
  # As the operator whose writes re-materialize the performance figures in
  # the background,
  # I want the refresher's walk to run under the heap cap a request runs
  # under, in a task of its own,
  # so that a walk grown past the cap is killed and logged while the
  # refresher keeps serving the next write.
  #
  # Acceptance criteria:
  # - A refresher walk past the cap is killed with the runtime's heap-cap
  #   reason, in a process other than the refresher's own.
  # - The refresher survives it and logs the skipped scope.
  test "the refresher walks under the heap cap after a write, and a walk past it fails alone" do
    world = small_world!()
    lower_cap!()
    trace_exits!()

    log =
      capture_log(fn ->
        refresher =
          start_supervised!(
            {Refresher, refresh: &Warmup.warm_basis/1, quiet_ms: 10, max_delay_ms: 50}
          )

        Refresher.notify(["portfolio:#{world.portfolio.id}"])

        assert_receive {:trace, walker, :exit, :killed}, 10_000
        assert walker != refresher

        # The drain runs in handle_info: wait for it to return.
        _state = :sys.get_state(refresher, 60_000)
        assert Process.alive?(refresher)
        Process.sleep(200)
      end)

    assert log =~ "performance warm-up skipped"
  end
end
