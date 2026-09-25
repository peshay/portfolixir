defmodule Portfolixir.Journal.BeforeImageLockTest do
  # E25 S6 (#891), F49: a journaled update or delete took its before-image
  # from the struct the caller had read, outside the writing transaction and
  # without a lock, so two writers acting on one read both claimed the same
  # prior state and the journal's change history did not chain. The journal
  # seam now re-reads the row FOR UPDATE inside the writing transaction and
  # records that row as the before-image, and the stored row as the
  # after-image; a row gone in the meantime answers not found.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias Portfolixir.Journal
  alias Portfolixir.Knowledge.Events
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Tax
  alias Portfolixir.WorldFixtures

  defp owner, do: Actor.owner_ui()

  defp entries(type, id, operation) do
    Journal.list_entries(resource_type: type, resource_id: to_string(id), operation: operation)
  end

  # Each case: the resource type, a fresh record, two updates that change
  # different fields, and a delete — all of them context functions.
  defp cases do
    world = WorldFixtures.base_world(name: "Lock World")
    security = WorldFixtures.create_security!(name: "Lockstep Rail AG", ticker: "LRA")
    tx = WorldFixtures.deposit!(world, "250", ~D[2026-02-02])
    {:ok, classification} = Classifications.create_classification(owner(), %{name: "Style"})
    # Bucket names are unique instance-wide: one per test run.
    {:ok, bucket} =
      Buckets.create_bucket(owner(), %{
        name: "Core #{System.unique_integer([:positive])}",
        dimension: "tag"
      })

    {:ok, event} =
      Events.create_event(owner(), %{
        security_id: security.id,
        kind: "earnings",
        date: ~D[2026-11-20],
        timing: "estimated",
        source_quality: "awareness"
      })

    {:ok, profile} =
      Tax.create_profile(owner(), %{holder: "Owner", valid_from: ~D[2025-01-01]})

    [
      {"classification", classification,
       &Classifications.update_classification(owner(), &1, %{name: "Style one"}),
       &Classifications.update_classification(owner(), &1, %{description: "Second write"}),
       &Classifications.delete_classification(owner(), &1)},
      {"bucket", bucket,
       &Buckets.update_bucket(owner(), &1, %{
         name: "Core one #{System.unique_integer([:positive])}"
       }), &Buckets.update_bucket(owner(), &1, %{color: "#123abc"}),
       &Buckets.delete_bucket(owner(), &1)},
      {"security", security, &Catalog.update_security(owner(), &1, %{name: "Lockstep one"}),
       &Catalog.update_security(owner(), &1, %{note: "Second write"}), nil},
      {"cash_account", world.cash,
       &Portfolios.update_cash_account(owner(), &1, %{name: "Cash one"}),
       &Portfolios.update_cash_account(owner(), &1, %{notes: "Second write"}), nil},
      {"transaction", tx, &Ledger.update_transaction(owner(), &1, %{notes: "First write"}),
       &Ledger.update_transaction(owner(), &1, %{date: ~D[2026-02-03]}),
       &Ledger.delete_transaction(owner(), &1)},
      {"security_event", event, &Events.update_event(owner(), &1, %{note: "First write"}),
       &Events.update_event(owner(), &1, %{timing: "exact"}), &Events.delete_event(owner(), &1)},
      {"tax_profile", profile, &Tax.update_profile(owner(), &1, %{note: "First write"}),
       &Tax.update_profile(owner(), &1, %{assessment_type: "joint"}),
       &Tax.delete_profile(owner(), &1)}
    ]
  end

  # User story:
  # As the operator reading a record's change history,
  # I want each entry's before-image to be the row as it stood when the write
  # took its lock, and its after-image the row as stored,
  # so that two writes acting on one read chain in the journal instead of
  # both claiming the same prior state.
  #
  # Acceptance criteria:
  # - Two updates built from one read: the second entry's before-image is the
  #   first entry's after-image, for every journaled context below.
  # - The second entry's after-image carries both writes, as stored.
  test "two updates from one stale read chain their journal before-images" do
    for {type, stale, first, second, _delete} <- cases() do
      assert {:ok, _} = first.(stale), "first update of #{type}"
      assert {:ok, _} = second.(stale), "second update of #{type}"

      assert [later, earlier] = entries(type, stale.id, :update), "two entries for #{type}"

      assert later.before == earlier.after,
             "#{type}: the second before-image is not the first after-image"

      first_changes =
        for {key, value} <- earlier.after,
            key != "updated_at",
            earlier.before[key] != value,
            do: {key, value}

      assert first_changes != [], "#{type}: the first write changed nothing"

      for {key, value} <- first_changes do
        assert later.after[key] == value,
               "#{type}: the second after-image lost the first write's #{key}"
      end
    end
  end

  # User story:
  # As the operator or the agent writing a record another writer has just
  # deleted,
  # I want the write to answer that the record is gone,
  # so that it neither crashes nor journals a change to a row that no longer
  # exists.
  #
  # Acceptance criteria:
  # - An update or a delete of a row deleted in the meantime answers not
  #   found (a security event keeps its `:stale` contract) and writes no
  #   entry.
  test "an update or delete of a row deleted in the meantime answers not found" do
    for {type, stale, first, _second, delete} <- cases(), delete do
      assert {:ok, _} = delete.(stale), "delete of #{type}"
      before = Journal.list_entries(resource_type: type)

      assert {:error, reason} = first.(stale)
      assert reason in [:not_found, :stale], "#{type} update answered #{inspect(reason)}"

      assert {:error, reason} = delete.(stale)
      assert reason in [:not_found, :stale], "#{type} delete answered #{inspect(reason)}"

      assert Journal.list_entries(resource_type: type) == before
    end
  end

  # User story (E25 S6 review round, M5):
  # As the operator correcting an alias's note back to what I read while
  # another edit changed it in between,
  # I want my edit written,
  # so that a write built from a stale read is never computed as "no change"
  # and dropped.
  #
  # Acceptance criteria:
  # - An alias edit builds its changeset on the row as stored under the
  #   write's lock: two edits from one read leave the second one's value,
  #   and the journal chains them.
  test "an alias edit from a stale read that sets a field back is written, not dropped" do
    {:ok, security} =
      Catalog.create_security(owner(), %{
        name: "Alias Rail AG",
        isin: "DE000ALIAS03",
        currency_code: "EUR"
      })

    {:ok, %{alias: stale}} =
      Catalog.record_isin_change(owner(), security, "DE000ALIAS11", note: "read note")

    assert {:ok, _} =
             Catalog.update_identifier_alias(owner(), stale, %{note: "changed meanwhile"})

    assert {:ok, written} = Catalog.update_identifier_alias(owner(), stale, %{note: "read note"})

    assert written.note == "read note"
    assert Repo.get!(Portfolixir.Catalog.IdentifierAlias, stale.id).note == "read note"

    assert [later, earlier] = entries("security_identifier_alias", stale.id, :update)
    assert later.before == earlier.after
    assert later.after["note"] == "read note"
  end
end
