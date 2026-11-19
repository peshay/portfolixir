defmodule Portfolixir.Ledger.TaxesCheckTest do
  # Sprint 30 plan, A4 (#1356; risk tier: stored data): a transaction's
  # `taxes` is never negative. The changeset already refuses a negative
  # value (a refunded tax is its own `tax_refund` transaction);
  # `transactions_taxes_non_negative_check` now refuses it at
  # the database too, for a writer that bypasses the changeset, and the
  # changeset maps the constraint so such a refusal is a changeset error,
  # never a raised one. The migration's guard over stored rows is covered by
  # test/portfolixir/seeded_upgrade/taxes_check_test.exs.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.WorldFixtures

  @constraint "transactions_taxes_non_negative_check"

  # User story:
  # As the maintainer of the ledger,
  # I want the database itself to refuse a transaction with negative taxes,
  # so that no writer, present or future, stores a second representation of
  # a refunded tax beside the tax_refund kind.
  #
  # Acceptance criteria:
  # - A raw insert of a deposit with taxes of -1 is refused with a check
  #   violation naming the taxes constraint.
  # - The same insert with taxes of 0 is stored.
  test "the database refuses negative taxes from a writer that bypasses the changeset" do
    world = WorldFixtures.base_world(name: "Taxes Check World")

    error =
      assert_raise Postgrex.Error, fn ->
        journaled_insert!(deposit_row(world, Decimal.new("-1")))
      end

    assert error.postgres.code == :check_violation
    assert error.postgres.constraint == @constraint

    assert {1, _} = journaled_insert!(deposit_row(world, Decimal.new("0")))
  end

  # User story:
  # As the agent whose write reaches the database without the changeset's
  # sign rule having run on its final value,
  # I want the refusal answered as a changeset error on `taxes`,
  # so that I get the documented 422 naming the tax_refund remedy, not a 500.
  #
  # Acceptance criteria:
  # - A changeset whose taxes become -1 after validation is refused by the
  #   database, and `Repo.insert/1` answers `{:error, changeset}` with the
  #   error on `taxes` naming the tax_refund remedy.
  test "the changeset maps the database's refusal to an error on taxes" do
    world = WorldFixtures.base_world(name: "Taxes Mapping World")

    changeset =
      %Transaction{}
      |> Transaction.changeset(%{
        type: "deposit",
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        currency_code: "EUR",
        date: ~D[2026-02-01],
        gross_amount: Decimal.new("250")
      })
      |> Ecto.Changeset.force_change(:taxes, Decimal.new("-1"))

    assert changeset.valid?

    assert {:error, refused} =
             Repo.transaction(fn ->
               Repo.query!("SELECT set_config('portfolixir.journal_actor', 'owner_ui', true)")

               case Repo.insert(changeset) do
                 {:ok, stored} -> stored
                 {:error, refused} -> Repo.rollback(refused)
               end
             end)

    assert %{taxes: [message]} = errors_on(refused)
    assert message =~ "must be greater than or equal to 0"
    assert message =~ "tax_refund"
  end

  # --- helpers ---------------------------------------------------------------

  defp deposit_row(world, taxes) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    %{
      type: "deposit",
      portfolio_id: world.portfolio.id,
      cash_account_id: world.cash.id,
      currency_code: "EUR",
      date: ~D[2026-02-01],
      gross_amount: Decimal.new("250"),
      fees: Decimal.new("0"),
      taxes: taxes,
      inserted_at: now,
      updated_at: now
    }
  end

  # `transactions` is journal-armed: a raw write names an actor the way the
  # journal seam does.
  defp journaled_insert!(row) do
    {:ok, result} =
      Repo.transaction(fn ->
        Repo.query!("SELECT set_config('portfolixir.journal_actor', 'owner_ui', true)")
        Repo.insert_all(Transaction, [row])
      end)

    result
  end
end
