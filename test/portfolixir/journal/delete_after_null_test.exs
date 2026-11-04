defmodule Portfolixir.Journal.DeleteAfterNullTest do
  # ADR-0017, amendment of 2026-11-04 (#1378; risk tier: an audit record's
  # shape, ADR-0036): from the cut-over on, every `delete` entry stores
  # `after: null`, whatever its writer, because after a delete nothing
  # stands; `before` stays the full record as stored under the write's lock.
  # `Journal.record/3` sets it in one place. One test per writer kind: a row
  # delete, a set delete, and a cascading delete through `Lifecycle.Delete`.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Classifications
  alias Portfolixir.Classifications.Assignment
  alias Portfolixir.Journal
  alias Portfolixir.Journal.Serializer
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.WorldFixtures

  defp agent, do: Actor.api_token_rw("synthetic-agent")

  defp deletes(resource_type) do
    Journal.list_entries(resource_type: resource_type, operation: :delete)
  end

  defp tag_bucket!(name) do
    {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: name, dimension: "tag"})
    bucket
  end

  # User story:
  # As the agent reading the audit journal,
  # I want a row delete's entry to say that nothing stands after it,
  # so that `after` means "what stands after the write" for every operation
  # and the deleted record is read from `before`.
  #
  # Acceptance criteria:
  # - The delete entry of a booking stores `after: null`.
  # - Its `before` is the booking as stored before the delete, unchanged.
  test "a row delete stores after null and the stored row as before" do
    world = WorldFixtures.base_world()
    security = WorldFixtures.create_security!(name: "Synthetic Row ETF", ticker: "SRE")

    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-02-01],
        quantity: "10",
        price: "100",
        currency_code: "EUR"
      })

    stored = Serializer.snapshot(Repo.get!(Transaction, tx.id))

    assert {:ok, _} = Ledger.delete_transaction(agent(), tx)

    assert [entry] = deletes("transaction")
    assert entry.resource_id == to_string(tx.id)
    assert entry.after == nil
    assert entry.before == stored
  end

  # User story:
  # As the agent reading the audit journal,
  # I want a set's delete (a position's bucket override cleared, a range of
  # manual quotes released) to say that nothing stands after it,
  # so that an emptied set is not mistaken for a set that still stands.
  #
  # Acceptance criteria:
  # - Clearing a position's override stores `after: null`; its `before` is
  #   the set as stored, naming the position.
  # - Releasing manual quotes stores `after: null`; its `before` is the rows
  #   it released.
  test "a set delete stores after null and the stored set as before" do
    world = WorldFixtures.base_world()
    family = tag_bucket!("Family")
    security = WorldFixtures.create_security!(name: "Synthetic Set ETF", ticker: "SSE")

    :ok = Buckets.set_position_override(Actor.owner_ui(), world.depot, security, [family.id])
    assert :ok = Buckets.clear_position_override(agent(), world.depot, security)

    assert [override] = deletes("position_bucket_override")
    assert override.after == nil

    assert override.before == %{
             "id" => nil,
             "securities_account_id" => world.depot.id,
             "security_id" => security.id,
             "bucket_ids" => [family.id]
           }

    {:ok, _} =
      Catalog.upsert_quotes(agent(), security.id, [
        %{"date" => "2026-03-02", "close" => "42.50"}
      ])

    assert {:ok, %{released: [~D[2026-03-02]]}} =
             Catalog.release_manual_quotes(agent(), security.id, ~D[2026-03-01], ~D[2026-03-05])

    assert [release] = deletes("security_quotes")
    assert release.resource_id == to_string(security.id)
    assert release.after == nil
    assert release.before["security_id"] == security.id

    assert [%{"date" => "2026-03-02", "source" => "manual", "close" => close}] =
             release.before["quotes"]

    assert Decimal.equal?(Decimal.new(close), Decimal.new("42.50"))
  end

  # User story:
  # As the agent reading the audit journal after a security was deleted,
  # I want every entry the delete wrote, its memberships' and its own, to
  # store `after: null`,
  # so that a cascading delete reads like every other delete.
  #
  # Acceptance criteria:
  # - The category assignment's, the position override's and the security's
  #   own delete entries all store `after: null`.
  # - The security's `before` is the row as stored before the delete, and the
  #   assignment's is the assignment as stored.
  test "a cascading delete through Lifecycle.Delete stores after null on every entry" do
    world = WorldFixtures.base_world()
    family = tag_bucket!("Family")
    security = WorldFixtures.create_security!(name: "Synthetic Mistake ETF", ticker: "SME")

    {:ok, strategy} = Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    {:ok, core} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: strategy.id,
        name: "Core"
      })

    {:ok, _} =
      Classifications.assign_security(Actor.owner_ui(), security.id, strategy.id, core.id)

    :ok = Buckets.set_position_override(Actor.owner_ui(), world.depot, security, [family.id])

    stored_security = Serializer.snapshot(Repo.get!(Security, security.id))

    stored_assignment =
      Serializer.snapshot(
        Repo.get_by!(Assignment, security_id: security.id, classification_id: strategy.id)
      )

    assert {:ok, _} = Catalog.delete_security(agent(), security)

    assert [assignment] = deletes("security_category_assignment")
    assert [override] = deletes("position_bucket_override")
    assert [row] = deletes("security")

    for entry <- [assignment, override, row] do
      assert entry.after == nil
      assert entry.actor_type == :api_token_rw
    end

    assert row.resource_id == to_string(security.id)
    assert row.before == stored_security
    assert assignment.before == stored_assignment
    assert override.before["security_id"] == security.id
    assert override.before["securities_account_id"] == world.depot.id
  end
end
