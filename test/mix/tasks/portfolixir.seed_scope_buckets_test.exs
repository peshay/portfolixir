defmodule Mix.Tasks.Portfolixir.SeedScopeBucketsTest do
  @moduledoc """
  Pins the on-demand seed task for restore-after-migrate installs (fix round,
  ADR-0024). The task is deliberately a thin wrapper: the seed itself is pinned
  in `Portfolixir.Buckets.PortfolioSeedTest`; here we assert the operator-facing
  behavior — the printed summary and the idempotent re-run.

  `Mix.shell/1` is global, so this case must not run async.
  """
  use Portfolixir.DataCase, async: false

  import Portfolixir.WorldFixtures, only: [base_world: 1]

  alias Portfolixir.Buckets
  alias Portfolixir.Derived.DataVersion

  setup do
    previous_shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(previous_shell) end)
    :ok
  end

  # User story (fix round, restore-after-migrate installs):
  # As a local portfolio maintainer who migrated an empty database and restored
  # my data afterwards,
  # I want `mix portfolixir.seed_scope_buckets` to create the missing
  # bucket/view pairs and tell me exactly what it did,
  # so that I can verify the catch-up migration without reading the database.
  #
  # Acceptance criteria:
  # - The task runs the same seed as the migration and prints the summary
  #   counters (buckets/views created, accounts tagged, skipped).
  # - A second run is a no-op and reports all zeros.
  test "seeds the missing bucket/view pairs and prints the summary" do
    base_world(name: "Restored", cash_name: "R Cash", depot_name: "R Depot")

    # Rerun the task exactly as the CLI would; the `app.start` requirement is
    # a no-op here because the app is already running inside the test sandbox.
    Mix.Task.rerun("portfolixir.seed_scope_buckets")

    assert_received {:mix_shell, :info, [summary]}
    assert summary =~ "Portfolio scope seed complete"
    assert summary =~ "buckets created:        1"
    assert summary =~ "views created:          1"
    assert summary =~ "accounts tagged:        2"
    assert summary =~ "skipped (other scope):  0"

    assert %{migrated?: true, buckets: [%{name: "Restored"}], views: [%{name: "Restored"}]} =
             Buckets.migration_summary()

    # Idempotency: the second run changes nothing and says so.
    Mix.Task.rerun("portfolixir.seed_scope_buckets")

    assert_received {:mix_shell, :info, [rerun_summary]}
    assert rerun_summary =~ "buckets created:        0"
    assert rerun_summary =~ "views created:          0"
    assert rerun_summary =~ "accounts tagged:        0"

    assert length(Buckets.migration_summary().buckets) == 1
  end

  # User story (#1042, Sprint 19 B1):
  # As a local portfolio maintainer catching up a restored install,
  # I want the task to invalidate the derived figures once its seed has
  # tagged my accounts,
  # so that a view's figures computed before the seed are not served as
  # current after it.
  #
  # Acceptance criteria:
  # - The seed the task runs is frozen to its migration's schema and bumps no
  #   data version itself (nothing derived exists at that version); the task
  #   bumps every portfolio's basis, and the global one, after a seed that
  #   created or tagged anything.
  # - A run that seeds nothing bumps nothing.
  test "a seed that tags an account bumps the data version, and a no-op run does not" do
    world = base_world(name: "Restored", cash_name: "R Cash", depot_name: "R Depot")
    portfolio_basis = DataVersion.portfolio_basis(world.portfolio.id)
    versions = fn -> {DataVersion.current(portfolio_basis), DataVersion.current("global")} end

    {portfolio_before, global_before} = versions.()

    Mix.Task.rerun("portfolixir.seed_scope_buckets")
    assert_received {:mix_shell, :info, [summary]}
    assert summary =~ "accounts tagged:        2"

    {portfolio_seeded, global_seeded} = versions.()
    assert portfolio_seeded > portfolio_before
    assert global_seeded > global_before

    Mix.Task.rerun("portfolixir.seed_scope_buckets")
    assert_received {:mix_shell, :info, [rerun_summary]}
    assert rerun_summary =~ "accounts tagged:        0"

    assert versions.() == {portfolio_seeded, global_seeded}
  end
end
