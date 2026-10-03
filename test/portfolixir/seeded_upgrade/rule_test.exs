defmodule Portfolixir.SeededUpgrade.RuleTest do
  # The seeded-upgrade rule (Sprint 17, Lane G-1, #995; widened by #1016): a
  # migration newer than the harness that adds a CHECK, a NOT NULL, a
  # backfill, a UNIQUE index, a foreign key or an exclusion constraint ships
  # with a seeded case. Tagged :seeded_upgrade so the migration-roundtrip job, which
  # runs the cases, enforces it too; it reads source files only.
  use ExUnit.Case, async: true

  alias Portfolixir.ScratchDatabase
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
  test "every migration since the rule that can trip over a legacy row has a seeded case" do
    case Rule.uncovered() do
      [] -> :ok
      uncovered -> flunk(Rule.explain(uncovered))
    end
  end

  test "the cutoff is a migration, so it cannot exempt one by a typo" do
    assert List.keymember?(ScratchDatabase.migration_files(), Rule.since(), 0)
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

    # The two places the message sends a reader exist.
    assert message =~ ~s|docs/development/guide.md ("Upgrade migrations over legacy rows")|
    assert File.read!("docs/development/guide.md") =~ "\n## Upgrade migrations over legacy rows\n"
    assert File.exists?("test/portfolixir/seeded_upgrade/sprint16_test.exs")
  end

  describe "the heuristic" do
    test "a CHECK on an existing table, in Ecto or in SQL, is one" do
      assert Rule.changes(migration("create constraint(:t, :c, check: \"x > 0\")")) == [:check]

      assert Rule.changes(migration(~s|execute("ALTER TABLE t ADD CONSTRAINT c CHECK (x > 0)")|)) ==
               [:check]

      assert Rule.changes(migration(~s|repo().query!("ALTER TABLE t VALIDATE CONSTRAINT c")|)) ==
               [:check]

      # A table named by a string or by an expression is still a table the
      # migration did not create.
      assert Rule.changes(migration(~s|create constraint("t", :c, check: "x > 0")|)) == [:check]

      assert Rule.changes(migration(~s|create constraint(@table, :c, check: "x > 0")|)) == [
               :check
             ]
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

      # timestamps/1 adds two columns Ecto makes NOT NULL unless told otherwise.
      for body <- ["timestamps()", "timestamps(type: :utc_datetime_usec)", "timestamps(opts)"] do
        assert Rule.changes(migration("alter table(:t) do\n#{body}\nend")) == [:not_null], body
      end

      # SQL with an interpolated table or column name is read as one text.
      assert Rule.changes(
               migration(~S|execute("ALTER TABLE #{@table} ADD COLUMN #{column} text NOT NULL")|)
             ) == [:not_null]
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
            "alias Portfolixir.Portfolios.Backfill, as: Fill\nFill.run()",
            "alias Portfolixir.Repo\nRepo.update_all(\"t\", set: [x: 1])"
          ] do
        assert Rule.changes(migration(body)) == [:backfill], body
      end
    end

    test "SQL built by interpolation or concatenation is read as one text" do
      for body <- [
            ~S|repo().query!("UPDATE #{table} SET #{column} = round(#{column}, 6) WHERE #{column} IS NOT NULL")|,
            "execute(\"\"\"\nUPDATE \#{@table}\n   SET former_names = '{}'\n\"\"\")",
            ~S|execute("INSERT INTO #{table} (name) SELECT name FROM portfolios")|,
            ~S|execute("UPDATE " <> table <> " SET x = 1")|,
            ~S|execute("UPDATE " <> "#{table}" <> " SET x = 1")|
          ] do
        assert Rule.changes(migration(body)) == [:backfill], body
      end

      for body <- [
            ~S|repo().query!("SELECT count(*) FROM #{table} WHERE #{column} IS NULL")|,
            ~S|Logger.warning("updated #{count} rows; set the #{name} by hand")|,
            ~S|"prefix_" <> name|
          ] do
        assert Rule.changes(migration(body)) == [], body
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
            "Portfolixir.Repo.query!(\"SELECT 1\")",
            "alias Portfolixir.Repo\nRepo.query!(\"SELECT 1\")",
            "alias Ecto.{Changeset, Multi}\nMulti.new()",
            ~s|create table("t") do\nadd :c, :string\nend\ncreate constraint("t", :c, check: "c <> ''")|,
            "# CHECK (x > 0), then UPDATE t SET x = 1 -- a comment only\n:ok",
            "alter table(:t) do\ntimestamps(null: true)\nend",
            "create table(:t) do\nadd :c, :string\ntimestamps()\nend"
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

  # User story (#1016, decided by the Sprint 18 plan's D-7):
  # As the operator upgrading a self-hosted instance,
  # I want a migration that adds a UNIQUE index, a foreign key or an
  # exclusion constraint to a table my instance already fills to have run
  # over such rows before it ships,
  # so that a legacy duplicate or orphan never stops a release at boot unseen.
  #
  # Acceptance criteria:
  # - On a table the migration does not create, each counts: a UNIQUE index
  #   (`unique_index/3`, `index/3` with `unique: true`, SQL `CREATE UNIQUE
  #   INDEX`, `ADD CONSTRAINT ... UNIQUE`), a foreign key (`references/2` in
  #   `alter table`, SQL `FOREIGN KEY`, `ADD COLUMN ... REFERENCES`) and an
  #   exclusion constraint (`constraint/3` with `exclude:`, SQL `EXCLUDE
  #   USING`).
  # - Built CONCURRENTLY or behind a cleanup step, it still counts: the
  #   cleanup is what the case proves.
  # - The same on a table the migration creates, and a plain index, are none.
  describe "the heuristic, widened (#1016)" do
    test "a UNIQUE index on an existing table, in Ecto or in SQL, is one" do
      for body <- [
            "create unique_index(:t, [:a, :b])",
            "create_if_not_exists unique_index(:t, [:a], where: \"a IS NOT NULL\")",
            "create unique_index(:t, [:a], concurrently: true)",
            "create index(:t, [:a], unique: true)",
            ~s|execute("CREATE UNIQUE INDEX t_a_index ON t (a)")|,
            ~s|execute("CREATE UNIQUE INDEX CONCURRENTLY t_a_index ON t (a)")|,
            ~s|execute("ALTER TABLE t ADD CONSTRAINT t_a_key UNIQUE (a)")|,
            ~S|repo().query!("CREATE UNIQUE INDEX #{@index} ON t (a) WHERE a IS NOT NULL")|
          ] do
        assert Rule.changes(migration(body)) == [:unique], body
      end
    end

    test "a cleanup ahead of the index does not exempt it" do
      body =
        ~s|execute("DELETE FROM t WHERE id NOT IN (SELECT min(id) FROM t GROUP BY a)")\n| <>
          "create unique_index(:t, [:a])"

      assert Rule.changes(migration(body)) == [:unique]
    end

    test "a foreign key on an existing table, in Ecto or in SQL, is one" do
      for body <- [
            "alter table(:t) do\nadd :owner_id, references(:owners)\nend",
            "alter table(:t) do\nmodify :owner_id, references(:owners, on_delete: :restrict)\nend",
            ~s|execute("ALTER TABLE t ADD CONSTRAINT t_owner_fkey FOREIGN KEY (owner_id) REFERENCES owners (id)")|,
            ~s|execute("ALTER TABLE t ADD COLUMN owner_id bigint REFERENCES owners (id)")|
          ] do
        assert Rule.changes(migration(body)) == [:foreign_key], body
      end
    end

    test "an exclusion constraint on an existing table, in Ecto or in SQL, is one" do
      for body <- [
            ~s|create constraint(:t, :t_no_overlap, exclude: ~s"gist (a WITH =, period WITH &&)")|,
            ~s|execute("ALTER TABLE t ADD CONSTRAINT t_no_overlap EXCLUDE USING gist (a WITH =)")|
          ] do
        assert Rule.changes(migration(body)) == [:exclusion], body
      end
    end

    test "a new table's own UNIQUE index, foreign key and exclusion constraint are none" do
      for body <- [
            "create table(:t) do\nadd :a, :string\nend\ncreate unique_index(:t, [:a])",
            "create table(:t) do\nadd :a, :string\nend\ncreate index(:t, [:a], unique: true)",
            "create table(:t) do\nadd :owner_id, references(:owners)\nend",
            "create table(:t) do\nadd :a, :string\nend\n" <>
              "alter table(:t) do\nadd :owner_id, references(:owners)\nend",
            "create table(:t) do\nadd :a, :string\nend\n" <>
              ~s|create constraint(:t, :t_no_overlap, exclude: ~s"gist (a WITH =)")|,
            "create index(:t, [:a])",
            "create index(:t, [:a], concurrently: true)",
            "drop unique_index(:t, [:a])",
            ~s|execute("DROP INDEX IF EXISTS t_a_index")|
          ] do
        assert Rule.changes(migration(body)) == [], body
      end
    end

    test "the heuristic sees the UNIQUE index the decision names" do
      # D-7 (#1016): the example the rule did not see. It is older than the
      # cutoff, so the rule lists it nowhere; its refusal of legacy duplicates
      # is pinned by its own test (position_target_unique_test.exs).
      assert changes_of(20_260_925_210_000) == [:unique]
    end

    test "the message names what each new kind adds" do
      message =
        Rule.explain([
          {20_260_926_121_500, "20260926121500_add_author.exs",
           [:unique, :foreign_key, :exclusion]}
        ])

      assert message =~
               "20260926121500_add_author.exs -- adds a UNIQUE index and a foreign key and " <>
                 "an exclusion constraint"

      assert String.replace(message, ~r/\s+/, " ") =~
               "a UNIQUE index, a foreign key or an exclusion constraint"
    end
  end

  # #1022: a tag named in a comment is no seeded case.
  test "a seeded_upgrade tag inside a comment covers nothing" do
    dir = Path.join(System.tmp_dir!(), "rule-comment-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    File.write!(Path.join(dir, "commented_test.exs"), """
    # @tag seeded_upgrade: 20_990_101_000_007
    @tag seeded_upgrade: [20_990_101_000_008]
    test "covers one" do
      # once tagged seeded_upgrade: 20_990_101_000_009
      :ok
    end
    """)

    assert Rule.covered_versions(Path.join(dir, "*_test.exs")) == MapSet.new([20_990_101_000_008])
  end

  describe "the rule over a migrations directory of its own" do
    setup do
      dir =
        Path.join(System.tmp_dir!(), "seeded-upgrade-rule-#{System.unique_integer([:positive])}")

      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)

      for {file, body} <- [
            {"20990101000001_create_rule_widgets.exs",
             "create table(:rule_widgets) do\nadd :size, :integer, null: false\nend"},
            {"20990101000002_bound_rule_widgets.exs",
             "create constraint(:rule_widgets, :size_check, check: \"size > 0\")\n" <>
               "alter table(:rule_widgets) do\nmodify :size, :integer, null: false\nend"},
            {"20990101000003_fill_rule_widgets.exs",
             ~s|execute("UPDATE rule_widgets SET size = 1 WHERE size IS NULL")|},
            {"20990101000004_index_rule_widgets.exs", "create index(:rule_widgets, [:size])"}
          ] do
        File.write!(Path.join(dir, file), migration(body))
      end

      # A seeded case's tag in the list form, naming the backfill.
      File.mkdir_p!(Path.join(dir, "test"))

      File.write!(
        Path.join(dir, "test/rule_widgets_test.exs"),
        "@tag seeded_upgrade: [20_990_101_000_003]\ntest \"fills the widgets\""
      )

      %{dir: dir}
    end

    test "it lists each newer risky migration no tag names, and nothing else", %{dir: dir} do
      opts = [
        migrations: dir,
        since: 20_990_101_000_001,
        tests: Path.join(dir, "test/*_test.exs")
      ]

      assert Rule.covered_versions(Path.join(dir, "test/*_test.exs")) ==
               MapSet.new([20_990_101_000_003])

      assert [{20_990_101_000_002, "20990101000002_bound_rule_widgets.exs", [:check, :not_null]}] =
               uncovered = Rule.uncovered(opts)

      message = Rule.explain(uncovered, dir)

      assert message =~
               "#{dir}/20990101000002_bound_rule_widgets.exs -- adds a CHECK and a NOT NULL; " <>
                 "seed at 20990101000001, the migration before it"

      # Older than the cutoff, the same migrations are not listed.
      assert Rule.uncovered(Keyword.put(opts, :since, 20_990_101_000_004)) == []
    end

    test "the first migration of a directory is seeded on an empty database", %{dir: dir} do
      message =
        Rule.explain(
          [{20_990_101_000_001, "20990101000001_create_rule_widgets.exs", [:check]}],
          dir
        )

      assert message =~ "adds a CHECK; seed an empty database, as it is the first migration"
    end
  end

  defp changes_of(version) do
    {^version, file} = List.keyfind(ScratchDatabase.migration_files(), version, 0)
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
