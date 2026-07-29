defmodule Portfolixir.Repo.Migrations.CreateTaxConfiguration do
  @moduledoc """
  ADR-0031 §3: the configuration layer the recorded tax-statement snapshots are
  checked against — statutory data that changes by year, a taxpayer situation
  that changes by date, and the Freistellungsauftrag as instructed per
  institution.

  All three tables exist because none of this is constant. The
  Sparer-Pauschbetrag changed in 2023, so a hardcoded ceiling would flag every
  correct transcription of a pre-2023 statement as inconsistent — exactly the
  failure mode Epic 19 is built to avoid.

  `holder` and `institution` are free text (Portfolixir has no institution
  entity). The unique indexes fold case so `"comdirect"` and `"Comdirect"`
  collide instead of silently becoming two rows that story 19.4's cross-checks
  would then compare against each other.
  """
  use Ecto.Migration

  def change do
    create table(:tax_parameters) do
      add(:jurisdiction, :string, size: 2, null: false)
      add(:tax_year, :integer, null: false)
      add(:capital_gains_tax_rate, :decimal, precision: 6, scale: 4, null: false)
      add(:solidarity_surcharge_rate, :decimal, precision: 6, scale: 4, null: false)
      add(:saver_allowance_single, :decimal, precision: 20, scale: 6, null: false)
      add(:saver_allowance_joint, :decimal, precision: 20, scale: 6, null: false)

      # Ecto's Postgres adapter emits `numeric[]` here and does NOT apply
      # precision/scale to the element type, so passing them would be silently
      # ignored. Element validation (0 <= r < 1) lives in the changeset. This
      # column is prefill/advisory input; nothing computes with it yet.
      add(:church_tax_rates, {:array, :decimal}, null: false, default: [])

      add(:built_in, :boolean, null: false, default: false)

      timestamps()
    end

    create(unique_index(:tax_parameters, [:jurisdiction, :tax_year]))

    # Widen when a second jurisdiction lands — a second country gets its own
    # engine, never nullable columns bolted onto this one (ADR-0031 §Trade-offs).
    create(
      constraint(:tax_parameters, :tax_parameters_jurisdiction_check,
        check: "jurisdiction = 'DE'"
      )
    )

    # int4 bound discipline (ADR-0028 fix round): a tax year outside this range
    # is a typo, not a statement.
    create(
      constraint(:tax_parameters, :tax_parameters_tax_year_check,
        check: "tax_year BETWEEN 1990 AND 2200"
      )
    )

    # Rates are fractions, never percentages: 0.25, not 25.
    create(
      constraint(:tax_parameters, :tax_parameters_rates_check,
        check: """
        capital_gains_tax_rate >= 0 AND capital_gains_tax_rate < 1 AND
        solidarity_surcharge_rate >= 0 AND solidarity_surcharge_rate < 1
        """
      )
    )

    create(
      constraint(:tax_parameters, :tax_parameters_allowances_check,
        check: """
        saver_allowance_single >= 0 AND saver_allowance_joint >= 0
        """
      )
    )

    create table(:tax_profiles) do
      add(:holder, :string, null: false)
      add(:valid_from, :date, null: false)
      add(:jurisdiction, :string, size: 2, null: false, default: "DE")
      add(:church_tax_liable, :boolean, null: false, default: false)
      add(:church_tax_rate, :decimal, precision: 6, scale: 4, null: false, default: 0)
      add(:assessment_type, :string, null: false, default: "single")
      add(:note, :text)

      timestamps()
    end

    # Case-folded so a holder typed two ways stays one taxpayer (§5a). The
    # profile in force is resolved as the greatest valid_from <= date, so one
    # row per holder and day is the identity.
    create(
      unique_index(:tax_profiles, ["lower(holder)", :valid_from],
        name: :tax_profiles_holder_valid_from_index
      )
    )

    create(
      constraint(:tax_profiles, :tax_profiles_jurisdiction_check, check: "jurisdiction = 'DE'")
    )

    create(
      constraint(:tax_profiles, :tax_profiles_church_tax_rate_check,
        check: "church_tax_rate >= 0 AND church_tax_rate < 1"
      )
    )

    # Not liable means the rate is zero — a stored non-zero rate on a not-liable
    # profile would silently inflate every consistency finding for that holder.
    # Mirrors `validate_church_tax/1` in Portfolixir.Tax.Profile.
    create(
      constraint(:tax_profiles, :tax_profiles_church_tax_liability_check,
        check: "church_tax_liable OR church_tax_rate = 0"
      )
    )

    # Mirrors `@assessment_types` in Portfolixir.Tax.Profile exactly.
    create(
      constraint(:tax_profiles, :tax_profiles_assessment_type_check,
        check: "assessment_type IN ('single', 'joint')"
      )
    )

    create table(:allowance_orders) do
      add(:holder, :string, null: false)
      add(:institution, :string, null: false)
      add(:tax_year, :integer, null: false)
      add(:amount_granted, :decimal, precision: 20, scale: 6, null: false)
      add(:note, :text)

      timestamps()
    end

    # Case-folded for the same reason as tax_profiles (§5a): story 19.4 joins
    # orders against snapshots per holder + institution, and a case split there
    # reports a missing instruction that is not missing.
    create(
      unique_index(:allowance_orders, ["lower(holder)", "lower(institution)", :tax_year],
        name: :allowance_orders_holder_institution_year_index
      )
    )

    create(
      constraint(:allowance_orders, :allowance_orders_tax_year_check,
        check: "tax_year BETWEEN 1990 AND 2200"
      )
    )

    create(
      constraint(:allowance_orders, :allowance_orders_amount_granted_check,
        check: "amount_granted >= 0"
      )
    )
  end
end
