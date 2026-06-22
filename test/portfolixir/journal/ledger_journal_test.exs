defmodule Portfolixir.LedgerJournalTest do
  use Portfolixir.DataCase, async: true

  # User story:
  # As an operator who let an agent write to my ledger,
  # I want every committed transaction write recorded in the append-only journal,
  # so that any booking — created, edited, or deleted, by a human or an agent —
  # is attributable and reversible by inspection (FR-28 / NFR-2, ADR-0017,
  # Ledger slice: the transactions crown jewel).
  #
  # Acceptance criteria:
  # - create_transaction/2 records one create entry attributed to the actor.
  # - update_transaction/3 records before and after snapshots.
  # - delete_transaction/2 journals the deletion with a before snapshot.
  # - A rejected changeset commits nothing and journals nothing.
  # - The `transactions` table is guard-armed: a write that bypasses the
  #   journaled context path is refused by the database.

  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo
  alias Portfolixir.WorldFixtures

  setup do
    world = WorldFixtures.base_world(name: "Ledger Co")
    security = WorldFixtures.create_security!(name: "Held Co", ticker: "HLD")
    %{world: world, security: security}
  end

  defp buy_attrs(world, security, overrides \\ %{}) do
    Map.merge(
      %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-02-01],
        quantity: "10",
        price: "100",
        currency_code: "EUR"
      },
      overrides
    )
  end

  test "create_transaction/2 records a create entry attributed to the actor", ctx do
    actor = Actor.api_token_rw("ledger-token")
    {:ok, tx} = Ledger.create_transaction(actor, buy_attrs(ctx.world, ctx.security))

    assert [entry] = Journal.list_entries(resource_type: "transaction", operation: :create)
    assert entry.actor_type == :api_token_rw
    assert entry.actor_label == "ledger-token"
    assert entry.resource_id == to_string(tx.id)
    assert entry.before == nil
    assert entry.after["type"] == "buy"
  end

  test "update_transaction/3 records before and after snapshots", ctx do
    {:ok, tx} = Ledger.create_transaction(Actor.owner_ui(), buy_attrs(ctx.world, ctx.security))

    {:ok, _} = Ledger.update_transaction(Actor.owner_ui(), tx, %{quantity: "12"})

    assert [entry] = Journal.list_entries(resource_type: "transaction", operation: :update)
    assert entry.before["quantity"] == "10"
    assert entry.after["quantity"] == "12"
    assert entry.resource_id == to_string(tx.id)
  end

  test "delete_transaction/2 journals the deletion with a before snapshot", ctx do
    {:ok, tx} = Ledger.create_transaction(Actor.owner_ui(), buy_attrs(ctx.world, ctx.security))

    {:ok, _} = Ledger.delete_transaction(Actor.owner_ui(), tx)

    assert [entry] = Journal.list_entries(resource_type: "transaction", operation: :delete)
    assert entry.resource_id == to_string(tx.id)
    assert entry.before["type"] == "buy"
    assert Ledger.get_transaction(tx.id) == nil
  end

  test "a rejected changeset commits nothing and journals nothing", ctx do
    actor = Actor.owner_ui()
    before = Ledger.count_transactions()

    assert {:error, %Ecto.Changeset{}} =
             Ledger.create_transaction(
               actor,
               buy_attrs(ctx.world, ctx.security, %{type: "bogus"})
             )

    assert Journal.list_entries(resource_type: "transaction") == []
    assert Ledger.count_transactions() == before
  end

  test "a direct unactored write to transactions is refused by the database", ctx do
    assert_raise Postgrex.Error, fn ->
      Repo.insert!(Transaction.changeset(%Transaction{}, buy_attrs(ctx.world, ctx.security)))
    end
  end
end
