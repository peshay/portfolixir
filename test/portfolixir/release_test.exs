defmodule Portfolixir.ReleaseTest do
  # Issue #760 (ADR-0045 §2): the production image carries no Mix, so the two
  # operator commands the docs name run through `Portfolixir.Release`.
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Derived.Memo
  alias Portfolixir.DerivedConfig
  alias Portfolixir.Release

  # User story:
  # As an operator upgrading the production image,
  # I want the entrypoint to run every pending migration before the app starts,
  # so that a release never serves a schema it was not built for.
  #
  # Acceptance criteria:
  # - migrate/0 runs to :ok on a migrated database (nothing pending is a no-op).
  test "migrate/0 runs the pending migrations and is a no-op when there are none" do
    assert Release.migrate() == :ok
  end

  # User story:
  # As an operator of the production image,
  # I want the drop-and-rebuild of the derived layer reachable without Mix,
  # so that ADR-0039 §6's emergency procedure is one command there too.
  #
  # Acceptance criteria:
  # - rebuild_derived/0 returns the same report the Mix task prints.
  test "rebuild_derived/0 is the release twin of the Mix task" do
    Memo.reset()
    DerivedConfig.enable!(lifetimes: [performance_analysis: :durable])

    assert {:ok, %{dropped: dropped, runtime_ms: runtime_ms}} = Release.rebuild_derived()
    assert is_integer(dropped) and dropped >= 0
    assert is_integer(runtime_ms) and runtime_ms >= 0
  end
end
