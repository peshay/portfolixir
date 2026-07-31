defmodule Portfolixir.Tax.ParametersTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Tax

  # User story (2026-07-25, ADR-0031, story 19.2):
  # As a local portfolio maintainer,
  # I want the statutory numbers to be year-scoped data rather than constants
  # in the code,
  # so that a statement from an earlier year still validates correctly.
  #
  # Acceptance criteria:
  # - AC-1: the consistency engine receives the year's rates and
  #   Sparer-Pauschbetrag ceilings as data — 801/1602 € up to 2022,
  #   1000/2000 € from 2023.
  # - AC-6: every parameter write is journaled; a raw write raises.
  # - AC-7: the German history is seeded and survives the suite.
  # - AC-8: an unseeded year fails loudly, never falls back.

  test "the seeded German history resolves the ceiling in force for the year" do
    {:ok, before_2023} = Tax.fetch_parameters("DE", 2022)
    {:ok, from_2023} = Tax.fetch_parameters("DE", 2023)

    assert Decimal.equal?(before_2023.saver_allowance_single, Decimal.new("801.00"))
    assert Decimal.equal?(before_2023.saver_allowance_joint, Decimal.new("1602.00"))
    assert Decimal.equal?(from_2023.saver_allowance_single, Decimal.new("1000.00"))
    assert Decimal.equal?(from_2023.saver_allowance_joint, Decimal.new("2000.00"))

    # The 2021 partial Soli abolition did not touch the Abgeltungsteuer, so both
    # years carry the same rates.
    for parameters <- [before_2023, from_2023] do
      assert Decimal.equal?(parameters.capital_gains_tax_rate, Decimal.new("0.25"))
      assert Decimal.equal?(parameters.solidarity_surcharge_rate, Decimal.new("0.055"))
      assert parameters.built_in
    end
  end

  test "the seeded history starts at the Abgeltungsteuer and stops at the current year" do
    years = Tax.list_parameters(jurisdiction: "DE") |> Enum.map(& &1.tax_year)

    assert Enum.min(years) == 2009
    assert Enum.max(years) == 2026
    assert years == Enum.sort(years)
    assert length(years) == length(Enum.uniq(years))
  end

  # AC-8: never guess a year whose law is not written.
  test "an unseeded year is an error, not the nearest year" do
    assert Tax.fetch_parameters("DE", 2027) == {:error, :not_found}
    assert Tax.fetch_parameters("DE", 2008) == {:error, :not_found}
  end

  test "upserting parameters is journaled and replaces the year's row" do
    attrs = %{
      jurisdiction: "DE",
      tax_year: 2027,
      capital_gains_tax_rate: Decimal.new("0.25"),
      solidarity_surcharge_rate: Decimal.new("0.055"),
      saver_allowance_single: Decimal.new("1100.00"),
      saver_allowance_joint: Decimal.new("2200.00"),
      church_tax_rates: [Decimal.new("0.08"), Decimal.new("0.09")]
    }

    {:ok, created} = Tax.upsert_parameters(Actor.owner_ui(), attrs)
    refute created.built_in

    {:ok, updated} =
      Tax.upsert_parameters(
        Actor.owner_ui(),
        %{attrs | saver_allowance_single: Decimal.new("1200.00")}
      )

    assert updated.id == created.id
    assert Decimal.equal?(updated.saver_allowance_single, Decimal.new("1200.00"))

    entries =
      Journal.list_entries(resource_type: "tax_parameters", resource_id: to_string(created.id))

    assert entries |> Enum.map(& &1.operation) |> Enum.sort() == [:create, :update]
    assert Enum.all?(entries, &(&1.actor_type == :owner_ui))
  end

  test "a rate outside the unit interval is rejected" do
    attrs = %{
      jurisdiction: "DE",
      tax_year: 2027,
      capital_gains_tax_rate: Decimal.new("25"),
      solidarity_surcharge_rate: Decimal.new("0.055"),
      saver_allowance_single: Decimal.new("1000.00"),
      saver_allowance_joint: Decimal.new("2000.00")
    }

    assert {:error, changeset} = Tax.upsert_parameters(Actor.owner_ui(), attrs)
    assert %{capital_gains_tax_rate: [_ | _]} = errors_on(changeset)
  end

  test "a church-tax rate element outside the unit interval is rejected" do
    attrs = %{
      jurisdiction: "DE",
      tax_year: 2027,
      capital_gains_tax_rate: Decimal.new("0.25"),
      solidarity_surcharge_rate: Decimal.new("0.055"),
      saver_allowance_single: Decimal.new("1000.00"),
      saver_allowance_joint: Decimal.new("2000.00"),
      church_tax_rates: [Decimal.new("0.08"), Decimal.new("9")]
    }

    assert {:error, changeset} = Tax.upsert_parameters(Actor.owner_ui(), attrs)
    assert %{church_tax_rates: [_ | _]} = errors_on(changeset)
  end

  # AC-6: arming is what makes the traceability guarantee real.
  test "a write that bypasses the journal raises" do
    assert_raise Postgrex.Error, ~r/requires a journal actor/, fn ->
      Repo.insert!(%Tax.Parameters{
        jurisdiction: "DE",
        tax_year: 2028,
        capital_gains_tax_rate: Decimal.new("0.25"),
        solidarity_surcharge_rate: Decimal.new("0.055"),
        saver_allowance_single: Decimal.new("1000.00"),
        saver_allowance_joint: Decimal.new("2000.00"),
        church_tax_rates: []
      })
    end
  end
end
