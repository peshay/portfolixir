defmodule Portfolixir.Ledger.SplitDeleteAtomicityTest do
  # Sprint 18 U1 (#912), ADR-0028 §1; RISK-TIER (ADR-0036): the whole-split
  # delete is one write. A failure while removing any row of the event leaves
  # every row standing and journals nothing — the half state the row-by-row
  # delete used to leave between two calls never commits.
  #
  # Nothing in a correct delete fails, so the test makes one fail: a trigger,
  # created inside the test's own transaction and rolled back with it, raises
  # on the delete of the event's second row.
  #
  # async: false — creating a trigger on `transactions` takes a lock every
  # concurrent test on the ledger would wait on.
  #
  # Every name, figure and date is synthetic.
  use Portfolixir.DataCase, async: false

  import Ecto.Query

  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Ledger.Splits
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo

  # User story (U1, #912; ADR-0028 §1):
  # As the operator deleting a split booked in two portfolios,
  # I want the delete to remove both rows or neither,
  # so that a failure can never leave one portfolio scaled and the other not.
  #
  # Acceptance criteria:
  # - When the delete of any row of the event fails, the call fails, every
  #   row of the event is still stored and no delete is journaled.
  test "a failure on one row deletes nothing" do
    world_a = base_world(name: "Hauptportfolio", cash_name: "Girokonto", depot_name: "Depot 1")

    world_b =
      base_world(name: "Sparplan-Portfolio", cash_name: "Tagesgeld", depot_name: "Depot 2")

    security = create_security!(name: "Kestrel Robotik SE", ticker: "KRS")
    buy!(world_a, security, quantity: "40", price: "62.50", date: ~D[2026-09-01])
    buy!(world_b, security, quantity: "12", price: "60", date: ~D[2026-09-02])

    {:ok, [first, second]} =
      Splits.book_split(Actor.owner_ui(), %{
        security_id: security.id,
        date: ~D[2026-09-15],
        ratio_numerator: 2,
        ratio_denominator: 1
      })

    refuse_delete_of!(second.id)

    assert_raise Postgrex.Error, ~r/synthetic refusal/, fn ->
      Splits.delete_split(Actor.owner_ui(), first)
    end

    stored =
      Repo.all(
        from(t in Transaction,
          where: t.type == "split" and t.security_id == ^security.id,
          select: t.id,
          order_by: t.id
        )
      )

    assert stored == [first.id, second.id]
    assert Journal.list_entries(resource_type: "transaction", operation: :delete) == []
  end

  defp refuse_delete_of!(id) when is_integer(id) do
    Repo.query!("""
    CREATE FUNCTION synthetic_refused_delete() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      RAISE EXCEPTION 'synthetic refusal of row %', OLD.id;
    END
    $$
    """)

    Repo.query!("""
    CREATE TRIGGER synthetic_refused_delete BEFORE DELETE ON transactions
    FOR EACH ROW WHEN (OLD.id = #{id}) EXECUTE FUNCTION synthetic_refused_delete()
    """)

    :ok
  end
end
