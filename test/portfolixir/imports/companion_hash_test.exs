defmodule Portfolixir.Imports.CompanionHashTest do
  # E25 S5, F37 (risk-tier: idempotency, ADR-0036): a tax refund the parser
  # splits off a row is hashed with that row and books or skips with it.
  use Portfolixir.DataCase, async: false

  import Ecto.Query

  alias Portfolixir.Actor
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Entry
  alias Portfolixir.Imports.ImportHash
  alias Portfolixir.Imports.Preview
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios
  alias Portfolixir.Repo

  @security %{isin: "DE000ACME008", wkn: nil, ticker: nil, name: "Synthetic AG", currency: "EUR"}

  defp portfolio! do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Import target",
        base_currency_code: "EUR"
      })

    portfolio
  end

  defp refund(row, amount) do
    %Entry{
      source_row: "#{row}.tax_refund.1",
      kind: "tax_refund",
      date: ~D[2024-05-02],
      currency_code: "EUR",
      gross_amount: Decimal.new(amount),
      fees: Decimal.new(0),
      taxes: Decimal.new(0),
      security: @security,
      pp_portfolio_name: "Depot",
      pp_account_name: "Cash",
      note: "Auto-split tax refund from row #{row}"
    }
  end

  defp buy(row) do
    %Entry{
      source_row: row,
      kind: "buy",
      date: ~D[2024-05-01],
      currency_code: "EUR",
      gross_amount: Decimal.new("1000"),
      fees: Decimal.new(0),
      taxes: Decimal.new(0),
      quantity: Decimal.new("20"),
      price: Decimal.new("50"),
      security: @security,
      pp_portfolio_name: "Depot",
      pp_account_name: "Cash"
    }
  end

  defp sell(row, quantity, refund_amount) do
    %Entry{
      source_row: row,
      kind: "sell",
      date: ~D[2024-05-02],
      currency_code: "EUR",
      gross_amount: Decimal.mult(Decimal.new(quantity), Decimal.new("50")),
      fees: Decimal.new(0),
      taxes: Decimal.new(0),
      quantity: Decimal.new(quantity),
      price: Decimal.new("50"),
      security: @security,
      pp_portfolio_name: "Depot",
      pp_account_name: "Cash",
      companion_entries: [refund(row, refund_amount)]
    }
  end

  defp refunds(portfolio) do
    from(t in Transaction,
      where: t.portfolio_id == ^portfolio.id and t.type == "tax_refund",
      select: t.import_hash
    )
    |> Repo.all()
  end

  defp count(portfolio),
    do: Repo.aggregate(from(t in Transaction, where: t.portfolio_id == ^portfolio.id), :count)

  # User story (E25 S5, F37):
  # As the operator whose export splits a tax refund off two different sales,
  # I want both refunds booked,
  # so that a refund is never skipped as "already imported" because another
  # sale carried an equal one.
  #
  # Acceptance criteria:
  # - Two different parents with equal refunds book both refunds, each under
  #   its own hash.
  # - Re-importing the same file books nothing.
  test "two different parents with equal refunds book both" do
    portfolio = portfolio!()
    preview = %Preview{entries: [buy(1), sell(2, "5", "12.00"), sell(3, "10", "12.00")]}

    assert {:ok, result} = Imports.apply(preview, %{portfolio_id: portfolio.id})
    assert result.created_transactions == 5
    assert result.duplicate_entries == []
    assert [a, b] = refunds(portfolio)
    refute a == b

    assert {:ok, again} = Imports.apply(preview, %{portfolio_id: portfolio.id})
    assert again.created_transactions == 0
    assert length(again.duplicate_entries) == 5
    assert count(portfolio) == 5
  end

  # User story (E25 S5, F37):
  # As the operator re-importing an export I imported before this change,
  # I want a refund stored under the old formula recognised with its sale,
  # so that nothing books twice.
  #
  # Acceptance criteria:
  # - A companion whose stored hash is the one the Sprint 15 formula gave it
  #   books nothing on re-import, because its parent is already booked, and
  #   the preview counts both rows as already imported.
  test "a companion stored under the Sprint 15 formula is recognised on re-import" do
    portfolio = portfolio!()
    preview = %Preview{entries: [buy(1), sell(2, "5", "12.00")]}

    assert {:ok, %{created_transactions: 3}} =
             Imports.apply(preview, %{portfolio_id: portfolio.id})

    # The refund as an import before this change stored it: hashed as a row
    # of its own.
    sprint15 = ImportHash.compute(refund(2, "12.00"), portfolio.id)

    {:ok, {1, _}} =
      Repo.transaction(fn ->
        Repo.query!("SELECT set_config('portfolixir.journal_actor', 'test', true)")

        from(t in Transaction, where: t.portfolio_id == ^portfolio.id and t.type == "tax_refund")
        |> Repo.update_all(set: [import_hash: sprint15])
      end)

    assert %{total: %{hash: 3, new: 0}} =
             Imports.reimport_counts(preview, portfolio_id: portfolio.id)

    assert {:ok, again} = Imports.apply(preview, %{portfolio_id: portfolio.id})
    assert again.created_transactions == 0
    assert Enum.map(again.duplicate_entries, & &1.layer) == [:hash, :hash, :hash]
    assert count(portfolio) == 3
  end

  # User story (E25 S5, F37):
  # As the operator,
  # I want a split-off refund to book only with the row it came from,
  # so that it never books when its row is skipped.
  #
  # Acceptance criteria:
  # - A companion of a row that cannot be imported is skipped and listed with
  #   the reason, and creates nothing.
  test "a companion is skipped with a parent that is not imported" do
    portfolio = portfolio!()
    unimportable = %{sell(2, "5", "7.50") | gross_amount: nil, kind: "fee"}

    assert {:ok, result} =
             Imports.apply(%Preview{entries: [unimportable]}, %{portfolio_id: portfolio.id})

    assert result.created_transactions == 0
    assert [%{row: 2}, %{row: "2.tax_refund.1", reason: reason}] = result.skipped_entries
    assert reason =~ "row 2"
    assert count(portfolio) == 0
  end
end
