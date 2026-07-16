defmodule Portfolixir.Portfolios.SnapshotsTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Journal
  alias Portfolixir.Portfolios.Snapshots

  # User story (Andi, 2026-07-16, ADR-0027):
  # As a local portfolio maintainer about to restructure my strategy,
  # I want to freeze "the depot state as of today" as a named snapshot of a
  # view scope — a pure ledger marker, copying no data —
  # so that I can later compare my real performance against having kept
  # exactly those holdings.
  #
  # Acceptance criteria:
  # - A snapshot is (name, view scope, as-of date); view NULL = everything.
  # - No transaction/quantity/price data is copied anywhere.
  # - The as-of date must not lie in the future.
  # - Names are unique per view scope.
  # - Create and delete are journaled (actor-first).
  # - Deleting a view removes its snapshots; "everything" snapshots survive.

  test "creates, lists and deletes a snapshot marker" do
    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Stocks"})

    {:ok, snapshot} =
      Snapshots.create_snapshot(Actor.owner_ui(), %{
        name: "Before restructuring",
        view_id: view.id,
        as_of: ~D[2026-07-01]
      })

    assert snapshot.name == "Before restructuring"
    assert snapshot.view_id == view.id
    assert snapshot.as_of == ~D[2026-07-01]

    {:ok, everything} =
      Snapshots.create_snapshot(Actor.owner_ui(), %{name: "All-in marker", as_of: ~D[2026-06-30]})

    assert everything.view_id == nil

    assert Enum.map(Snapshots.list_snapshots(), & &1.id) |> Enum.sort() ==
             Enum.sort([snapshot.id, everything.id])

    assert [_] = Snapshots.list_snapshots(view: view.id)

    {:ok, _} = Snapshots.delete_snapshot(Actor.owner_ui(), snapshot.id)
    assert Snapshots.list_snapshots(view: view.id) == []
  end

  test "rejects a future as-of date and duplicate names per scope" do
    tomorrow = Date.add(Date.utc_today(), 1)

    assert {:error, changeset} =
             Snapshots.create_snapshot(Actor.owner_ui(), %{name: "Future", as_of: tomorrow})

    assert %{as_of: [message]} = errors_on(changeset)
    assert message =~ "future"

    {:ok, _} =
      Snapshots.create_snapshot(Actor.owner_ui(), %{name: "Twice", as_of: ~D[2026-07-01]})

    assert {:error, changeset} =
             Snapshots.create_snapshot(Actor.owner_ui(), %{name: "Twice", as_of: ~D[2026-07-02]})

    assert %{name: _} = errors_on(changeset)
  end

  test "snapshot writes are journaled; deleting a view cascades its snapshots" do
    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Crypto"})

    {:ok, scoped} =
      Snapshots.create_snapshot(Actor.owner_ui(), %{
        name: "Scoped",
        view_id: view.id,
        as_of: ~D[2026-07-01]
      })

    {:ok, unscoped} =
      Snapshots.create_snapshot(Actor.owner_ui(), %{name: "Everything", as_of: ~D[2026-07-01]})

    assert [%{operation: :create}, %{operation: :create}] =
             Journal.list_entries(resource_type: "snapshot")

    {:ok, _} = Buckets.delete_view(Actor.owner_ui(), view)

    remaining = Snapshots.list_snapshots()
    assert Enum.map(remaining, & &1.id) == [unscoped.id]
    refute Enum.any?(remaining, &(&1.id == scoped.id))

    {:ok, _} = Snapshots.delete_snapshot(Actor.owner_ui(), unscoped.id)

    assert Enum.count(
             Journal.list_entries(resource_type: "snapshot"),
             &(&1.operation == :delete)
           ) == 1
  end
end
