defmodule Portfolixir.Invariants.TestDatabaseCollationTest do
  # One collation for the test database, on every machine (Sprint 31 plan
  # M3, #1475, S2). The local test databases sorted in C.UTF-8, the
  # PostgreSQL default of the machines the sessions run on, while CI's
  # postgres image created its database in en_US.utf8: the review seed drew
  # its quotes in the database's name order, and a test passed in every
  # local run and failed in every CI run (Sprint 30, review_seed_test.exs's
  # W2; fixed by sorting in Elixir, 9d7d29b). A test database in another
  # collation fails here, before a test can depend on its order.
  #
  # The collation is C.UTF-8 because ecto_sql's Postgres adapter can name
  # it (`lc_collate`, `lc_ctype`, `template` in config/test.exs), so every
  # path that runs `mix ecto.create` under MIX_ENV=test creates the same
  # database: CI's jobs, the SessionStart hook, `scripts/worktree.sh --db`
  # and the scratch databases of test/support/scratch_database.ex. An ICU
  # collation needs `LOCALE_PROVIDER icu`, which the adapter cannot say.
  #
  # A database created before this rule in another collation is recreated:
  #
  #     MIX_ENV=test mix ecto.drop && MIX_ENV=test mix ecto.create && MIX_ENV=test mix ecto.migrate
  use Portfolixir.DataCase, async: true

  @collation "C.UTF-8"

  # PostgreSQL keeps the name it was given; "C.utf8" and "C.UTF-8" name one
  # locale.
  defp same_locale?(name), do: String.downcase(String.replace(name, "-", "")) == "c.utf8"

  test "the running test database sorts and classifies characters in C.UTF-8" do
    %{rows: [[provider, collate, ctype]]} =
      Repo.query!("""
      SELECT datlocprovider::text, datcollate, datctype
      FROM pg_database
      WHERE datname = current_database()
      """)

    database = Repo.config()[:database]

    assert {provider, same_locale?(collate), same_locale?(ctype)} == {"c", true, true},
           "the test database #{database} uses provider #{inspect(provider)}, " <>
             "collation #{inspect(collate)} and ctype #{inspect(ctype)}, not libc " <>
             "#{@collation}; recreate it: MIX_ENV=test mix ecto.drop && " <>
             "MIX_ENV=test mix ecto.create && MIX_ENV=test mix ecto.migrate"
  end

  test "the repo creates the test database in C.UTF-8, from template0" do
    config = Repo.config()

    # template1 carries the cluster's default collation, and PostgreSQL
    # refuses another one for a copy of it; template0 takes any.
    assert {config[:lc_collate], config[:lc_ctype], config[:template]} ==
             {@collation, @collation, "template0"}
  end

  test "CI creates its test database through mix ecto.create, not the image's" do
    # A service whose POSTGRES_DB names the test database creates it in the
    # image's default collation, and `mix ecto.create` then finds it there.
    ci = File.read!(".github/workflows/ci.yml")

    refute Regex.match?(~r/POSTGRES_DB:\s*portfolixir_test\b/, ci),
           "a CI service creates portfolixir_test in the image's collation (POSTGRES_DB)"

    assert ci =~ "MIX_ENV=test mix ecto.create"
  end
end
