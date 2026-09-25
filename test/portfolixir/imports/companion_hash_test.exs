defmodule Portfolixir.Imports.CompanionHashTest do
  # E25 S5, F37 (risk-tier: idempotency, ADR-0036): a tax refund the parser
  # splits off a row is hashed with that row and checked by its own hashes.
  use Portfolixir.DataCase, async: false

  import Ecto.Query

  alias Portfolixir.Actor
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Entry
  alias Portfolixir.Imports.ImportHash
  alias Portfolixir.Imports.Preview
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios
  alias Portfolixir.Repo

  @security %{isin: "DE000ACME008", wkn: nil, ticker: nil, name: "Synthetic AG", currency: "EUR"}

  defp portfolio! do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Import target #{System.unique_integer([:positive])}",
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

  defp types(portfolio) do
    from(t in Transaction,
      where: t.portfolio_id == ^portfolio.id,
      order_by: t.id,
      select: {t.type, t.gross_amount}
    )
    |> Repo.all()
    |> Enum.map(fn {type, amount} ->
      {type, amount |> Decimal.normalize() |> Decimal.to_string(:normal)}
    end)
  end

  defp store_refund_under_sprint15!(portfolio, entry) do
    sprint15 = ImportHash.compute(entry, portfolio.id)

    {:ok, {1, _}} =
      Repo.transaction(fn ->
        Repo.query!("SELECT set_config('portfolixir.journal_actor', 'test', true)")

        from(t in Transaction, where: t.portfolio_id == ^portfolio.id and t.type == "tax_refund")
        |> Repo.update_all(set: [import_hash: sprint15])
      end)
  end

  # User story (E25 S5 review round, F37):
  # As the operator who deleted a sale by hand and imports the export again,
  # I want the sale booked again and its refund, still stored, left alone,
  # so that the import neither fails nor books the refund twice.
  #
  # Acceptance criteria:
  # - With the refund stored under either hash formula, the re-import books
  #   the sale only and lists the refund as already booked (layer hash).
  # - The preview counts the sale as new and the refund as already booked.
  test "a sale deleted by hand books again alone, its refund stored under either formula" do
    for formula <- [:current, :sprint15] do
      portfolio = portfolio!()
      preview = %Preview{entries: [buy(1), sell(2, "5", "12.00")]}

      assert {:ok, %{created_transactions: 3}} =
               Imports.apply(preview, %{portfolio_id: portfolio.id})

      if formula == :sprint15, do: store_refund_under_sprint15!(portfolio, refund(2, "12.00"))

      sale =
        Repo.one!(
          from(t in Transaction, where: t.portfolio_id == ^portfolio.id and t.type == "sell")
        )

      {:ok, _} = Ledger.delete_transaction(Actor.owner_ui(), sale)

      assert %{total: %{hash: 2, new: 1}} =
               Imports.reimport_counts(preview, portfolio_id: portfolio.id)

      assert {:ok, again} = Imports.apply(preview, %{portfolio_id: portfolio.id})
      assert again.created_transactions == 1, "formula #{formula}"

      assert [%{row: "2.tax_refund.1", layer: :hash}] =
               Enum.filter(again.duplicate_entries, &(&1.row == "2.tax_refund.1"))

      assert types(portfolio) |> Enum.frequencies() == %{
               {"buy", "1000"} => 1,
               {"sell", "250"} => 1,
               {"tax_refund", "12"} => 1
             }
    end
  end

  # User story (E25 S5 review round, F37):
  # As the operator who added a tax refund to a sale I had already imported,
  # I want the next import to book that refund,
  # so that a refund is never reported as already booked when nothing holds it.
  #
  # Acceptance criteria:
  # - The sale is skipped as already booked; its new refund books.
  # - The preview counts the refund as new.
  # - Importing the file once more books nothing.
  test "a refund added to a sale already imported books on the next import" do
    portfolio = portfolio!()
    without_refund = %Preview{entries: [buy(1), %{sell(2, "5", "12.00") | companion_entries: []}]}

    assert {:ok, %{created_transactions: 2}} =
             Imports.apply(without_refund, %{portfolio_id: portfolio.id})

    with_refund = %Preview{entries: [buy(1), sell(2, "5", "12.00")]}

    assert %{total: %{hash: 2, new: 1}} =
             Imports.reimport_counts(with_refund, portfolio_id: portfolio.id)

    assert {:ok, result} = Imports.apply(with_refund, %{portfolio_id: portfolio.id})
    assert result.created_transactions == 1
    assert Enum.map(result.duplicate_entries, & &1.row) |> Enum.sort() == [1, 2]
    assert [_] = refunds(portfolio)

    assert {:ok, %{created_transactions: 0}} =
             Imports.apply(with_refund, %{portfolio_id: portfolio.id})

    assert count(portfolio) == 3
  end

  # User story (E25 S5 review round, F37):
  # As the operator whose next export writes a sale's numbers with more places,
  # I want its refund recognised by what it books,
  # so that a drifted export books no refund twice.
  #
  # Acceptance criteria:
  # - A sale whose content hash drifted is skipped on the economic key, and so
  #   is its unchanged refund, whose hash drifted with its sale's.
  test "a re-export whose sale drifted books no refund twice" do
    portfolio = portfolio!()
    preview = %Preview{entries: [buy(1), sell(2, "5", "12.00")]}

    assert {:ok, %{created_transactions: 3}} =
             Imports.apply(preview, %{portfolio_id: portfolio.id})

    drifted = %{sell(2, "5", "12.00") | price: Decimal.new("50.0000001")}

    assert {:ok, again} =
             Imports.apply(%Preview{entries: [buy(1), drifted]}, %{portfolio_id: portfolio.id})

    assert again.created_transactions == 0

    assert Enum.map(again.duplicate_entries, &{&1.row, &1.layer}) |> Enum.sort() ==
             [{1, :hash}, {2, :economics}, {"2.tax_refund.1", :economics}]

    assert count(portfolio) == 3
  end

  # User story (E25 S5 review round, F37):
  # As the operator whose export lists one paper under its old and its new
  # ISIN, each row with a refund,
  # I want the refund collapsed with its row when its twin carries the same
  # one, and booked when its twin carries none,
  # so that the collapse neither doubles nor loses a refund.
  #
  # Acceptance criteria:
  # - A collapsed row's refund equal to its twin's refund collapses with it.
  # - A collapsed row's refund whose twin has none books.
  test "a collapsed row's refund collapses with its twin's, and books when its twin has none" do
    security = security_with_isin_change!()

    for {twin_refund?, expected_refunds} <- [{true, 1}, {false, 1}] do
      portfolio = portfolio!()
      old_isin = %{@security | isin: "DE00000000A3", name: "Example AG"}
      new_isin = %{@security | isin: "DE00000000B1", name: "Example AG"}

      twin =
        %{sell(2, "5", "12.00") | security: old_isin}
        |> then(fn entry ->
          if twin_refund?,
            do: %{entry | companion_entries: [%{refund(2, "12.00") | security: old_isin}]},
            else: %{entry | companion_entries: []}
        end)

      collapsed = %{
        sell(3, "5", "12.00")
        | security: new_isin,
          companion_entries: [%{refund(3, "12.00") | security: new_isin}]
      }

      assert {:ok, result} =
               Imports.apply(%Preview{entries: [twin, collapsed]}, %{
                 portfolio_id: portfolio.id
               })

      assert [%{row: 3} | _] = result.collapsed_duplicates
      assert length(refunds(portfolio)) == expected_refunds, "twin refund #{twin_refund?}"

      assert from(t in Transaction, where: t.portfolio_id == ^portfolio.id and t.type == "sell")
             |> Repo.aggregate(:count) == 1

      assert Repo.all(
               from(t in Transaction,
                 where: t.portfolio_id == ^portfolio.id,
                 select: t.security_id,
                 distinct: true
               )
             ) == [security.id]
    end
  end

  defp security_with_isin_change! do
    {:ok, security} =
      Portfolixir.Catalog.create_security(Actor.owner_ui(), %{
        name: "Example AG",
        isin: "DE00000000A3",
        currency_code: "EUR"
      })

    {:ok, %{security: security}} =
      Portfolixir.Catalog.record_isin_change(Actor.owner_ui(), security, "DE00000000B1")

    security
  end
end
