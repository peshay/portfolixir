defmodule Portfolixir.Imports.JsonRowRefusalsTest do
  # Sprint 22 R3 (risk tier: import idempotency, ADR-0036). Three JSON v1
  # rows the parser used to let through, each now refused at the preview
  # with its reason named, while the rest of the file previews and books:
  # a `time` it cannot read (#1306), a kind that needs a security without
  # one (#1305), and a cash row with a negative `amount` (#1307). ADR-0053's
  # note of 2026-11-01 lists them among its refusals.
  #
  # Every name and amount is synthetic.
  #
  # async: false — the applier's after-commit enrichment runs in a task that
  # needs the shared sandbox connection.
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Imports
  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  defp target(name) do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{name: name, base_currency_code: "EUR"})

    portfolio
  end

  defp parse!(transactions) do
    body = ~s({"version": 1, "transactions": [#{Enum.join(transactions, ",\n")}]})
    {:ok, preview} = PortfolioPerformance.parse(body, filename: "refusals.json")
    preview
  end

  defp apply!(preview, portfolio) do
    {:ok, _result} = Imports.apply(preview, %{portfolio_id: portfolio.id})
    Ledger.list_transactions_for_portfolio(portfolio.id)
  end

  defp booked(transactions, type), do: Enum.filter(transactions, &(&1.type == type))

  @deposit ~s({"type": "DEPOSIT", "account": "Test-Cash", "date": "2025-03-01",
    "currency": "EUR", "amount": "1000.00"})

  defp removal(time),
    do: ~s({"type": "REMOVAL", "account": "Test-Cash", "date": "2025-03-03",
      "time": #{time}, "currency": "EUR", "amount": "25.00"})

  # User story (#1306):
  # As the operator dropping a Portfolio Performance JSON export,
  # I want a row whose time of day the parser cannot read named as that
  # row's error, with the forms it reads,
  # so that two same-day rows whose times were both dropped never fold into
  # one booking, the second counted as already imported.
  #
  # Acceptance criteria:
  # - Two removals of 25.00 on 2025-03-03 that differ only in their
  #   unreadable times ("9:15 AM", "2025-03-03T09:45") are two row errors,
  #   "unreadable time “9:15 AM”: use HH:MM or HH:MM:SS — row not imported",
  #   and neither is an entry.
  # - The apply books the deposit alone: Test-Cash 1000.00, no removal.
  # - The same two removals at "09:15" and "09:45:30" book twice, 25.00
  #   each.
  # - A blank time is no time, as an absent one is; a time that is not a
  #   string is unreadable too.
  test "an unreadable time is a row error, so two rows differing only in it never fold into one" do
    preview = parse!([@deposit, removal(~s("9:15 AM")), removal(~s("2025-03-03T09:45"))])

    assert Enum.map(preview.entries, & &1.kind) == ["deposit"]

    assert preview.errors == [
             %{
               row: 2,
               message: "unreadable time “9:15 AM”: use HH:MM or HH:MM:SS — row not imported"
             },
             %{
               row: 3,
               message:
                 "unreadable time “2025-03-03T09:45”: use HH:MM or HH:MM:SS — row not imported"
             }
           ]

    unreadable = apply!(preview, target("Unreadable"))
    assert booked(unreadable, "removal") == []
    assert [deposit] = booked(unreadable, "deposit")
    assert Decimal.equal?(deposit.gross_amount, Decimal.new("1000.00"))

    readable = parse!([@deposit, removal(~s("09:15")), removal(~s("09:45:30"))])
    assert readable.errors == []
    assert Enum.map(readable.entries, & &1.time) == [nil, ~T[09:15:00], ~T[09:45:30]]

    removals = readable |> apply!(target("Readable")) |> booked("removal")
    assert length(removals) == 2
    assert Enum.all?(removals, &Decimal.equal?(&1.gross_amount, Decimal.new("25.00")))

    blank = parse!([removal(~s("  ")), removal("null"), removal("915")])
    assert Enum.map(blank.entries, & &1.time) == [nil, nil]

    assert blank.errors == [
             %{row: 3, message: "unreadable time “915”: use HH:MM or HH:MM:SS — row not imported"}
           ]
  end
end
