defmodule Portfolixir.MixProject do
  use Mix.Project

  def project do
    [
      app: :portfolixir,
      version: "0.1.0",
      # The floor the code, the suite and the dev tooling need (#1132): the
      # suite's async modules share ExUnit groups (`group:`), which exist from
      # 1.18 on; `Date.shift/2` and yaml_elixir (under mix_audit) need 1.17.
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      licenses: ["MIT"],
      test_coverage: [tool: ExCoveralls],
      dialyzer: [
        plt_local_path: "priv/plts",
        plt_core_path: "priv/plts",
        # `:mix` is in the PLT for the Mix task(s) under lib/mix/tasks
        # (fix round: mix portfolixir.seed_scope_buckets).
        plt_add_apps: [:mix]
      ],
      aliases: aliases(),
      deps: deps()
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test,
        "coveralls.json": :test,
        "coveralls.lcov": :test,
        "coveralls.post": :test
      ]
    ]
  end

  def application do
    [
      mod: {Portfolixir.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.8.9"},
      {:phoenix_ecto, "~> 4.6"},
      {:gettext, "~> 1.0"},
      {:ecto_sql, "~> 3.12"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.2"},
      {:excoveralls, "~> 0.18", only: :test, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.18", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.3", only: [:test], runtime: false},
      {:floki, ">= 0.36.0", only: :test},
      # LiveView 1.x parses the test DOM with lazy_html instead of Floki.
      {:lazy_html, ">= 0.1.0", only: :test},
      {:jason, "~> 1.4"},
      {:nimble_csv, "~> 1.2"},
      # Every money figure runs on Decimal directly (ADR-0003), so it is
      # declared here rather than reached through Ecto alone: a declared
      # dependency is one Dependabot can move when an advisory names it
      # (2026-10-12 security review, H28).
      {:decimal, "~> 3.1.2"},
      # Phoenix 1.8's default HTTP server (#772, Sprint 11 Lane D): Bandit
      # replaced plug_cowboy, which took cowlib and its unfixed advisories
      # out of the tree.
      {:bandit, "~> 1.12"},
      {:req, "~> 0.5"},
      # The news feed parser's XML reader (ADR-0056 A1, Sprint 27 plan D-7):
      # SAX mode, no atom from a name, no DTD processed, and a handler that
      # stops at the first breach. Pinned exactly: a hostile-input surface
      # moves only through the maintenance lane's audit.
      {:saxy, "== 1.7.0"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      "deps.get": [&__MODULE__.own_deps/1, "deps.get"],
      "deps.update": [&__MODULE__.own_deps/1, "deps.update"],
      "deps.clean": [&__MODULE__.own_deps/1, "deps.clean"]
    ]
  end

  # A worktree from scripts/worktree.sh links `deps` to the main checkout's
  # when their mix.lock files agree. Before a task writes into `deps`, the
  # link becomes a copy of its own (`scripts/worktree.sh own`), so a fetch
  # for a lock the worktree changed cannot change the main checkout's
  # dependencies (Sprint 31 M4, Sprint 30 retrospective carry-forward 9).
  # Where `deps` is a directory, as in the main checkout, CI and the images,
  # it does nothing. test/invariants/worktree_deps_guard_test.exs pins the
  # aliases.
  #
  # The paths are literal, relative to the project root Mix runs in, as the
  # one subprocess test/invariants/scope_b2_outbound_chokepoint_test.exs
  # registers for this module. The script copies with `cp -a`, which keeps
  # the modification times Mix's compile checks read.
  @doc false
  def own_deps(_args) do
    case File.lstat("deps") do
      {:ok, %File.Stat{type: :symlink}} ->
        case System.cmd("bash", ["scripts/worktree.sh", "own", "deps"], stderr_to_stdout: true) do
          {output, 0} -> Mix.shell().info(String.trim_trailing(output))
          {output, _} -> Mix.raise("scripts/worktree.sh could not copy deps:\n" <> output)
        end

      _ ->
        :ok
    end
  end
end
