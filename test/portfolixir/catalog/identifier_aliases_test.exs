defmodule Portfolixir.Catalog.IdentifierAliasesTest do
  use Portfolixir.DataCase

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
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
      security = create_security!(%{isin: "DE0001234567"})

      assert {:ok, %{security: updated, alias: alias_row}} =
               Catalog.record_isin_change(Actor.owner_ui(), security, "DE0007654321",
                 changed_on: ~D[2026-07-01],
                 note: "merger rename"
               )

      assert updated.isin == "DE0007654321"
      assert alias_row.security_id == security.id
      assert alias_row.former_isin == "DE0001234567"
      assert alias_row.changed_on == ~D[2026-07-01]
      assert alias_row.note == "merger rename"

      assert [listed] = Catalog.list_identifier_aliases(updated)
      assert listed.former_isin == "DE0001234567"

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

      assert update_entry.after["isin"] == "DE0007654321"
      assert update_entry.before["isin"] == "DE0001234567"
    end

    test "normalizes the new ISIN to catalog normal form (trimmed, upcased)" do
      security = create_security!(%{isin: "DE0001234567"})

      assert {:ok, %{security: updated}} =
               Catalog.record_isin_change(Actor.owner_ui(), security, "  de0007654321  ")

      assert updated.isin == "DE0007654321"
    end

    test "rejects recording the current ISIN as the new one (A->A)" do
      security = create_security!(%{isin: "DE0001234567"})

      assert {:error, %Ecto.Changeset{} = changeset} =
               Catalog.record_isin_change(Actor.owner_ui(), security, "de0001234567")

      assert {"must differ from the current ISIN", _} = changeset.errors[:new_isin]
      assert Catalog.get_security!(security.id).isin == "DE0001234567"
      assert Catalog.list_identifier_aliases(security) == []
    end

    test "rejects a new ISIN that is live on another security, naming it" do
      _other = create_security!(%{name: "Other AG", isin: "DE0009999999"})
      security = create_security!(%{isin: "DE0001234567"})

      assert {:error, %Ecto.Changeset{} = changeset} =
               Catalog.record_isin_change(Actor.owner_ui(), security, "DE0009999999")

      assert {message, _} = changeset.errors[:new_isin]
      assert message =~ "Other AG"
    end

    test "rejects a new ISIN that is aliased to another security, naming it" do
      other = create_security!(%{name: "Other AG", isin: "DE0009999999"})

      {:ok, _} = Catalog.record_isin_change(Actor.owner_ui(), other, "DE0008888888")

      security = create_security!(%{isin: "DE0001234567"})

      assert {:error, %Ecto.Changeset{} = changeset} =
               Catalog.record_isin_change(Actor.owner_ui(), security, "DE0009999999")

      assert {message, _} = changeset.errors[:new_isin]
      assert message =~ "Other AG"
    end

    test "rejects a security without a current ISIN" do
      security = create_security!(%{})

      assert {:error, %Ecto.Changeset{} = changeset} =
               Catalog.record_isin_change(Actor.owner_ui(), security, "DE0001234567")

      assert changeset.errors[:new_isin]
    end

    test "rejects a blank new ISIN" do
      security = create_security!(%{isin: "DE0001234567"})

      assert {:error, %Ecto.Changeset{}} =
               Catalog.record_isin_change(Actor.owner_ui(), security, "   ")

      assert {:error, %Ecto.Changeset{}} =
               Catalog.record_isin_change(Actor.owner_ui(), security, nil)
    end

    # ADR-0029 §3 "chains and reverts": B->A consumes the security's own alias
    # row (journaled) instead of deadlocking on the uniqueness guard.
    test "reverting to an own former ISIN consumes that alias row (B->A)" do
      security = create_security!(%{isin: "DE000000000A"})

      {:ok, %{security: security}} =
        Catalog.record_isin_change(Actor.owner_ui(), security, "DE000000000B")

      assert {:ok, %{security: reverted, alias: new_alias}} =
               Catalog.record_isin_change(Actor.owner_ui(), security, "DE000000000A")

      assert reverted.isin == "DE000000000A"
      # The A alias was consumed; only the B alias remains.
      assert [remaining] = Catalog.list_identifier_aliases(reverted)
      assert remaining.former_isin == "DE000000000B"
      assert new_alias.former_isin == "DE000000000B"

      assert [delete_entry] =
               Journal.list_entries(
                 resource_type: "security_identifier_alias",
                 operation: :delete
               )

      assert delete_entry.before["former_isin"] == "DE000000000A"
    end

    test "supports chains: A->B->C keeps both former ISINs as aliases" do
      security = create_security!(%{isin: "DE000000000A"})

      {:ok, %{security: security}} =
        Catalog.record_isin_change(Actor.owner_ui(), security, "DE000000000B")

      {:ok, %{security: security}} =
        Catalog.record_isin_change(Actor.owner_ui(), security, "DE000000000C")

      assert security.isin == "DE000000000C"

      former =
        security
        |> Catalog.list_identifier_aliases()
        |> Enum.map(& &1.former_isin)
        |> Enum.sort()

      assert former == ["DE000000000A", "DE000000000B"]
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
      security = create_security!(%{isin: "DE0001234567"})

      {:ok, %{alias: alias_row}} =
        Catalog.record_isin_change(Actor.owner_ui(), security, "DE0007654321")

      assert {:ok, _deleted} = Catalog.delete_identifier_alias(Actor.owner_ui(), alias_row)
      assert Catalog.list_identifier_aliases(security) == []

      assert [entry] =
               Journal.list_entries(
                 resource_type: "security_identifier_alias",
                 operation: :delete
               )

      assert entry.before["former_isin"] == "DE0001234567"
    end

    test "reassigns an alias to another security, journaled" do
      security = create_security!(%{isin: "DE0001234567"})
      other = create_security!(%{name: "Other AG", isin: "DE0009999999"})

      {:ok, %{alias: alias_row}} =
        Catalog.record_isin_change(Actor.owner_ui(), security, "DE0007654321")

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
      security = create_security!(%{isin: "DE0001234567"})

      {:ok, %{alias: alias_row}} =
        Catalog.record_isin_change(Actor.owner_ui(), security, "DE0007654321")

      assert {:ok, corrected} =
               Catalog.update_identifier_alias(Actor.owner_ui(), alias_row, %{
                 former_isin: "DE0001111111"
               })

      assert corrected.former_isin == "DE0001111111"

      assert [entry | _] =
               Journal.list_entries(
                 resource_type: "security_identifier_alias",
                 operation: :update
               )

      assert entry.after["former_isin"] == "DE0001111111"
    end

    test "rejects updating an alias onto a live ISIN" do
      security = create_security!(%{isin: "DE0001234567"})
      _other = create_security!(%{name: "Other AG", isin: "DE0009999999"})

      {:ok, %{alias: alias_row}} =
        Catalog.record_isin_change(Actor.owner_ui(), security, "DE0007654321")

      assert {:error, %Ecto.Changeset{} = changeset} =
               Catalog.update_identifier_alias(Actor.owner_ui(), alias_row, %{
                 former_isin: "DE0009999999"
               })

      assert {message, _} = changeset.errors[:former_isin]
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
      security = create_security!(%{name: "Aliased AG", isin: "DE0001234567"})

      {:ok, %{security: security}} =
        Catalog.record_isin_change(Actor.owner_ui(), security, "DE0007654321")

      %{aliased: security}
    end

    test "create_security rejects an ISIN present in the alias table", %{aliased: aliased} do
      assert {:error, %Ecto.Changeset{} = changeset} =
               Catalog.create_security(Actor.owner_ui(), %{
                 name: "Fresh",
                 currency_code: "EUR",
                 isin: "DE0001234567"
               })

      assert {message, _} = changeset.errors[:isin]
      assert message =~ aliased.name
    end

    test "the import applier's create path rejects an aliased ISIN", %{aliased: aliased} do
      assert {:error, %Ecto.Changeset{} = changeset} =
               Catalog.create_security(Actor.import_session(), %{
                 name: "Fresh from import",
                 currency_code: "EUR",
                 isin: "de0001234567"
               })

      assert {message, _} = changeset.errors[:isin]
      assert message =~ aliased.name
    end

    test "update_security rejects an ISIN present in the alias table", %{aliased: aliased} do
      other = create_security!(%{name: "Innocent", isin: "DE0005555555"})

      assert {:error, %Ecto.Changeset{} = changeset} =
               Catalog.update_security(Actor.owner_ui(), other, %{isin: "DE0001234567"})

      assert {message, _} = changeset.errors[:isin]
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
  describe "delete_security/2 with aliases" do
    test "removes alias rows with the security, journaled" do
      security = create_security!(%{isin: "DE0001234567"})

      {:ok, %{security: security}} =
        Catalog.record_isin_change(Actor.owner_ui(), security, "DE0007654321")

      assert {:ok, _} = Catalog.delete_security(Actor.owner_ui(), security)

      assert [entry | _] =
               Journal.list_entries(
                 resource_type: "security_identifier_alias",
                 operation: :delete
               )

      assert entry.before["former_isin"] == "DE0001234567"

      # The formerly aliased ISIN is free again for a new security.
      assert {:ok, _} =
               Catalog.create_security(Actor.owner_ui(), %{
                 name: "Fresh",
                 currency_code: "EUR",
                 isin: "DE0001234567"
               })
    end
  end
end
