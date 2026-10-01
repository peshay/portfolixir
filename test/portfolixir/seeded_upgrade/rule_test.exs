defmodule Portfolixir.SeededUpgrade.RuleTest do
  # The seeded-upgrade rule (Sprint 17, Lane G-1, #995): a migration newer
  # than the harness that adds a CHECK, a NOT NULL or a backfill ships with a
  # seeded case. Tagged :seeded_upgrade so the migration-roundtrip job, which
  # runs the cases, enforces it too; it reads source files only.
  use ExUnit.Case, async: true

  alias Portfolixir.SeededUpgrade.Rule

  @moduletag :seeded_upgrade

  # User story:
  # As the operator upgrading a self-hosted instance,
  # I want every new migration that can trip over the rows my instance holds
  # to have been run over such rows before it ships,
  # so that a release does not stop at boot on data a database migrated from
  # empty never had.
  #
  # Acceptance criteria:
  # - A migration newer than the rule's cutoff that adds a CHECK, a NOT NULL
  #   or a backfill and that no `seeded_upgrade:` tag names fails this test,
  #   which names the migration, what it adds and how to add its case.
  # - Migrations up to the cutoff are not listed anywhere; they are older
  #   than the rule.
  test "every migration since the rule that adds a CHECK, a NOT NULL or a backfill has a seeded case" do
    case Rule.uncovered() do
      [] -> :ok
      uncovered -> flunk(Rule.explain(uncovered))
    end
  end

  test "the cutoff is a migration, so it cannot exempt one by a typo" do
    assert List.keymember?(Rule.migration_files(), Rule.since(), 0)
  end

  test "Sprint 16's two seeded cases are read from their tags" do
    covered = Rule.covered_versions()

    assert 20_260_925_130_000 in covered
    assert 20_260_926_121_500 in covered
  end

  test "the heuristic sees Sprint 16's two catches in the shipped migrations" do
    assert :check in changes_of(20_260_925_130_000)
    assert changes_of(20_260_926_121_500) == [:check, :backfill]
  end

  test "the message names the migration, what it adds and the version to seed at" do
    message = Rule.explain([{20_260_926_121_500, "20260926121500_add_author.exs", [:backfill]}])

    assert message =~ "priv/repo/migrations/20260926121500_add_author.exs -- adds a backfill"
    assert message =~ "seed at 20260926121400, the migration before it"
    assert message =~ "@tag seeded_upgrade: <the migration's version>"
    assert message =~ "Portfolixir.SeededUpgrade.upgrade!"
  end

  describe "the heuristic" do
    test "a CHECK on an existing table, in Ecto or in SQL, is one" do
      assert Rule.changes(migration("create constraint(:t, :c, check: \"x > 0\")")) == [:check]

      assert Rule.changes(migration(~s|execute("ALTER TABLE t ADD CONSTRAINT c CHECK (x > 0)")|)) ==
               [:check]

      assert Rule.changes(migration(~s|repo().query!("ALTER TABLE t VALIDATE CONSTRAINT c")|)) ==
               [:check]
    end

    test "a NOT NULL on an existing table, in Ecto or in SQL, is one" do
      assert Rule.changes(migration("alter table(:t) do\nadd :c, :string, null: false\nend")) ==
               [:not_null]

      assert Rule.changes(migration("alter table(:t) do\nmodify :c, :string, null: false\nend")) ==
               [:not_null]

      assert Rule.changes(migration(~s|execute("ALTER TABLE t ALTER COLUMN c SET NOT NULL")|)) ==
               [:not_null]

      assert Rule.changes(migration(~s|execute("ALTER TABLE t ADD COLUMN c text NOT NULL")|)) ==
               [:not_null]
    end

    test "a backfill, in SQL, through a repo or through application code, is one" do
      for body <- [
            ~s|execute("UPDATE accounts SET former_names = '{}'")|,
            ~s|execute("UPDATE ONLY accounts AS a SET x = 1")|,
            ~s|execute("INSERT INTO buckets (name) SELECT name FROM portfolios")|,
            "repo().update_all(\"t\", set: [x: 1])",
            "repo().insert_all(\"t\", [%{x: 1}])",
            "Portfolixir.Repo.update_all(\"t\", set: [x: 1])",
            "Portfolixir.Tax.seed_builtin_parameters(repo())",
            "alias Portfolixir.Portfolios.Backfill\nBackfill.run()",
            "alias Portfolixir.Portfolios.{Backfill}\nBackfill.run()",
            "alias Portfolixir.Portfolios.Backfill, as: Fill\nFill.run()"
          ] do
        assert Rule.changes(migration(body)) == [:backfill], body
      end
    end

    test "a new table's own constraints, a read and documentation are none" do
      for body <- [
            "create table(:t) do\nadd :c, :string, null: false\nend\n" <>
              "create constraint(:t, :c, check: \"c <> ''\")",
            "create table(:t) do\nadd :c, :string\nend\n" <>
              "alter table(:t) do\nmodify :c, :string, null: false\nend",
            "alter table(:t) do\nadd :c, :string\nend",
            ~s|repo().query!("SELECT count(*) FROM t WHERE x IS NULL")|,
            ~s|execute("CREATE TRIGGER t_guard BEFORE UPDATE ON t FOR EACH ROW EXECUTE FUNCTION f()")|,
            "Logger.warning(\"the kind check (ADR-0050) found a row\")",
            "Map.update(%{}, :a, 1, & &1)",
            "Portfolixir.Repo.query!(\"SELECT 1\")"
          ] do
        assert Rule.changes(migration(body)) == [], body
      end

      documented = """
      defmodule Portfolixir.Repo.Migrations.Documented do
        @moduledoc "Adds CHECK (x > 0) and runs UPDATE t SET x = 1 -- in prose only."
        use Ecto.Migration

        @doc "INSERT INTO t SELECT 1, in prose only."
        def up, do: execute("CREATE INDEX t_x_index ON t (x)")
      end
      """

      assert Rule.changes(documented) == []
    end
  end

  defp changes_of(version) do
    {^version, file} = List.keyfind(Rule.migration_files(), version, 0)
    file |> File.read!() |> Rule.changes()
  end

  defp migration(body) do
    """
    defmodule Portfolixir.Repo.Migrations.Synthetic do
      use Ecto.Migration

      def up do
        #{body}
      end
    end
    """
  end
end
