defmodule Portfolixir.Ledger.SplitRowUpdateTest do
  # E25 S6 (#891), G07: a split is booked through the split flow
  # (`Splits.book_split/2`), which checks the effective date, the positions,
  # a conflicting same-day ratio and the cumulative factor, and fans out one
  # row per positioned portfolio. The generic transaction update could
  # re-date, re-rate or re-target a stored split row without any of those
  # checks, rescaling other portfolios' positions. It now refuses a change
  # to a split row's date, security, portfolio, type or ratio; the note
  # stays editable. A wrong split is deleted and booked again.
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Splits
  alias Portfolixir.Portfolios

  defp owner, do: Actor.owner_ui()

  setup do
    world = base_world(name: "Split Row World")
    security = create_security!(name: "Split Row Holdings", ticker: "SRH")
    other = create_security!(name: "Other Split Row Co", ticker: "OSR")
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-05])

    {:ok, [split]} =
      Splits.book_split(owner(), %{
        security_id: security.id,
        date: ~D[2026-02-01],
        ratio_numerator: 2,
        ratio_denominator: 1
      })

    %{world: world, security: security, other: other, split: split}
  end

  # User story:
  # As the operator whose split was booked through the split flow,
  # I want the generic booking edit to refuse moving, re-rating or
  # re-targeting that split,
  # so that a split never changes without the checks that booked it, and no
  # other portfolio's position is rescaled behind them.
  #
  # Acceptance criteria:
  # - Changing a stored split row's date, ratio, security, portfolio or type
  #   answers a changeset error on that field naming delete-and-rebook, and
  #   stores and journals nothing.
  # - Its note still updates, journaled.
  test "a split row's facts are refused, its note updates",
       %{world: world, security: security, other: other, split: split} do
    {:ok, second} =
      Portfolios.create_portfolio(owner(), %{name: "Second", base_currency_code: "EUR"})

    refusals = [
      {:date, %{date: ~D[2026-01-20]}},
      {:split_ratio_numerator, %{split_ratio_numerator: 3}},
      {:split_ratio_denominator, %{split_ratio_denominator: 3}},
      {:security_id, %{security_id: other.id}},
      {:portfolio_id, %{portfolio_id: second.id}},
      {:type, %{type: "buy", quantity: "10", price: "1", securities_account_id: world.depot.id}}
    ]

    before = length(Journal.list_entries(resource_type: "transaction"))

    for {field, attrs} <- refusals do
      assert {:error, changeset} = Ledger.update_transaction(owner(), split, attrs),
             "#{field} was accepted"

      assert [message] = errors_on(changeset)[field], "no error on #{field}"
      assert message =~ "delete"
    end

    stored = Ledger.get_transaction(split.id)
    assert stored.date == ~D[2026-02-01]
    assert {stored.split_ratio_numerator, stored.split_ratio_denominator} == {2, 1}
    assert stored.security_id == security.id
    assert stored.portfolio_id == world.portfolio.id
    assert length(Journal.list_entries(resource_type: "transaction")) == before

    assert {:ok, noted} =
             Ledger.update_transaction(owner(), split, %{notes: "per the statement"})

    assert noted.notes == "per the statement"
    assert length(Journal.list_entries(resource_type: "transaction")) == before + 1
  end

  # Acceptance criteria:
  # - Another booking cannot become a split through the generic update: the
  #   split flow is the only way a split row enters the ledger.
  test "another booking cannot become a split through the update", %{world: world} do
    [buy] = Ledger.list_transactions() |> Enum.filter(&(&1.type == "buy"))

    assert {:error, changeset} =
             Ledger.update_transaction(owner(), buy, %{
               type: "split",
               quantity: nil,
               price: nil,
               securities_account_id: nil,
               cash_account_id: nil,
               split_ratio_numerator: 2,
               split_ratio_denominator: 1
             })

    assert [message] = errors_on(changeset)[:type]
    assert message =~ "split"
    assert Ledger.get_transaction(buy.id).type == "buy"
    assert Ledger.get_transaction(buy.id).portfolio_id == world.portfolio.id
  end
end
