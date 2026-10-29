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

  # User story (security review 2026-10-12, K05):
  # As an operator running the derived-value rebuild beside a running
  # instance (`docker compose exec app bin/portfolixir eval ...`),
  # I want the rebuild to start the application without its web listener,
  # its schedulers' boot work or its boot steps,
  # so that the emergency procedure ADR-0039 §6 names works while the
  # instance holds its port, and does nothing but the rebuild.
  #
  # Acceptance criteria:
  # - With the endpoint configured to serve and every scheduler on,
  #   rebuild_derived/0 returns its report, and the configuration it started
  #   under has the endpoint's server off, the quote and FX syncs, the
  #   warm-up, the refresher and logo discovery off, and the boot seed and
  #   logo reconciliation off.
  test "rebuild_derived/0 starts without the web listener, the schedulers or the boot steps" do
    keys = [
      PortfolixirWeb.Endpoint,
      Portfolixir.Catalog.QuoteSync,
      Portfolixir.Fx.RateSync,
      Portfolixir.Portfolios.Performance.Warmup,
      Portfolixir.Derived.Refresher,
      :enable_logo_discovery,
      :seed_builtins_on_boot,
      :reconcile_logos_on_boot
    ]

    previous = Map.new(keys, &{&1, Application.fetch_env(:portfolixir, &1)})

    on_exit(fn ->
      for {key, value} <- previous do
        case value do
          {:ok, value} -> Application.put_env(:portfolixir, key, value)
          :error -> Application.delete_env(:portfolixir, key)
        end
      end
    end)

    put = fn key, opts ->
      Application.put_env(
        :portfolixir,
        key,
        Keyword.merge(Application.get_env(:portfolixir, key, []), opts)
      )
    end

    put.(PortfolixirWeb.Endpoint, server: true)

    for key <- Enum.slice(keys, 1..4), do: put.(key, enabled?: true)

    for key <- Enum.drop(keys, 5), do: Application.put_env(:portfolixir, key, true)

    Memo.reset()
    assert {:ok, %{dropped: _, runtime_ms: _}} = Release.rebuild_derived()

    refute Phoenix.Endpoint.Supervisor.server?(:portfolixir, PortfolixirWeb.Endpoint)

    for key <- Enum.slice(keys, 1..4) do
      assert Application.get_env(:portfolixir, key)[:enabled?] == false, inspect(key)
    end

    for key <- Enum.drop(keys, 5) do
      assert Application.get_env(:portfolixir, key) == false, inspect(key)
    end
  end
end
