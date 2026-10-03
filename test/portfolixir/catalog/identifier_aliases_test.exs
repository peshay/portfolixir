defmodule Portfolixir.Catalog.IdentifierAliasesTest do
  use Portfolixir.DataCase

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.IdentifierAlias
  alias Portfolixir.Catalog.IdentifierAliases
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Clock
  alias Portfolixir.Journal

  defp create_security!(attrs) do
    {:ok, security} =
      Catalog.create_security(
        Actor.owner_ui(),
        Map.merge(%{name: "Example AG", currency_code: "EUR"}, attrs)
      )

    security
  end

  # User story:
  # As a local portfolio maintainer whose security got a new ISIN through a
  # corporate action,
  # I want to record the ISIN change so the former ISIN becomes a journaled
  # alias and the security carries the new ISIN,
  # so that a later re-import of an old or new PP export keeps matching the
  # same security instead of duplicating it (ADR-0029 §3).
  #
  # Acceptance criteria:
  # - The former ISIN is stored as a `security_identifier_aliases` row with
  #   `changed_on` and the optional note.
  # - The security row carries the new ISIN after the call.
  # - Alias insert and security update are journaled with the acting actor in
  #   one transaction.
  describe "record_isin_change/4" do
    test "moves the current ISIN into an alias and writes the new ISIN" do
      security = create_security!(%{isin: "DE0001234565"})

      assert {:ok, %{security: updated, alias: alias_row}} =
               Catalog.record_isin_change(Actor.owner_ui(), security, "DE0007654329",
                 changed_on: ~D[2026-07-01],
                 note: "merger rename"
               )

      assert updated.isin == "DE0007654329"
      assert alias_row.security_id == security.id
      assert alias_row.former_isin == "DE0001234565"
      assert alias_row.changed_on == ~D[2026-07-01]
      assert alias_row.note == "merger rename"

      assert [listed] = Catalog.list_identifier_aliases(updated)
      assert listed.former_isin == "DE0001234565"

      assert [alias_entry] =
               Journal.list_entries(
                 resource_type: "security_identifier_alias",
                 operation: :create
               )

      assert alias_entry.actor_type == :owner_ui

      assert [update_entry | _] =
               Journal.list_entries(
                 resource_type: "security",
                 resource_id: to_string(security.id),
                 operation: :update
               )

      assert update_entry.after["isin"] == "DE0007654329"
      assert update_entry.before["isin"] == "DE0001234565"
    end

    test "normalizes the new ISIN to catalog normal form (trimmed, upcased)" do
      security = create_security!(%{isin: "DE0001234565"})

      assert {:ok, %{security: updated}} =
               Catalog.record_isin_change(Actor.owner_ui(), security, "  de0007654329  ")

      assert updated.isin == "DE0007654329"
    end

    test "rejects recording the current ISIN as the new one (A->A)" do
      security = create_security!(%{isin: "DE0001234565"})

      assert {:error, %Ecto.Changeset{} = changeset} =
               Catalog.record_isin_change(Actor.owner_ui(), security, "de0001234565")

      assert "must differ from the current ISIN" in errors_on(changeset).new_isin
      assert Catalog.get_security!(security.id).isin == "DE0001234565"
      assert Catalog.list_identifier_aliases(security) == []
    end

    test "rejects a new ISIN that is live on another security, naming it" do
      _other = create_security!(%{name: "Other AG", isin: "DE0009999995"})
      security = create_security!(%{isin: "DE0001234565"})

      assert {:error, %Ecto.Changeset{} = changeset} =
               Catalog.record_isin_change(Actor.owner_ui(), security, "DE0009999995")

      assert [message] = errors_on(changeset).new_isin
      assert message =~ "Other AG"
    end

    test "rejects a new ISIN that is aliased to another security, naming it" do
      other = create_security!(%{name: "Other AG", isin: "DE0009999995"})

      {:ok, _} = Catalog.record_isin_change(Actor.owner_ui(), other, "DE0008888884")

      security = create_security!(%{isin: "DE0001234565"})

      assert {:error, %Ecto.Changeset{} = changeset} =
               Catalog.record_isin_change(Actor.owner_ui(), security, "DE0009999995")

      assert [message] = errors_on(changeset).new_isin
      assert message =~ "Other AG"
    end

    test "rejects a security without a current ISIN" do
      security = create_security!(%{})

      assert {:error, %Ecto.Changeset{} = changeset} =
               Catalog.record_isin_change(Actor.owner_ui(), security, "DE0001234565")

      assert errors_on(changeset)[:new_isin]
    end

    test "rejects a blank new ISIN" do
      security = create_security!(%{isin: "DE0001234565"})

      assert {:error, %Ecto.Changeset{}} =
               Catalog.record_isin_change(Actor.owner_ui(), security, "   ")

      assert {:error, %Ecto.Changeset{}} =
               Catalog.record_isin_change(Actor.owner_ui(), security, nil)
    end

    # ADR-0029 §3 "chains and reverts": B->A consumes the security's own alias
    # row (journaled) instead of deadlocking on the uniqueness guard.
    test "reverting to an own former ISIN consumes that alias row (B->A)" do
      security = create_security!(%{isin: "DE00000000A3"})

      {:ok, %{security: security}} =
        Catalog.record_isin_change(Actor.owner_ui(), security, "DE00000000B1")

      assert {:ok, %{security: reverted, alias: new_alias}} =
               Catalog.record_isin_change(Actor.owner_ui(), security, "DE00000000A3")

      assert reverted.isin == "DE00000000A3"
      # The A alias was consumed; only the B alias remains.
      assert [remaining] = Catalog.list_identifier_aliases(reverted)
      assert remaining.former_isin == "DE00000000B1"
      assert new_alias.former_isin == "DE00000000B1"

      assert [delete_entry] =
               Journal.list_entries(
                 resource_type: "security_identifier_alias",
                 operation: :delete
               )

      assert delete_entry.before["former_isin"] == "DE00000000A3"
    end

    test "supports chains: A->B->C keeps both former ISINs as aliases" do
      security = create_security!(%{isin: "DE00000000A3"})

      {:ok, %{security: security}} =
        Catalog.record_isin_change(Actor.owner_ui(), security, "DE00000000B1")

      {:ok, %{security: security}} =
        Catalog.record_isin_change(Actor.owner_ui(), security, "DE00000000C9")

      assert security.isin == "DE00000000C9"

      former =
        security
        |> Catalog.list_identifier_aliases()
        |> Enum.map(& &1.former_isin)
        |> Enum.sort()

      assert former == ["DE00000000A3", "DE00000000B1"]
    end
  end

  # User story:
  # As a local portfolio maintainer who recorded an ISIN change by mistake,
  # I want to delete or reassign an identifier alias with a journal trail,
  # so that aliases stay correctable master data (ADR-0029 §3, not write-once).
  #
  # Acceptance criteria:
  # - `delete_identifier_alias/2` removes the row and journals the delete.
  # - `update_identifier_alias/3` can reassign the alias to another security
  #   and correct its fields, journaled.
  describe "delete_identifier_alias/2 and update_identifier_alias/3" do
    test "deletes an alias with a journaled delete entry" do
      security = create_security!(%{isin: "DE0001234565"})

      {:ok, %{alias: alias_row}} =
        Catalog.record_isin_change(Actor.owner_ui(), security, "DE0007654329")

      assert {:ok, _deleted} = Catalog.delete_identifier_alias(Actor.owner_ui(), alias_row)
      assert Catalog.list_identifier_aliases(security) == []

      assert [entry] =
               Journal.list_entries(
                 resource_type: "security_identifier_alias",
                 operation: :delete
               )

      assert entry.before["former_isin"] == "DE0001234565"
    end

    test "reassigns an alias to another security, journaled" do
      security = create_security!(%{isin: "DE0001234565"})
      other = create_security!(%{name: "Other AG", isin: "DE0009999995"})

      {:ok, %{alias: alias_row}} =
        Catalog.record_isin_change(Actor.owner_ui(), security, "DE0007654329")

      assert {:ok, moved} =
               Catalog.update_identifier_alias(Actor.owner_ui(), alias_row, %{
                 security_id: other.id
               })

      assert moved.security_id == other.id
      assert [_] = Catalog.list_identifier_aliases(other)

      assert [entry | _] =
               Journal.list_entries(
                 resource_type: "security_identifier_alias",
                 operation: :update
               )

      assert entry.after["security_id"] == other.id
    end

    test "corrects an alias former_isin to a value live on no security" do
      security = create_security!(%{isin: "DE0001234565"})

      {:ok, %{alias: alias_row}} =
        Catalog.record_isin_change(Actor.owner_ui(), security, "DE0007654329")

      assert {:ok, corrected} =
               Catalog.update_identifier_alias(Actor.owner_ui(), alias_row, %{
                 former_isin: "DE0001111110"
               })

      assert corrected.former_isin == "DE0001111110"

      assert [entry | _] =
               Journal.list_entries(
                 resource_type: "security_identifier_alias",
                 operation: :update
               )

      assert entry.after["former_isin"] == "DE0001111110"
    end

    test "rejects updating an alias onto a live ISIN" do
      security = create_security!(%{isin: "DE0001234565"})
      _other = create_security!(%{name: "Other AG", isin: "DE0009999995"})

      {:ok, %{alias: alias_row}} =
        Catalog.record_isin_change(Actor.owner_ui(), security, "DE0007654329")

      assert {:error, %Ecto.Changeset{} = changeset} =
               Catalog.update_identifier_alias(Actor.owner_ui(), alias_row, %{
                 former_isin: "DE0009999995"
               })

      assert [message] = errors_on(changeset).former_isin
      assert message =~ "Other AG"
    end
  end

  # User story:
  # As a local portfolio maintainer,
  # I want every security-ISIN write path to reject an ISIN that is recorded
  # as a former ISIN of any security,
  # so that current ISINs and aliases stay unique across both tables and a
  # stale export can never mint a duplicate carrying a retired ISIN
  # (ADR-0029 §3 bidirectional guard).
  #
  # Acceptance criteria:
  # - `create_security` rejects an aliased ISIN, naming the aliased security.
  # - `update_security` rejects an aliased ISIN, naming the aliased security.
  # - The import applier's create path (import-session actor) is equally
  #   rejected.
  describe "bidirectional alias guard" do
    setup do
      security = create_security!(%{name: "Aliased AG", isin: "DE0001234565"})

      {:ok, %{security: security}} =
        Catalog.record_isin_change(Actor.owner_ui(), security, "DE0007654329")

      %{aliased: security}
    end

    test "create_security rejects an ISIN present in the alias table", %{aliased: aliased} do
      assert {:error, %Ecto.Changeset{} = changeset} =
               Catalog.create_security(Actor.owner_ui(), %{
                 name: "Fresh",
                 currency_code: "EUR",
                 isin: "DE0001234565"
               })

      assert [message] = errors_on(changeset).isin
      assert message =~ aliased.name
    end

    test "the import applier's create path rejects an aliased ISIN", %{aliased: aliased} do
      assert {:error, %Ecto.Changeset{} = changeset} =
               Catalog.create_security(Actor.import_session(), %{
                 name: "Fresh from import",
                 currency_code: "EUR",
                 isin: "de0001234565"
               })

      assert [message] = errors_on(changeset).isin
      assert message =~ aliased.name
    end

    test "update_security rejects an ISIN present in the alias table", %{aliased: aliased} do
      other = create_security!(%{name: "Innocent", isin: "DE0005555551"})

      assert {:error, %Ecto.Changeset{} = changeset} =
               Catalog.update_security(Actor.owner_ui(), other, %{isin: "DE0001234565"})

      assert [message] = errors_on(changeset).isin
      assert message =~ aliased.name
    end

    test "an ISIN-untouched update passes the guard", %{aliased: aliased} do
      assert {:ok, updated} =
               Catalog.update_security(Actor.owner_ui(), aliased, %{name: "Renamed AG"})

      assert updated.name == "Renamed AG"
    end
  end

  # User story:
  # As a local portfolio maintainer deleting an unused security,
  # I want its identifier aliases to be removed with it (journaled),
  # so that no orphaned alias keeps blocking the retired ISIN
  # (ADR-0029 §3 correctability; the security delete guard protects history).
  #
  # Acceptance criteria:
  # - Deleting a security without transactions/quotes removes its alias rows.
  # - The alias removals are journaled.
  # User story:
  # As the operator whose ISIN write, alias correction or alias delete ran
  # on a row another writer removed after I read it,
  # I want a not-found answer, never a server error,
  # so that I reload and see what is there (E25 S6, F49).
  #
  # Acceptance criteria:
  # - An ISIN change of a security deleted since the read answers
  #   {:error, :not_found} and writes no alias.
  # - A delete or an update of an alias deleted since answers
  #   {:error, :not_found}.
  # - A correction onto a former ISIN another alias holds is refused by the
  #   unique index as a field error, and changes nothing.
  describe "a row gone or taken under the write" do
    test "an ISIN change of a deleted security answers not_found" do
      security = create_security!(%{isin: "DE0001234565"})
      {:ok, _} = Catalog.delete_security(Actor.owner_ui(), security)

      assert {:error, :not_found} =
               Catalog.record_isin_change(Actor.owner_ui(), security, "DE0007654329")

      assert Repo.aggregate(IdentifierAlias, :count) == 0
    end

    test "a delete or an update of a deleted alias answers not_found" do
      security = create_security!(%{isin: "DE0001234565"})

      {:ok, %{alias: alias_row}} =
        Catalog.record_isin_change(Actor.owner_ui(), security, "DE0007654329")

      assert {:ok, _} = Catalog.delete_identifier_alias(Actor.owner_ui(), alias_row)
      assert {:error, :not_found} = Catalog.delete_identifier_alias(Actor.owner_ui(), alias_row)

      assert {:error, :not_found} =
               Catalog.update_identifier_alias(Actor.owner_ui(), alias_row, %{note: "late"})
    end

    test "a correction onto another alias's former ISIN is a field error" do
      security = create_security!(%{isin: "DE0001234565"})

      {:ok, %{security: security, alias: first}} =
        Catalog.record_isin_change(Actor.owner_ui(), security, "DE0007654329")

      {:ok, %{alias: second}} =
        Catalog.record_isin_change(Actor.owner_ui(), security, "DE0001111110")

      assert {:error, %Ecto.Changeset{} = changeset} =
               Catalog.update_identifier_alias(Actor.owner_ui(), second, %{
                 former_isin: first.former_isin
               })

      assert "is already recorded as a former ISIN" in errors_on(changeset).former_isin
      assert Repo.get!(IdentifierAlias, second.id).former_isin == "DE0007654329"
    end
  end

  # User story:
  # As the operator merging away a security whose ISIN the kept one does not
  # take (ADR-0050 §9, keep_target_isin),
  # I want the merged-away ISIN recorded as a former ISIN of the kept
  # security, and refused while it is anyone's current or former ISIN,
  # so that an export still carrying it resolves to the kept security, and
  # never to two.
  #
  # Acceptance criteria:
  # - The ISIN, normalized, becomes one journaled alias row of the kept
  #   security, changed today unless a date is given; the kept security's
  #   own ISIN is unchanged.
  # - An ISIN still live on a security is refused on former_isin, naming
  #   that security; one recorded as a former ISIN already is refused by the
  #   unique index; neither writes anything.
  describe "record_merged_isin/4" do
    test "records the merged-away ISIN as a former ISIN, dated today by default" do
      kept = create_security!(%{name: "Kept AG", isin: "DE0001234565"})

      assert {:ok, %IdentifierAlias{} = alias_row} =
               IdentifierAliases.record_merged_isin(Actor.owner_ui(), kept, " de0007654329 ")

      assert {alias_row.security_id, alias_row.former_isin, alias_row.changed_on} ==
               {kept.id, "DE0007654329", Clock.today()}

      assert Repo.get!(Security, kept.id).isin == "DE0001234565"

      assert [entry] =
               Journal.list_entries(
                 resource_type: "security_identifier_alias",
                 operation: :create
               )

      assert entry.after["former_isin"] == "DE0007654329"
    end

    test "refuses an ISIN that is still live or already a former ISIN" do
      kept = create_security!(%{name: "Kept AG", isin: "DE0001234565"})
      live = create_security!(%{name: "Live AG", isin: "DE0007654329"})

      {:ok, %{alias: recorded}} =
        Catalog.record_isin_change(Actor.owner_ui(), live, "DE0001111110")

      entries = Repo.aggregate(Journal.Entry, :count)

      assert {:error, %Ecto.Changeset{} = changeset} =
               IdentifierAliases.record_merged_isin(Actor.owner_ui(), kept, "DE0001111110")

      assert [message] = errors_on(changeset).former_isin
      assert message =~ ~s|is still the current ISIN of "Live AG" (security ##{live.id})|

      assert {:error, %Ecto.Changeset{} = changeset} =
               IdentifierAliases.record_merged_isin(Actor.owner_ui(), kept, recorded.former_isin,
                 changed_on: ~D[2025-01-02]
               )

      assert "is already recorded as a former ISIN" in errors_on(changeset).former_isin
      assert Catalog.list_identifier_aliases(kept) == []
      assert Repo.aggregate(Journal.Entry, :count) == entries
    end
  end

  describe "delete_security/2 with aliases" do
    test "removes alias rows with the security, journaled" do
      security = create_security!(%{isin: "DE0001234565"})

      {:ok, %{security: security}} =
        Catalog.record_isin_change(Actor.owner_ui(), security, "DE0007654329")

      assert {:ok, _} = Catalog.delete_security(Actor.owner_ui(), security)

      assert [entry | _] =
               Journal.list_entries(
                 resource_type: "security_identifier_alias",
                 operation: :delete
               )

      assert entry.before["former_isin"] == "DE0001234565"

      # The formerly aliased ISIN is free again for a new security.
      assert {:ok, _} =
               Catalog.create_security(Actor.owner_ui(), %{
                 name: "Fresh",
                 currency_code: "EUR",
                 isin: "DE0001234565"
               })
    end
  end
end
