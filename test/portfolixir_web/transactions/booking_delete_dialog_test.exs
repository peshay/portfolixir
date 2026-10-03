defmodule PortfolixirWeb.Transactions.BookingDeleteDialogTest do
  # Sprint 18 U1 (#912), pick H2 = A, and the closing act's R5 and R6: the
  # delete dialog's own contract — `prepare/2` builds what it shows,
  # `delete/2` runs the confirmed delete — at the moments a page cannot
  # time: another writer deleting between the dialog's read and its write.
  # The other writer runs at an exact query through `Portfolixir.Interleave`
  # (the patch-coverage pass's race harness); its write commits to the
  # sandbox the way another connection's would.
  #
  # Every name, figure and date is synthetic.
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Interleave
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Splits
  alias PortfolixirWeb.Transactions.BookingDeleteDialog

  setup do
    world = base_world(name: "Hauptportfolio", cash_name: "Girokonto", depot_name: "Depot 1")
    other = base_world(name: "Sparplan-Portfolio", cash_name: "Tagesgeld", depot_name: "Depot 2")
    security = create_security!(name: "Kestrel Robotik SE", ticker: "KRS")
    buy = buy!(world, security, quantity: "10", price: "80", date: ~D[2026-09-01])
    buy!(other, security, quantity: "6", price: "80", date: ~D[2026-09-02])
    %{world: world, other: other, security: security, buy: buy}
  end

  defp agent, do: Actor.api_token_rw("synthetic-agent")

  defp split!(security) do
    {:ok, rows} =
      Splits.book_split(Actor.owner_ui(), %{
        security_id: security.id,
        date: ~D[2026-09-15],
        ratio_numerator: 2,
        ratio_denominator: 1
      })

    rows
  end

  # The one read of a booking by its id, outside any lock.
  defp row_read?(%{source: "transactions", query: query}),
    do: query =~ ~s{WHERE (t0."id" = $1)} and not (query =~ "FOR")

  defp row_read?(_metadata), do: false

  # The read of a split event's rows by its identity, outside any lock.
  defp event_read?(%{source: "transactions", query: query}),
    do: query =~ ~s{t0."type" = 'split'} and not (query =~ "FOR")

  defp event_read?(_metadata), do: false

  # User story (U1, #912; H2-A, A6):
  # As the operator confirming a delete while the agent deletes the same
  # booking,
  # I want "That transaction no longer exists." even when the agent's
  # delete lands between the dialog's read and its write,
  # so that the race reads as the row being gone, never as a crash.
  #
  # Acceptance criteria:
  # - A booking deleted right after the dialog re-read it answers :gone;
  #   one journal entry, the agent's.
  test "a booking deleted between the dialog's read and its delete is gone", %{buy: buy} do
    deleting = BookingDeleteDialog.prepare(buy, %{})

    assert {:gone, {:ok, _}} =
             Interleave.run(
               &row_read?/1,
               fn -> Ledger.delete_transaction(agent(), buy) end,
               fn -> BookingDeleteDialog.delete(Actor.owner_ui(), deleting) end
             )

    assert Ledger.get_transaction(buy.id) == nil
  end

  # User story (U1, #912; H2-A, A4; the closing act, R5):
  # As the operator confirming a split's delete while the agent deletes one
  # of its rows,
  # I want the split's other listed rows deleted all the same,
  # so that no portfolio keeps the event the dialog promised to remove.
  #
  # Acceptance criteria:
  # - The row the delete anchored on, deleted between the event's read and
  #   the lock: the delete reads the event again and removes the other row.
  # - A split whose every row is gone before the dialog is built gives no
  #   dialog (`prepare/2` answers nil).
  test "a split row deleted between the event's read and the lock is read again",
       %{security: security} do
    [row_a, row_b] = split!(security)
    deleting = BookingDeleteDialog.prepare(row_b, %{})

    {result, {:ok, _}} =
      Interleave.run(
        &event_read?/1,
        fn -> Ledger.delete_transaction(agent(), row_a) end,
        fn -> BookingDeleteDialog.delete(Actor.owner_ui(), deleting) end
      )

    assert {:ok, message} = result
    assert Phoenix.HTML.safe_to_string(message) =~ "Split deleted:"
    assert Splits.booked_on(security.id, ~D[2026-09-15]) == []

    assert BookingDeleteDialog.prepare(row_b, %{}) == nil
  end

  # User story (U1, #912; H2-A, A4 and A6; the closing act, R5):
  # As the operator confirming a split's delete that the agent first
  # extended and then deleted whole,
  # I want "That transaction no longer exists.",
  # so that a dialog with nothing left to show never opens anew.
  #
  # Acceptance criteria:
  # - The event gained a row (nothing deleted), and every row is deleted
  #   before the dialog is rebuilt: the delete answers :gone.
  test "a split changed and then deleted whole meanwhile is gone",
       %{security: security} do
    [row_a, _row_b] = split!(security)
    deleting = BookingDeleteDialog.prepare(row_a, %{})

    third = base_world(name: "Depot-Portfolio", cash_name: "Kasse", depot_name: "Depot 3")
    buy!(third, security, quantity: "5", price: "80", date: ~D[2026-09-03])
    [_row_c] = split!(security)

    rollback? = fn
      %{query: query} when is_binary(query) -> query =~ ~r/rollback/i
      _metadata -> false
    end

    assert {:gone, {:ok, [_, _, _]}} =
             Interleave.run(
               rollback?,
               fn -> Splits.delete_split(agent(), row_a) end,
               fn -> BookingDeleteDialog.delete(Actor.owner_ui(), deleting) end
             )

    assert Splits.booked_on(security.id, ~D[2026-09-15]) == []
  end
end
