defmodule Portfolixir.Tax.SeedTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Tax

  @seed_actor Actor.system_job("tax_parameters_seed")

  # User story (2026-07-25, ADR-0031, story 19.2):
  # As a local portfolio maintainer,
  # I want the German statutory history to be there without typing it,
  # so that recording an older statement validates against that year's law.
  #
  # Acceptance criteria:
  # - AC-7: the seed is idempotent, reversible and never overwrites a value the
  #   operator has edited.
  # - The rollback is marker-scoped: rows the operator created survive.

  test "re-running the seed inserts nothing and writes no journal noise" do
    before_rows = Tax.list_parameters(jurisdiction: "DE")
    before_entries = Journal.list_entries(resource_type: "tax_parameters")

    {:ok, summary} = Tax.seed_builtin_parameters(@seed_actor)

    assert summary.inserted == 0
    assert summary.skipped == length(before_rows)

    assert Enum.map(Tax.list_parameters(jurisdiction: "DE"), & &1.id) ==
             Enum.map(before_rows, & &1.id)

    assert length(Journal.list_entries(resource_type: "tax_parameters")) ==
             length(before_entries)
  end

  test "a re-run never overwrites an operator-edited value" do
    {:ok, seeded} = Tax.fetch_parameters("DE", 2024)

    {:ok, edited} =
      Tax.upsert_parameters(Actor.owner_ui(), %{
        jurisdiction: "DE",
        tax_year: 2024,
        capital_gains_tax_rate: seeded.capital_gains_tax_rate,
        solidarity_surcharge_rate: seeded.solidarity_surcharge_rate,
        saver_allowance_single: Decimal.new("1234.00"),
        saver_allowance_joint: Decimal.new("2468.00")
      })

    {:ok, _summary} = Tax.seed_builtin_parameters(@seed_actor)

    {:ok, after_seed} = Tax.fetch_parameters("DE", 2024)
    assert after_seed.id == edited.id
    assert Decimal.equal?(after_seed.saver_allowance_single, Decimal.new("1234.00"))
  end

  test "the rollback removes only built-in rows, each journaled" do
    {:ok, operator_row} =
      Tax.upsert_parameters(Actor.owner_ui(), %{
        jurisdiction: "DE",
        tax_year: 2027,
        capital_gains_tax_rate: Decimal.new("0.25"),
        solidarity_surcharge_rate: Decimal.new("0.055"),
        saver_allowance_single: Decimal.new("1100.00"),
        saver_allowance_joint: Decimal.new("2200.00")
      })

    built_in = Enum.count(Tax.list_parameters(jurisdiction: "DE"), & &1.built_in)
    deletes_before = seed_entry_count(:delete)

    :ok = Tax.rollback_builtin_parameters(@seed_actor)

    remaining = Tax.list_parameters(jurisdiction: "DE")
    assert Enum.map(remaining, & &1.id) == [operator_row.id]
    refute Enum.any?(remaining, & &1.built_in)
    assert seed_entry_count(:delete) - deletes_before == built_in
  end

  test "seeding into an empty table writes the full German history, journaled" do
    :ok = Tax.rollback_builtin_parameters(@seed_actor)
    assert Tax.list_parameters(jurisdiction: "DE") == []

    creates_before = seed_entry_count(:create)

    {:ok, summary} = Tax.seed_builtin_parameters(@seed_actor)

    assert summary.inserted == 2026 - 2009 + 1
    assert summary.skipped == 0
    assert seed_entry_count(:create) - creates_before == summary.inserted

    {:ok, y2022} = Tax.fetch_parameters("DE", 2022)
    {:ok, y2023} = Tax.fetch_parameters("DE", 2023)
    assert y2022.built_in and y2023.built_in
    assert Decimal.equal?(y2022.saver_allowance_single, Decimal.new("801.00"))
    assert Decimal.equal?(y2022.saver_allowance_joint, Decimal.new("1602.00"))
    assert Decimal.equal?(y2023.saver_allowance_single, Decimal.new("1000.00"))
    assert Decimal.equal?(y2023.saver_allowance_joint, Decimal.new("2000.00"))
    assert Decimal.equal?(y2023.capital_gains_tax_rate, Decimal.new("0.25"))
    assert Decimal.equal?(y2023.solidarity_surcharge_rate, Decimal.new("0.055"))
    assert Enum.map(y2023.church_tax_rates, &Decimal.to_string(&1, :normal)) == ~w(0.08 0.09)
  end

  # User story (#1015, Sprint 18 C3):
  # As the operator installing a fresh instance, or upgrading one from before
  # the tax seed,
  # I want the seed its migration calls to run against the schema that
  # migration had,
  # so that a column a later migration adds to the journal or to the tax
  # tables never stops the install at this migration.
  #
  # Acceptance criteria:
  # - The code the immutable migration calls names no schema and no journal
  #   module: its data, its columns and its journal write are frozen into
  #   `Portfolixir.Tax.BuiltinSeed`.
  # - Each seeded row's journal entry carries the seed's system job and the
  #   row's snapshot as the journal's serializer writes one: every column of
  #   the row at that version, decimals as strings, timestamps in ISO 8601.
  test "the seed the migration calls names no schema and no journal module" do
    assert File.read!("priv/repo/migrations/20260725140000_seed_tax_parameters.exs") =~
             "Tax.seed_builtin_parameters(seed_actor())"

    assert application_modules(File.read!("lib/portfolixir/tax/builtin_seed.ex")) == [
             [:Portfolixir, :Actor],
             [:Portfolixir, :Tax, :BuiltinSeed]
           ]
  end

  test "each seeded row's journal entry is the snapshot the journal writes" do
    :ok = Tax.rollback_builtin_parameters(@seed_actor)
    {:ok, _summary} = Tax.seed_builtin_parameters(@seed_actor)

    {:ok, row} = Tax.fetch_parameters("DE", 2023)

    [entry] =
      Journal.list_entries(
        resource_type: "tax_parameters",
        resource_id: Integer.to_string(row.id),
        operation: :create
      )

    assert entry.actor_type == :system_job
    assert entry.actor_label == "tax_parameters_seed"
    assert entry.before == nil

    assert entry.after == %{
             "id" => row.id,
             "jurisdiction" => "DE",
             "tax_year" => 2023,
             "capital_gains_tax_rate" => "0.25",
             "solidarity_surcharge_rate" => "0.055",
             "saver_allowance_single" => "1000.00",
             "saver_allowance_joint" => "2000.00",
             "church_tax_rates" => ["0.08", "0.09"],
             "built_in" => true,
             "inserted_at" => NaiveDateTime.to_iso8601(row.inserted_at),
             "updated_at" => NaiveDateTime.to_iso8601(row.updated_at)
           }
  end

  defp seed_entry_count(operation) do
    Journal.list_entries(
      resource_type: "tax_parameters",
      actor_type: "system_job",
      operation: operation
    )
    |> length()
  end

  # Every `Portfolixir.*` module the source names, the repo excepted.
  defp application_modules(source) do
    {_ast, modules} =
      source
      |> Code.string_to_quoted!()
      |> Macro.prewalk([], fn
        {:__aliases__, _meta, [:Portfolixir | rest] = parts} = node, acc ->
          if match?([:Repo | _], rest), do: {node, acc}, else: {node, [parts | acc]}

        node, acc ->
          {node, acc}
      end)

    modules |> Enum.uniq() |> Enum.sort()
  end
end
