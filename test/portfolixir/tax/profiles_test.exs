defmodule Portfolixir.Tax.ProfilesTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Tax

  # User story (2026-07-25, ADR-0031, story 19.2):
  # As a local portfolio maintainer,
  # I want my own tax situation to be effective-dated data rather than a
  # constant,
  # so that a change in my situation does not rewrite what an already-recorded
  # statement reconstructs to.
  #
  # Acceptance criteria:
  # - AC-2: church-tax liability defaults to NOT liable, the rate is 0 in that
  #   case, and assessment_type selects single/joint.
  # - AC-3: the profile in force is the greatest valid_from <= date, never an
  #   exact match.
  # - AC-4: adding a newer profile leaves an earlier lookup unchanged.
  # - AC-6: every profile write is journaled.

  test "a profile defaults to not liable for church tax with a zero rate" do
    {:ok, profile} =
      Tax.create_profile(Actor.owner_ui(), %{holder: "Owner", valid_from: ~D[2020-01-01]})

    refute profile.church_tax_liable
    assert Decimal.equal?(profile.church_tax_rate, Decimal.new("0"))
    assert profile.assessment_type == "single"
    assert profile.jurisdiction == "DE"
  end

  test "a non-zero church-tax rate on a not-liable profile is rejected" do
    assert {:error, changeset} =
             Tax.create_profile(Actor.owner_ui(), %{
               holder: "Owner",
               valid_from: ~D[2020-01-01],
               church_tax_liable: false,
               church_tax_rate: Decimal.new("0.09")
             })

    assert %{church_tax_rate: [_ | _]} = errors_on(changeset)
  end

  test "a liable profile keeps its rate and its assessment type" do
    {:ok, profile} =
      Tax.create_profile(Actor.owner_ui(), %{
        holder: "Owner",
        valid_from: ~D[2021-06-01],
        church_tax_liable: true,
        church_tax_rate: Decimal.new("0.09"),
        assessment_type: "joint"
      })

    assert profile.church_tax_liable
    assert Decimal.equal?(profile.church_tax_rate, Decimal.new("0.09"))
    assert profile.assessment_type == "joint"
  end

  test "a church-tax rate outside the unit interval is rejected even when liable" do
    assert {:error, changeset} =
             Tax.create_profile(Actor.owner_ui(), %{
               holder: "Owner",
               valid_from: ~D[2020-01-01],
               church_tax_liable: true,
               church_tax_rate: Decimal.new("9")
             })

    assert %{church_tax_rate: [_ | _]} = errors_on(changeset)
  end

  test "an explicitly blank church-tax rate is rejected, never defaulted" do
    assert {:error, changeset} =
             Tax.create_profile(Actor.owner_ui(), %{
               holder: "Owner",
               valid_from: ~D[2020-01-01],
               church_tax_liable: true,
               church_tax_rate: nil
             })

    assert %{church_tax_rate: [_ | _]} = errors_on(changeset)
  end

  # Identity.normalize/1 passes non-strings through so the cast reports the type
  # error rather than the normaliser masking it.
  test "a non-string holder is a type error, not a normalised value" do
    assert {:error, changeset} =
             Tax.create_profile(Actor.owner_ui(), %{holder: 42, valid_from: ~D[2020-01-01]})

    assert %{holder: [_ | _]} = errors_on(changeset)
  end

  test "an unknown assessment type is rejected" do
    assert {:error, changeset} =
             Tax.create_profile(Actor.owner_ui(), %{
               holder: "Owner",
               valid_from: ~D[2021-06-01],
               assessment_type: "household"
             })

    assert %{assessment_type: [_ | _]} = errors_on(changeset)
  end

  # AC-3: nearest-earlier-or-equal, the repo's `at_or_before` idiom.
  test "the profile in force is the greatest valid_from at or before the date" do
    {:ok, first} =
      Tax.create_profile(Actor.owner_ui(), %{holder: "Owner", valid_from: ~D[2018-01-01]})

    {:ok, second} =
      Tax.create_profile(Actor.owner_ui(), %{
        holder: "Owner",
        valid_from: ~D[2021-03-01],
        church_tax_liable: true,
        church_tax_rate: Decimal.new("0.09")
      })

    {:ok, third} =
      Tax.create_profile(Actor.owner_ui(), %{
        holder: "Owner",
        valid_from: ~D[2024-07-01],
        assessment_type: "joint"
      })

    assert Tax.profile_in_force("Owner", ~D[2017-12-31]) == nil
    assert Tax.profile_in_force("Owner", ~D[2018-01-01]).id == first.id
    assert Tax.profile_in_force("Owner", ~D[2020-12-31]).id == first.id
    assert Tax.profile_in_force("Owner", ~D[2021-03-01]).id == second.id
    assert Tax.profile_in_force("Owner", ~D[2023-05-05]).id == second.id
    assert Tax.profile_in_force("Owner", ~D[2099-01-01]).id == third.id

    assert Tax.profile_in_force("Someone else", ~D[2023-05-05]) == nil
  end

  # AC-4: resolution is a pure function of (holder, on_date) — a later row does
  # not reach back in time.
  test "adding a newer profile leaves an earlier lookup unchanged" do
    {:ok, old} =
      Tax.create_profile(Actor.owner_ui(), %{holder: "Owner", valid_from: ~D[2019-01-01]})

    before = Tax.profile_in_force("Owner", ~D[2020-06-30])
    assert before.id == old.id

    {:ok, _newer} =
      Tax.create_profile(Actor.owner_ui(), %{
        holder: "Owner",
        valid_from: ~D[2025-01-01],
        church_tax_liable: true,
        church_tax_rate: Decimal.new("0.08")
      })

    again = Tax.profile_in_force("Owner", ~D[2020-06-30])
    assert again.id == old.id
    refute again.church_tax_liable
    assert Decimal.equal?(again.church_tax_rate, Decimal.new("0"))
  end

  # §5a: one holder, however it was typed.
  test "the holder is normalised on write and matched case-insensitively" do
    {:ok, profile} =
      Tax.create_profile(Actor.owner_ui(), %{
        holder: "  Owner   Name  ",
        valid_from: ~D[2020-01-01]
      })

    assert profile.holder == "Owner Name"
    assert Tax.profile_in_force("owner name", ~D[2021-01-01]).id == profile.id

    assert {:error, changeset} =
             Tax.create_profile(Actor.owner_ui(), %{
               holder: "OWNER NAME",
               valid_from: ~D[2020-01-01]
             })

    assert %{holder: [_ | _]} = errors_on(changeset)
  end

  test "an empty holder is rejected" do
    assert {:error, changeset} =
             Tax.create_profile(Actor.owner_ui(), %{holder: "   ", valid_from: ~D[2020-01-01]})

    assert %{holder: [_ | _]} = errors_on(changeset)
  end

  test "profiles list newest first and update and delete are journaled" do
    {:ok, older} =
      Tax.create_profile(Actor.owner_ui(), %{holder: "Owner", valid_from: ~D[2019-01-01]})

    {:ok, newer} =
      Tax.create_profile(Actor.owner_ui(), %{holder: "Owner", valid_from: ~D[2023-01-01]})

    assert Enum.map(Tax.list_profiles("Owner"), & &1.id) == [newer.id, older.id]

    {:ok, updated} = Tax.update_profile(Actor.owner_ui(), newer, %{note: "moved"})
    assert updated.note == "moved"

    {:ok, _deleted} = Tax.delete_profile(Actor.owner_ui(), older)
    assert Enum.map(Tax.list_profiles("Owner"), & &1.id) == [newer.id]

    operations =
      Journal.list_entries(resource_type: "tax_profile")
      |> Enum.map(& &1.operation)
      |> Enum.sort()

    assert operations == [:create, :create, :delete, :update]
  end

  test "a write that bypasses the journal raises" do
    assert_raise Postgrex.Error, ~r/requires a journal actor/, fn ->
      Repo.insert!(%Tax.Profile{holder: "Owner", valid_from: ~D[2020-01-01]})
    end
  end
end
