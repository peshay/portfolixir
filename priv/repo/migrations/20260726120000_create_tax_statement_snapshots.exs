defmodule Portfolixir.Repo.Migrations.CreateTaxStatementSnapshots do
  @moduledoc """
  ADR-0031 §2 (story 19.3): the recorded tax block of a broker statement — one
  row per `(institution, holder, tax_year, as_of)`.

  The row is a **transcription of an aggregate statement block**. Nothing about
  a real position, security or transaction is stored here, and nothing in it is
  derived: ADR-0031 rejects computing the German tax pots from the ledger
  because Portfolixir folds cost basis as a running average while the tax code
  mandates strict FIFO.

  **Sign convention — magnitudes only.** Every money column carries a
  `>= 0` CHECK. A loss pot is stored as the volume of loss available for
  offsetting, not as the negative number the statement prints. A negative input
  is rejected with a message naming the convention, never silently flipped:
  silent sign normalisation is how a transcription error becomes a permanently
  wrong number.

  `church_tax_rate` is prefilled from the holder's profile in force at `as_of`
  and then **frozen on the row**, so a later profile edit cannot rewrite what an
  already-recorded statement reconstructs to.
  """
  use Ecto.Migration

  @money_columns ~w(
    taxable_income
    allowance_granted
    allowance_used
    loss_pot_equities
    loss_pot_other
    loss_carryforward_prior_years
    withholding_tax_pot
    withholding_tax_credited
    capital_gains_tax_withheld
    solidarity_surcharge_withheld
    church_tax_withheld
  )a

  def change do
    create table(:tax_statement_snapshots) do
      add(:institution, :string, null: false)
      add(:holder, :string, null: false)
      add(:tax_year, :integer, null: false)
      add(:as_of, :date, null: false)
      add(:source, :string, null: false, default: "manual")
      add(:church_tax_rate, :decimal, precision: 6, scale: 4, null: false, default: 0)
      add(:note, :text)

      for column <- @money_columns do
        add(column, :decimal, precision: 20, scale: 6, null: false, default: 0)
      end

      timestamps()
    end

    # All four parts are NOT NULL, so there is no NULLS NOT DISTINCT trap.
    # Re-recording the same statement is a conflict, not a silent duplicate; a
    # corrected re-issue for the same date is an update.
    create(
      unique_index(
        :tax_statement_snapshots,
        ["lower(institution)", "lower(holder)", :tax_year, :as_of],
        name: :tax_statement_snapshots_identity_index
      )
    )

    create(
      constraint(:tax_statement_snapshots, :tax_statement_snapshots_tax_year_check,
        check: "tax_year BETWEEN 1990 AND 2200"
      )
    )

    # Mirrors `@sources` in Portfolixir.Tax.StatementSnapshot exactly.
    # `pdf_import` is reserved for the ADR-0021 intake.
    create(
      constraint(:tax_statement_snapshots, :tax_statement_snapshots_source_check,
        check: "source IN ('manual', 'pdf_import')"
      )
    )

    create(
      constraint(:tax_statement_snapshots, :tax_statement_snapshots_church_tax_rate_check,
        check: "church_tax_rate >= 0 AND church_tax_rate < 1"
      )
    )

    # The magnitude rule, as a DB backstop for a row written outside the
    # changeset. Mirrors `@money_fields` in the schema exactly.
    create(
      constraint(:tax_statement_snapshots, :tax_statement_snapshots_magnitudes_check,
        check: Enum.map_join(@money_columns, " AND\n", &"#{&1} >= 0")
      )
    )
  end
end
