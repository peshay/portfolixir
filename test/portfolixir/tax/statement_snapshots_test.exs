defmodule Portfolixir.Tax.StatementSnapshotsTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Tax

  # User story (2026-07-25, ADR-0031, story 19.3):
  # As a local portfolio maintainer,
  # I want to record the tax block of a broker statement with its as-of date,
  # so that the loss pots and the remaining allowance are auditable local data
  # instead of a PDF I have to find again.
  #
  # Acceptance criteria:
  # - The row stores Decimal values, non-negative magnitudes, and is unique on
  #   (institution, holder, tax_year, as_of).
  # - The write is journaled with the acting actor; an unjournaled write fails
  #   loudly.
  # - A negative input and an as_of in the future are rejected with a message
  #   naming the convention — never silently normalised.
  # - The church-tax rate is resolved from the profile in force at as_of and
  #   frozen on the row, so a later profile edit never rewrites a recorded
  #   transcription.

  defp statement_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        institution: "Example Bank",
        holder: "Owner",
        tax_year: 2025,
        as_of: ~D[2025-12-31],
        taxable_income: Decimal.new("4200.00"),
        allowance_granted: Decimal.new("1000.00"),
        allowance_used: Decimal.new("1000.00"),
        loss_pot_equities: Decimal.new("2500.00"),
        loss_pot_other: Decimal.new("300.00"),
        loss_carryforward_prior_years: Decimal.new("0"),
        withholding_tax_pot: Decimal.new("45.00"),
        withholding_tax_credited: Decimal.new("12.00"),
        capital_gains_tax_withheld: Decimal.new("800.00"),
        solidarity_surcharge_withheld: Decimal.new("44.00"),
        church_tax_withheld: Decimal.new("0")
      },
      overrides
    )
  end

  test "records a tax-statement snapshot with exact Decimal magnitudes" do
    {:ok, snapshot} =
      Tax.create_snapshot(Actor.owner_ui(), statement_attrs(), today: ~D[2026-01-15])

    assert snapshot.institution == "Example Bank"
    assert snapshot.holder == "Owner"
    assert snapshot.tax_year == 2025
    assert snapshot.as_of == ~D[2025-12-31]
    assert snapshot.source == "manual"

    assert Decimal.equal?(snapshot.taxable_income, Decimal.new("4200.00"))
    assert Decimal.equal?(snapshot.loss_pot_equities, Decimal.new("2500.00"))
    assert Decimal.equal?(snapshot.capital_gains_tax_withheld, Decimal.new("800.00"))
    assert Decimal.equal?(snapshot.church_tax_rate, Decimal.new("0"))

    assert Enum.map(Tax.list_snapshots(), & &1.id) == [snapshot.id]
    assert Enum.map(Tax.list_snapshots(holder: "owner", tax_year: 2025), & &1.id) == [snapshot.id]
    assert Tax.list_snapshots(tax_year: 2024) == []
  end

  # The magnitude rule, stated on the error rather than applied silently.
  test "a negative money field is rejected with a message naming the convention" do
    assert {:error, changeset} =
             Tax.create_snapshot(
               Actor.owner_ui(),
               statement_attrs(%{loss_pot_equities: Decimal.new("-2500.00")}),
               today: ~D[2026-01-15]
             )

    assert %{loss_pot_equities: [message]} = errors_on(changeset)
    assert message =~ "magnitude"
  end

  # C1 (ADR-0031 §4) — hard, because a save must not persist the contradiction.
  test "consuming more allowance than was granted is a save-blocking error" do
    assert {:error, changeset} =
             Tax.create_snapshot(
               Actor.owner_ui(),
               statement_attrs(%{
                 allowance_granted: Decimal.new("1000.00"),
                 allowance_used: Decimal.new("1200.00")
               }),
               today: ~D[2026-01-15]
             )

    assert %{allowance_used: [_ | _]} = errors_on(changeset)
  end

  # C2 — church tax withheld at a zero rate contradicts the row's own fields.
  test "church tax withheld at a zero church-tax rate is a save-blocking error" do
    assert {:error, changeset} =
             Tax.create_snapshot(
               Actor.owner_ui(),
               statement_attrs(%{
                 church_tax_rate: Decimal.new("0"),
                 church_tax_withheld: Decimal.new("72.00")
               }),
               today: ~D[2026-01-15]
             )

    assert %{church_tax_withheld: [_ | _]} = errors_on(changeset)
  end

  test "an as-of date in the future is rejected" do
    assert {:error, changeset} =
             Tax.create_snapshot(
               Actor.owner_ui(),
               statement_attrs(%{as_of: ~D[2026-06-30]}),
               today: ~D[2026-01-15]
             )

    assert %{as_of: [_ | _]} = errors_on(changeset)
  end

  test "an unknown source is rejected" do
    assert {:error, changeset} =
             Tax.create_snapshot(
               Actor.owner_ui(),
               statement_attrs(%{source: "guesswork"}),
               today: ~D[2026-01-15]
             )

    assert %{source: [_ | _]} = errors_on(changeset)
  end

  # Re-recording the same statement is a conflict, not a silent duplicate.
  test "the same statement recorded twice is a conflict" do
    {:ok, _first} =
      Tax.create_snapshot(Actor.owner_ui(), statement_attrs(), today: ~D[2026-01-15])

    assert {:error, changeset} =
             Tax.create_snapshot(
               Actor.owner_ui(),
               statement_attrs(%{institution: "EXAMPLE BANK"}),
               today: ~D[2026-01-15]
             )

    assert %{institution: [_ | _]} = errors_on(changeset)
  end

  test "a different as-of for the same year is a second snapshot" do
    {:ok, first} = Tax.create_snapshot(Actor.owner_ui(), statement_attrs(), today: ~D[2026-01-15])

    {:ok, second} =
      Tax.create_snapshot(
        Actor.owner_ui(),
        statement_attrs(%{as_of: ~D[2025-06-30]}),
        today: ~D[2026-01-15]
      )

    # Newest as-of first: the trim budget is read off the latest statement.
    assert Enum.map(Tax.list_snapshots(), & &1.id) == [first.id, second.id]
    assert Tax.latest_snapshot("Example Bank", "Owner", 2025).id == first.id
  end

  # AC-4 of story 19.2, realised here: the resolved rate is frozen on the row.
  test "the church-tax rate is resolved from the profile in force and frozen" do
    {:ok, _profile} =
      Tax.create_profile(Actor.owner_ui(), %{
        holder: "Owner",
        valid_from: ~D[2024-01-01],
        church_tax_liable: true,
        church_tax_rate: Decimal.new("0.09")
      })

    {:ok, snapshot} =
      Tax.create_snapshot(
        Actor.owner_ui(),
        statement_attrs(%{church_tax_withheld: Decimal.new("72.00")}),
        today: ~D[2026-01-15]
      )

    assert Decimal.equal?(snapshot.church_tax_rate, Decimal.new("0.09"))

    {:ok, _later_profile} =
      Tax.create_profile(Actor.owner_ui(), %{
        holder: "Owner",
        valid_from: ~D[2026-01-01],
        church_tax_liable: false
      })

    {:ok, reloaded} = Tax.fetch_snapshot(snapshot.id)
    assert Decimal.equal?(reloaded.church_tax_rate, Decimal.new("0.09"))
  end

  test "an explicit church-tax rate overrides the profile prefill" do
    {:ok, _profile} =
      Tax.create_profile(Actor.owner_ui(), %{
        holder: "Owner",
        valid_from: ~D[2024-01-01],
        church_tax_liable: true,
        church_tax_rate: Decimal.new("0.09")
      })

    {:ok, snapshot} =
      Tax.create_snapshot(
        Actor.owner_ui(),
        statement_attrs(%{church_tax_rate: Decimal.new("0.08")}),
        today: ~D[2026-01-15]
      )

    assert Decimal.equal?(snapshot.church_tax_rate, Decimal.new("0.08"))
  end

  test "updates and deletes are journaled, and an unknown id is not found" do
    {:ok, snapshot} =
      Tax.create_snapshot(Actor.owner_ui(), statement_attrs(), today: ~D[2026-01-15])

    {:ok, updated} =
      Tax.update_snapshot(
        Actor.owner_ui(),
        snapshot,
        %{note: "page 4 of the annual report"},
        today: ~D[2026-01-15]
      )

    assert updated.note == "page 4 of the annual report"

    {:ok, _deleted} = Tax.delete_snapshot(Actor.owner_ui(), snapshot.id)
    assert Tax.fetch_snapshot(snapshot.id) == {:error, :not_found}
    assert Tax.delete_snapshot(Actor.owner_ui(), snapshot.id) == {:error, :not_found}

    operations =
      Journal.list_entries(resource_type: "tax_statement_snapshot")
      |> Enum.map(& &1.operation)
      |> Enum.sort()

    assert operations == [:create, :delete, :update]
  end

  test "a write that bypasses the journal raises" do
    assert_raise Postgrex.Error, ~r/requires a journal actor/, fn ->
      Repo.insert!(%Tax.StatementSnapshot{
        institution: "Example Bank",
        holder: "Owner",
        tax_year: 2025,
        as_of: ~D[2025-12-31],
        source: "manual"
      })
    end
  end
end
