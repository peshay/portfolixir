defmodule Portfolixir.Imports.ApplierResultOrderTest do
  # E25 S5, F40: the applier's result lists are built in linear time and keep
  # the file's row order.
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Entry
  alias Portfolixir.Imports.Preview
  alias Portfolixir.Portfolios

  defp portfolio! do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Import target",
        base_currency_code: "EUR"
      })

    portfolio
  end

  defp deposit(row, amount) do
    %Entry{
      source_row: row,
      kind: "deposit",
      date: ~D[2024-01-10],
      time: Time.new!(10, 0, rem(row, 60)),
      currency_code: "EUR",
      gross_amount: amount && Decimal.new(amount),
      fees: Decimal.new(0),
      taxes: Decimal.new(0),
      pp_account_name: "Cash"
    }
  end

  # User story (E25 S5, F40):
  # As the operator re-importing a large export,
  # I want the result's lists in the file's row order, built without
  # copying every list on every row,
  # so that a large re-import finishes in time proportional to its size.
  #
  # Acceptance criteria:
  # - Skipped and duplicate rows are listed in the file's order.
  # - Applying four times as many rows takes well under the sixteen times a
  #   quadratic build would.
  test "result lists keep the file's order" do
    portfolio = portfolio!()

    preview = %Preview{
      entries: [deposit(1, nil), deposit(2, "10"), deposit(3, nil), deposit(4, "20")]
    }

    assert {:ok, first} = Imports.apply(preview, %{portfolio_id: portfolio.id})
    assert Enum.map(first.skipped_entries, & &1.row) == [1, 3]

    assert {:ok, again} = Imports.apply(preview, %{portfolio_id: portfolio.id})
    assert Enum.map(again.skipped_entries, & &1.row) == [1, 3]
    assert Enum.map(again.duplicate_entries, & &1.row) == [2, 4]
  end

  test "a large re-import's result is built in linear time" do
    portfolio = portfolio!()

    time = fn rows ->
      entries = for row <- 1..rows, do: deposit(row, nil)

      {micros, {:ok, result}} =
        :timer.tc(fn ->
          Imports.apply(%Preview{entries: entries}, %{portfolio_id: portfolio.id})
        end)

      assert length(result.skipped_entries) == rows
      assert hd(result.skipped_entries).row == 1
      micros
    end

    _warm = time.(1_000)
    small = Enum.min([time.(10_000), time.(10_000)])
    large = Enum.min([time.(40_000), time.(40_000)])

    assert large < small * 8 + 200_000,
           "40k rows took #{div(large, 1000)} ms against #{div(small, 1000)} ms for 10k"
  end
end
