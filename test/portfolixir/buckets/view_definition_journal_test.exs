defmodule Portfolixir.Buckets.ViewDefinitionJournalTest do
  # E25 S6 (#891), F45, G29, G19 and decision T-10: a policy rule in force is
  # evaluated against a view's definition, and the definition changed with
  # no journal entry — through a view edit, a bucket-set edit, or the
  # database cascade of a bucket delete, which also turned an explicit
  # position override that lost its last bucket into inheritance.
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Journal
  alias Portfolixir.Portfolios.PolicyRules

  defp owner, do: Actor.owner_ui()

  # Bucket and view names are unique instance-wide, so each is made unique
  # here: two async tests inserting one name would wait on each other.
  defp unique(name), do: "#{name} #{System.unique_integer([:positive])}"

  defp bucket!(name, dimension \\ "tag") do
    {:ok, bucket} = Buckets.create_bucket(owner(), %{name: unique(name), dimension: dimension})
    bucket
  end

  defp view!(name, attrs \\ %{}) do
    {:ok, view} = Buckets.create_view(owner(), Map.put(attrs, :name, unique(name)))
    view
  end

  defp view_entries(view_id) do
    Journal.list_entries(resource_type: "view", resource_id: to_string(view_id))
  end

  # User story:
  # As the operator whose policy rules read a view,
  # I want every change to a view's definition journaled with the sets before
  # and after it,
  # so that a finding that shifts because the view changed has an audit
  # trace that says how.
  #
  # Acceptance criteria:
  # - Setting a view's buckets journals one `view` update entry, filed under
  #   the view, whose before and after carry include_all and both sets.
  # - Editing the view (name, include_all) journals one such entry too.
  # - Resending the same definition journals nothing.
  test "update_view and set_view_buckets each leave a journal entry with the prior and new sets" do
    core = bucket!("Core")
    satellite = bucket!("Satellite")
    view = view!("Strategy", %{include_all: false})

    assert :ok = Buckets.set_view_buckets(owner(), view, [core.id], [satellite.id])

    assert [set_entry] = view_entries(view.id)
    assert set_entry.operation == :update
    assert set_entry.actor_type == :owner_ui
    assert set_entry.before["include_bucket_ids"] == []
    assert set_entry.before["exclude_bucket_ids"] == []
    assert set_entry.after["include_bucket_ids"] == [core.id]
    assert set_entry.after["exclude_bucket_ids"] == [satellite.id]
    assert set_entry.after["include_all"] == false

    renamed = unique("Strategy all")

    assert {:ok, _} = Buckets.update_view(owner(), view, %{name: renamed, include_all: true})

    assert [edit_entry, ^set_entry] = view_entries(view.id)
    assert edit_entry.before["name"] == view.name
    assert edit_entry.before["include_all"] == false
    assert edit_entry.after["name"] == renamed
    assert edit_entry.after["include_all"] == true
    assert edit_entry.after["exclude_bucket_ids"] == [satellite.id]

    assert :ok = Buckets.set_view_buckets(owner(), view, [core.id], [satellite.id])
    assert length(view_entries(view.id)) == 2
  end

  # User story:
  # As the operator whose rule reads a view,
  # I want deleting a bucket that the view includes to leave the view's prior
  # sets in the journal,
  # so that the rule's changed finding is traceable to the delete.
  #
  # Acceptance criteria:
  # - The bucket is removed from the view's include set through the journaled
  #   set writer: a `view` entry holds the prior and the new sets.
  # - The bucket's own delete entry names every view and assignment it was
  #   removed from, as its before-image.
  # - No new refusal: the delete succeeds although a rule reads the view.
  test "deleting a bucket in a rule-referenced view's include set journals the view's prior sets" do
    world = base_world(name: "Rule Portfolio")
    security = create_security!(name: "Kestrel Industrial Group NV", ticker: "KIG")
    core = bucket!("Core")
    tactical = bucket!("Tactical")
    view = view!("Long term", %{include_all: false})
    :ok = Buckets.set_view_buckets(owner(), view, [core.id, tactical.id], [])

    {:ok, _rule} =
      PolicyRules.create_rule(owner(), %{
        portfolio_id: world.portfolio.id,
        view_id: view.id,
        name: "Single name at most 10 %",
        version: %{
          subject_type: "security",
          security_id: security.id,
          measure: "weight",
          kind: "cap",
          threshold: "10",
          severity: "hard"
        }
      })

    assert {:ok, _} = Buckets.delete_bucket(owner(), tactical)

    assert [cascade | _] = view_entries(view.id)
    assert cascade.before["include_bucket_ids"] == Enum.sort([core.id, tactical.id])
    assert cascade.after["include_bucket_ids"] == [core.id]

    assert [deleted] =
             Journal.list_entries(
               resource_type: "bucket",
               resource_id: to_string(tactical.id),
               operation: :delete
             )

    assert deleted.before["name"] == tactical.name
    assert deleted.before["memberships"]["view_include"] == [view.id]
    assert deleted.before["memberships"]["view_exclude"] == []
  end

  # User story:
  # As the operator who gave a position its own buckets,
  # I want a position whose only specific bucket is deleted to stay at
  # "no buckets (excluded)",
  # so that it does not silently start inheriting its depot's buckets and
  # appear in views that did not contain it.
  #
  # Acceptance criteria:
  # - An override that loses its last bucket is explicit-empty afterwards,
  #   not inherit; one that keeps another bucket keeps it.
  # - The depot's default set and the cash account's set lose the bucket.
  # - Each affected owner gets its own journal entry: the depot's default
  #   set, the cash account's set, and each rewritten position override.
  test "an override losing its last bucket stays explicit-empty, and each affected owner is journaled" do
    world = base_world(name: "Override Portfolio")
    only = create_security!(name: "Harbor Light Utilities SE", ticker: "HLU")
    both = create_security!(name: "Kestrel Industrial Group NV", ticker: "KIG")
    tactical = bucket!("Tactical")
    long_term = bucket!("Long term")

    :ok = Buckets.set_depot_default_buckets(owner(), world.depot, [tactical.id, long_term.id])
    :ok = Buckets.set_cash_account_buckets(owner(), world.cash, [tactical.id])
    :ok = Buckets.set_position_override(owner(), world.depot, only, [tactical.id])

    :ok =
      Buckets.set_position_override(owner(), world.depot, both, [tactical.id, long_term.id])

    before_depot = length(Journal.list_entries(resource_type: "depot_bucket_assignment"))
    before_cash = length(Journal.list_entries(resource_type: "cash_account_bucket_assignment"))
    before_override = length(Journal.list_entries(resource_type: "position_bucket_override"))

    assert {:ok, _} = Buckets.delete_bucket(owner(), tactical)

    assert Buckets.position_override(world.depot.id, only.id) == :explicit_empty
    assert Buckets.position_override(world.depot.id, both.id) == {:explicit, [long_term.id]}
    assert Buckets.depot_default_bucket_ids(world.depot.id) == [long_term.id]
    assert Buckets.cash_account_bucket_ids(world.cash.id) == []

    assert length(Journal.list_entries(resource_type: "depot_bucket_assignment")) ==
             before_depot + 1

    assert length(Journal.list_entries(resource_type: "cash_account_bucket_assignment")) ==
             before_cash + 1

    assert length(Journal.list_entries(resource_type: "position_bucket_override")) ==
             before_override + 2

    assert [deleted] =
             Journal.list_entries(
               resource_type: "bucket",
               resource_id: to_string(tactical.id),
               operation: :delete
             )

    memberships = deleted.before["memberships"]
    assert memberships["depot_defaults"] == [world.depot.id]
    assert memberships["cash_accounts"] == [world.cash.id]

    assert memberships["position_overrides"] ==
             Enum.sort([
               %{"securities_account_id" => world.depot.id, "security_id" => only.id},
               %{"securities_account_id" => world.depot.id, "security_id" => both.id}
             ])
  end

  # User story (E25 S6 review round, G19/T-10):
  # As the operator whose position override was stored before the exclusive
  # scope rule held for overrides,
  # I want deleting an unrelated tag bucket to go through,
  # so that a set the rule would refuse today never blocks a delete that
  # only removes a bucket from it.
  #
  # Acceptance criteria:
  # - The delete succeeds; the override keeps its other buckets, journaled.
  # - Removing a bucket never re-checks the exclusive dimension, since it
  #   cannot add a conflict; the remaining buckets must still exist.
  test "a stored set that breaks the exclusive dimension does not block a bucket delete" do
    world = base_world(name: "Legacy Portfolio")
    security = create_security!(name: "Harbor Light Utilities SE", ticker: "HLU")
    scope_one = bucket!("Scope one", "scope")
    scope_two = bucket!("Scope two", "scope")
    tag = bucket!("Tag")

    legacy_override!(world.depot.id, security.id, [scope_one.id, scope_two.id, tag.id])

    assert {:ok, _} = Buckets.delete_bucket(owner(), tag)

    assert Buckets.position_override(world.depot.id, security.id) ==
             {:explicit, Enum.sort([scope_one.id, scope_two.id])}

    assert {:error, :exclusive_bucket_conflict} =
             Buckets.set_position_override(owner(), world.depot, security, [
               scope_one.id,
               scope_two.id
             ])
  end

  # User story (E25 S6 review round, M2):
  # As the operator setting a view's buckets while someone deletes one of them,
  # I want the write refused as naming a bucket that no longer exists,
  # so that it never fails with a server error.
  #
  # Acceptance criteria:
  # - The buckets are checked under the view's lock, read FOR SHARE: a bucket
  #   deleted between the page's read and the write answers
  #   `{:error, :bucket_ids}` and nothing is written.
  test "a bucket deleted while a view's sets are written answers bucket_ids" do
    view = view!("Racing view", %{include_all: false})
    kept = bucket!("Kept")
    doomed = bucket!("Doomed")

    result =
      with_bucket_deleted_after_view_lock(doomed, fn ->
        Buckets.set_view_buckets(owner(), view, [kept.id, doomed.id], [])
      end)

    assert result == {:error, :bucket_ids}
    assert view_entries(view.id) == []
  end

  # A concurrent delete that commits after the page read the buckets and
  # before the write reads them: the hook deletes the bucket right after the
  # write has locked its view, in the same transaction.
  defp with_bucket_deleted_after_view_lock(bucket, fun) do
    test_pid = self()
    handler = "view-bucket-race-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler,
        [:portfolixir, :repo, :query],
        fn _event, _measurements, %{query: query}, _config ->
          if self() == test_pid and query =~ ~r/FROM "views".*FOR NO KEY UPDATE/s and
               Process.get(:deleted) == nil do
            Process.put(:deleted, true)
            {:ok, _} = Buckets.delete_bucket(owner(), bucket)
          end
        end,
        nil
      )

    try do
      fun.()
    after
      :telemetry.detach(handler)
    end
  end

  # A set as a writer before the fix round stored it: rows inserted raw.
  defp legacy_override!(depot_id, security_id, bucket_ids) do
    {:ok, _} =
      Repo.transaction(fn ->
        Repo.query!("SELECT set_config('portfolixir.journal_actor', 'test', true)")

        Repo.insert_all(
          Portfolixir.Buckets.PositionBucketOverride,
          Enum.map(
            bucket_ids,
            &%{securities_account_id: depot_id, security_id: security_id, bucket_id: &1}
          )
        )
      end)
  end

  test "a bucket or a view deleted in the meantime answers not found" do
    bucket = bucket!("Gone")
    view = view!("Gone view")

    assert {:ok, _} = Buckets.delete_bucket(owner(), bucket)
    assert {:error, :not_found} = Buckets.delete_bucket(owner(), bucket)

    assert {:ok, _} = Buckets.delete_view(owner(), view)
    assert {:error, :not_found} = Buckets.update_view(owner(), view, %{name: "Back"})
    assert {:error, :not_found} = Buckets.set_view_buckets(owner(), view, [], [])
    assert {:error, :not_found} = Buckets.delete_view(owner(), view)
  end
end
