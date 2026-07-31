defmodule Portfolixir.Tax.SeedTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Tax

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

    {:ok, summary} = Tax.seed_builtin_parameters(Actor.system_job("tax_parameters_seed"))

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

    {:ok, _summary} = Tax.seed_builtin_parameters(Actor.system_job("tax_parameters_seed"))

    {:ok, after_seed} = Tax.fetch_parameters("DE", 2024)
    assert after_seed.id == edited.id
    assert Decimal.equal?(after_seed.saver_allowance_single, Decimal.new("1234.00"))
  end

  test "the rollback removes only built-in rows" do
    {:ok, operator_row} =
      Tax.upsert_parameters(Actor.owner_ui(), %{
        jurisdiction: "DE",
        tax_year: 2027,
        capital_gains_tax_rate: Decimal.new("0.25"),
        solidarity_surcharge_rate: Decimal.new("0.055"),
        saver_allowance_single: Decimal.new("1100.00"),
        saver_allowance_joint: Decimal.new("2200.00")
      })

    :ok = Tax.rollback_builtin_parameters(Actor.system_job("tax_parameters_seed"))

    remaining = Tax.list_parameters(jurisdiction: "DE")
    assert Enum.map(remaining, & &1.id) == [operator_row.id]
    refute Enum.any?(remaining, & &1.built_in)
  end

  test "seeding into an empty table writes the full German history, journaled" do
    :ok = Tax.rollback_builtin_parameters(Actor.system_job("tax_parameters_seed"))
    assert Tax.list_parameters(jurisdiction: "DE") == []

    creates_before = create_entry_count()

    {:ok, summary} = Tax.seed_builtin_parameters(Actor.system_job("tax_parameters_seed"))

    assert summary.inserted == 2026 - 2009 + 1
    assert summary.skipped == 0
    assert create_entry_count() - creates_before == summary.inserted
  end

  defp create_entry_count do
    Journal.list_entries(
      resource_type: "tax_parameters",
      actor_type: "system_job",
      operation: :create
    )
    |> length()
  end
end
