defmodule Mix.CaptureTestRunTest do
  # Shares no DB state; exercises the capture script in an isolated tmp dir.
  use ExUnit.Case, async: true

  # User story:
  # As a local portfolio maintainer,
  # I want every local test run's full output and ExUnit seed persisted,
  # so that an intermittent failure burst is inspectable and replayable
  # instead of scrolled away (#682).
  #
  # Acceptance criteria:
  # - The wrapper writes the complete run output to a log file.
  # - The wrapper reports the captured seed and preserves the run's exit code.
  # - Old logs beyond the keep window are pruned.

  @script Path.expand("../../scripts/capture-test-run.sh", __DIR__)

  defp run_capture(tmp_dir, stub_body, args \\ [], keep \\ "20") do
    stub = Path.join(tmp_dir, "stub-mix-test.sh")
    File.write!(stub, "#!/usr/bin/env bash\n" <> stub_body)
    File.chmod!(stub, 0o755)

    System.cmd("bash", [@script | args],
      env: [
        {"TEST_RUN_LOG_DIR", Path.join(tmp_dir, "runs")},
        {"TEST_RUN_LOG_KEEP", keep},
        {"MIX_TEST_CMD", stub}
      ],
      stderr_to_stdout: true
    )
  end

  test "persists the full output with the seed and keeps the exit code" do
    tmp_dir = Path.join(System.tmp_dir!(), "capture-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {output, status} =
      run_capture(tmp_dir, """
      echo "3 tests, 1 failure"
      echo "Randomized with seed 424242"
      exit 2
      """)

    assert status == 2
    assert output =~ "captured: "
    assert output =~ "seed 424242"

    [log] = Path.wildcard(Path.join(tmp_dir, "runs/mix-test-*.log"))
    contents = File.read!(log)
    assert contents =~ "3 tests, 1 failure"
    assert contents =~ "Randomized with seed 424242"
  end

  test "prunes logs beyond the keep window" do
    tmp_dir = Path.join(System.tmp_dir!(), "capture-test-#{System.unique_integer([:positive])}")
    runs_dir = Path.join(tmp_dir, "runs")
    File.mkdir_p!(runs_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    for i <- 1..3 do
      File.write!(Path.join(runs_dir, "mix-test-2026010100000#{i}.log"), "old #{i}")
    end

    {_output, 0} = run_capture(tmp_dir, "echo ok\nexit 0\n", [], "2")

    assert length(Path.wildcard(Path.join(runs_dir, "mix-test-*.log"))) == 2
  end
end
