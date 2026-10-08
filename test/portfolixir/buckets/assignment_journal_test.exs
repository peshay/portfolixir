defmodule Portfolixir.Buckets.AssignmentJournalTest do
  # #953 (E25 S6 follow-up): the depot default-set writer, the cash-account
  # set writer and the position-override writers journaled the new set only.
  # An entry did not say what the set was changed from, which broke
  # ADR-0017's full before and after snapshots, and with no before-image the
  # G02 rule ("no entry for no change") could not apply: resending the
  # stored set wrote an entry each time. Each writer now reads the owner's
  # stored set under the owner lock G10 added and hands it to
  # `Journal.record/3` as the before-image, as the view writers do since F45.
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Derived.DataVersion
  alias Portfolixir.Journal

  defp owner, do: Actor.owner_ui()

  # Bucket names are unique instance-wide, so each is made unique here: two
  # async tests inserting one name would wait on each other.
  defp bucket!(name) do
    {:ok, bucket} =
      Buckets.create_bucket(owner(), %{
        name: "#{name} #{System.unique_integer([:positive])}",
        dimension: "tag"
      })

    bucket
  end

  defp entries(resource_type, owner_key, owner_id) do
    resource_type
    |> then(&Journal.list_entries(resource_type: &1))
    |> Enum.filter(&((&1.after || %{})[owner_key] == owner_id))
  end

  # User story:
  # As the operator auditing who changed an account's buckets,
  # I want each change of a depot's or a cash account's bucket set journaled
  # with the set before and after it, and a resent set journaled not at all,
  # so that the journal says what each set was changed from, and an agent
  # resending the stored set leaves no entry that changed nothing.
  #
  # Acceptance criteria:
  # - A depot's first set is journaled with an empty set before it; a change
  #   carries the stored set before and the stored set after, in id order.
  # - Resending the stored set, in any order, journals nothing.
  # - The cash-account writer does the same.
  # - A bucket delete that releases the bucket from both sets journals each
  #   with the set it held before.
  test "an account's bucket set is journaled with its prior set, and a resent set not at all" do
    world = base_world(name: "Journal Portfolio")
    core = bucket!("Core")
    satellite = bucket!("Satellite")

    for {write, resource_type, owner_key, owner_id} <- [
          {&Buckets.set_depot_default_buckets(owner(), world.depot, &1),
           "depot_bucket_assignment", "securities_account_id", world.depot.id},
          {&Buckets.set_cash_account_buckets(owner(), world.cash, &1),
           "cash_account_bucket_assignment", "cash_account_id", world.cash.id}
        ] do
      assert :ok = write.([core.id])
      assert [first] = entries(resource_type, owner_key, owner_id)
      assert first.operation == :update
      assert first.before["bucket_ids"] == []
      assert first.after["bucket_ids"] == [core.id]

      assert :ok = write.([satellite.id, core.id])
      assert [second, ^first] = entries(resource_type, owner_key, owner_id)
      assert second.before["bucket_ids"] == [core.id]
      assert second.after["bucket_ids"] == [core.id, satellite.id]
      assert second.before[owner_key] == owner_id

      assert :ok = write.([satellite.id, core.id])
      assert :ok = write.([core.id, satellite.id, core.id])
      assert [^second, ^first] = entries(resource_type, owner_key, owner_id)
    end

    assert {:ok, _} = Buckets.delete_bucket(owner(), satellite)

    for {resource_type, owner_key, owner_id} <- [
          {"depot_bucket_assignment", "securities_account_id", world.depot.id},
          {"cash_account_bucket_assignment", "cash_account_id", world.cash.id}
        ] do
      assert [released | _] = entries(resource_type, owner_key, owner_id)
      assert released.before["bucket_ids"] == [core.id, satellite.id]
      assert released.after["bucket_ids"] == [core.id]
    end
  end

  # User story:
  # As the operator auditing a position's own buckets,
  # I want each change of a position override journaled with the override
  # before it, and a resent override journaled not at all,
  # so that the journal tells inheriting, "no buckets" and a specific set
  # apart on both sides of each change.
  #
  # Acceptance criteria:
  # - The first override of an inheriting position has no before-image; a
  #   change carries the stored override before (an empty set for "no
  #   buckets") and the stored one after, in id order.
  # - Resending the stored override, explicit-empty included, journals
  #   nothing.
  # - Clearing the override journals a delete whose before-image is the
  #   override it removed.
  test "a position override is journaled with its prior override, and a resent one not at all" do
    world = base_world(name: "Override Journal Portfolio")
    security = create_security!(name: "Harbor Light Utilities SE", ticker: "HLU")
    core = bucket!("Core")
    satellite = bucket!("Satellite")

    override_entries = fn ->
      "position_bucket_override"
      |> entries("security_id", security.id)
      |> Enum.filter(&(&1.after["securities_account_id"] == world.depot.id))
    end

    assert :ok = Buckets.set_position_override(owner(), world.depot, security, [core.id])
    assert [first] = override_entries.()
    assert first.operation == :update
    assert first.before == nil
    assert first.after["bucket_ids"] == [core.id]

    assert :ok =
             Buckets.set_position_override(owner(), world.depot, security, [
               satellite.id,
               core.id
             ])

    assert [second, ^first] = override_entries.()
    assert second.before["bucket_ids"] == [core.id]
    assert second.after["bucket_ids"] == [core.id, satellite.id]

    assert :ok =
             Buckets.set_position_override(owner(), world.depot, security, [
               core.id,
               satellite.id
             ])

    assert [^second, ^first] = override_entries.()

    assert :ok = Buckets.set_position_override(owner(), world.depot, security, [])
    assert [emptied, ^second, ^first] = override_entries.()
    assert emptied.before["bucket_ids"] == [core.id, satellite.id]
    assert emptied.after["bucket_ids"] == []

    assert :ok = Buckets.set_position_override(owner(), world.depot, security, [])
    assert [^emptied, ^second, ^first] = override_entries.()

    assert :ok = Buckets.clear_position_override(owner(), world.depot, security)
    assert [cleared, ^emptied | _] = override_entries.()
    assert cleared.operation == :delete
    assert cleared.before["bucket_ids"] == []
    assert Buckets.position_override(world.depot.id, security.id) == :inherit
  end

  # User story (#953, the clear's half):
  # As the operator auditing a position's own buckets,
  # I want clearing the override of a position that already inherits its
  # depot's buckets to leave no journal entry and to invalidate nothing,
  # so that the journal holds no delete that removed nothing, as a resent set
  # leaves none (ADR-0017, G02).
  #
  # Acceptance criteria:
  # - Clearing a position that inherits answers :ok, journals no
  #   position_bucket_override entry, and bumps no derived basis: the
  #   portfolio's data version is unchanged.
  # - Clearing an override the position has still journals the delete with
  #   the override it removed, and bumps the portfolio's data version.
  # - Clearing it once more journals nothing and bumps nothing.
  test "clearing an override a position does not have leaves no entry and bumps nothing" do
    world = base_world(name: "Override Clear Portfolio")
    security = create_security!(name: "Quarry Bay Logistics AG", ticker: "QBL")
    core = bucket!("Core")
    basis = DataVersion.portfolio_basis(world.portfolio.id)

    override_entries = fn ->
      "position_bucket_override"
      |> entries("security_id", security.id)
      |> Enum.filter(&(&1.after["securities_account_id"] == world.depot.id))
    end

    assert Buckets.position_override(world.depot.id, security.id) == :inherit
    version = DataVersion.current(basis)

    assert :ok = Buckets.clear_position_override(owner(), world.depot, security)
    assert override_entries.() == []
    assert DataVersion.current(basis) == version

    assert :ok = Buckets.set_position_override(owner(), world.depot, security, [core.id])
    assert [set] = override_entries.()
    version = DataVersion.current(basis)

    assert :ok = Buckets.clear_position_override(owner(), world.depot, security)
    assert [cleared, ^set] = override_entries.()
    assert cleared.operation == :delete
    assert cleared.before["bucket_ids"] == [core.id]
    assert DataVersion.current(basis) > version
    version = DataVersion.current(basis)

    assert :ok = Buckets.clear_position_override(owner(), world.depot, security)
    assert [^cleared, ^set] = override_entries.()
    assert DataVersion.current(basis) == version
  end
end
