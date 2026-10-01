defmodule Portfolixir.DevConfigTest do
  # Closing-act finding UAT-15: config/test.exs read DATABASE_PORT, but
  # config/dev.exs set no Repo port, so the plan's walkthrough recipe
  # ("DATABASE_PORT=5433 … MIX_ENV=dev mix ecto.create/migrate/phx.server")
  # created its database on one server and migrated against whatever listened
  # on 5432 — a different PostgreSQL than the one the plan requires.
  #
  # async: false — the test sets DATABASE_PORT in the VM's environment.
  use ExUnit.Case, async: false

  # User story (closing-act finding UAT-15):
  # As a maintainer running a walkthrough instance against the PostgreSQL 18
  # server CI and Compose run,
  # I want the development configuration to honour DATABASE_PORT as the test
  # configuration does,
  # so that every mix task of the recipe talks to the server I named.
  #
  # Acceptance criteria:
  # - With DATABASE_PORT set, config/dev.exs gives the Repo that port.
  # - Unset, the Repo keeps PostgreSQL's default port 5432.
  test "the development Repo takes its port from DATABASE_PORT" do
    previous = System.get_env("DATABASE_PORT")

    try do
      System.put_env("DATABASE_PORT", "5433")
      assert repo_port() == 5433

      System.delete_env("DATABASE_PORT")
      assert repo_port() == 5432
    after
      if previous,
        do: System.put_env("DATABASE_PORT", previous),
        else: System.delete_env("DATABASE_PORT")
    end
  end

  # User story (#961):
  # As a contributor pointing a development or review instance at a
  # PostgreSQL other than the one on 127.0.0.1:5432,
  # I want the development guide and the review seed's header to name the
  # variables the development configuration reads,
  # so that I find DATABASE_PORT where I look for the recipe rather than only
  # in config/dev.exs.
  #
  # Acceptance criteria:
  # - docs/development/guide.md names every environment variable
  #   config/dev.exs reads.
  # - The header of priv/demo/finding_surfaces_seed.exs names the database
  #   variables and the HTTP port its recipe takes.
  test "the development guide and the seed header name the dev variables" do
    read_by_dev =
      ~r/"([A-Z][A-Z0-9_]+)"/
      |> Regex.scan(File.read!("config/dev.exs"), capture: :all_but_first)
      |> List.flatten()
      |> Enum.uniq()

    assert "DATABASE_PORT" in read_by_dev

    guide = File.read!("docs/development/guide.md")

    for name <- read_by_dev do
      assert guide =~ "`#{name}`", "the development guide does not name #{name}"
    end

    header =
      "priv/demo/finding_surfaces_seed.exs"
      |> File.read!()
      |> String.split("\n")
      |> Enum.take_while(&String.starts_with?(&1, "#"))
      |> Enum.join("\n")

    for name <- ~w(DATABASE_NAME DATABASE_HOST DATABASE_PORT PORT) do
      assert header =~ "`#{name}`", "the seed header does not name #{name}"
    end
  end

  # User story (#963):
  # As a reviewer seeding a throwaway walkthrough database,
  # I want a seed run to leave logo discovery and the quote and FX sync off,
  # while `mix phx.server` in development keeps them on,
  # so that the seeded instance does not vary with provider availability and
  # no demo name leaves the machine without my choosing to send it.
  #
  # Acceptance criteria:
  # - With PORTFOLIXIR_BACKGROUND_FETCH=off, config/dev.exs turns logo
  #   discovery, the quote sync and the FX sync off.
  # - Unset, all three stay on, as before.
  # - Every documented `mix run priv/demo/...` command sets the switch.
  test "the background-fetch switch turns logo discovery and the quote and FX sync off" do
    previous = System.get_env("PORTFOLIXIR_BACKGROUND_FETCH")

    try do
      System.put_env("PORTFOLIXIR_BACKGROUND_FETCH", "off")
      assert background_fetch() == %{logos: false, quotes: false, fx: false}

      System.delete_env("PORTFOLIXIR_BACKGROUND_FETCH")
      assert background_fetch() == %{logos: true, quotes: true, fx: true}
    after
      if previous,
        do: System.put_env("PORTFOLIXIR_BACKGROUND_FETCH", previous),
        else: System.delete_env("PORTFOLIXIR_BACKGROUND_FETCH")
    end

    documented =
      for path <- [
            "priv/demo/README.md",
            "priv/demo/finding_surfaces_seed.exs",
            "priv/demo/quotes_seed.exs",
            "priv/demo/strategies_seed.exs",
            "_bmad-output/planning-artifacts/design-language/review-rubric.md"
          ],
          line <- path |> File.read!() |> String.split("\n"),
          line =~ "mix run priv/demo/",
          do: {path, line}

    assert length(documented) >= 5

    for {path, line} <- documented do
      assert line =~ "PORTFOLIXIR_BACKGROUND_FETCH=off ", "#{path}: #{line}"
    end
  end

  defp background_fetch do
    config = dev_config()

    %{
      logos: Keyword.fetch!(config, :enable_logo_discovery),
      quotes:
        config |> Keyword.fetch!(Portfolixir.Catalog.QuoteSync) |> Keyword.fetch!(:enabled?),
      fx: config |> Keyword.fetch!(Portfolixir.Fx.RateSync) |> Keyword.fetch!(:enabled?)
    }
  end

  defp repo_port do
    dev_config()
    |> Keyword.fetch!(Portfolixir.Repo)
    |> Keyword.fetch!(:port)
  end

  defp dev_config do
    "config/dev.exs"
    |> Config.Reader.read!(env: :dev, target: :host)
    |> Keyword.fetch!(:portfolixir)
  end
end
