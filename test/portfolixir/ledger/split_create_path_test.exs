defmodule Portfolixir.Ledger.SplitCreatePathTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Splits
  alias Portfolixir.Ledger.Transaction

  setup do
    world = base_world(name: "Split Path World", cash_name: "SP Cash", depot_name: "SP Depot")
    security = create_security!(name: "Synthetic Split Path", ticker: "SSP")
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-05])
    %{world: world, security: security}
  end

  defp split_rows, do: Repo.all(from(t in Transaction, where: t.type == "split"))

  # User story (security review 2026-10-12, K10):
  # As the operator whose splits re-base a security's quotes for every
  # portfolio,
  # I want the ledger's generic create path to refuse a split-typed booking,
  # as its update path already does,
  # so that a split is only ever booked through the split flow and its checks.
  #
  # Acceptance criteria:
  # - Ledger.create_transaction with type split answers a changeset error on
  #   :type naming the split flow; nothing is stored.
  # - Splits.book_split still books its rows.
  test "the generic create path refuses a split; the split flow still books one", %{
    world: world,
    security: security
  } do
    assert {:error, changeset} =
             Ledger.create_transaction(Actor.owner_ui(), %{
               type: "split",
               portfolio_id: world.portfolio.id,
               security_id: security.id,
               date: ~D[2026-02-01],
               currency_code: "EUR",
               split_ratio_numerator: 3,
               split_ratio_denominator: 1
             })

    assert {message, _meta} = changeset.errors[:type]
    assert message =~ "POST /api/v1/splits"
    assert split_rows() == []

    assert {:ok, [booked]} =
             Splits.book_split(Actor.owner_ui(), %{
               security_id: security.id,
               date: ~D[2026-02-01],
               ratio_numerator: 2,
               ratio_denominator: 1
             })

    assert [%Transaction{id: id}] = split_rows()
    assert id == booked.id
  end
end
