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

  @arbolia ~s("security": {"name": "Arbolia Inc.", "isin": "DE000ACME016", "currency": "EUR"})

  # User story (#1305):
  # As the operator dropping a Portfolio Performance JSON export,
  # I want a row of a kind that books on a security, but names none, named
  # as that row's error,
  # so that the preview never looks clean while the confirm then refuses
  # the whole file on "Security can't be blank".
  #
  # Acceptance criteria:
  # - A dividend of 12.50 without a `security` is "dividend without a
  #   security — row not imported"; a purchase, a sale, a delivery either
  #   way and a security transfer read the same in their own words.
  # - An interest payment, a fee or a tax without a security is no such
  #   row: it previews.
  # - The file's other rows book: the deposit of 1000.00, the purchase of
  #   10 Arbolia Inc. for 100.00, the interest of 12.50, the fee and the tax
  #   of 12.50 each; Test-Cash ends at 887.50.
  test "a row of a kind that books on a security, but names none, is a row error" do
    no_security = fn type, extra ->
      ~s({"type": "#{type}", "account": "Test-Cash", "portfolio": "Test-Depot",
        "date": "2025-03-04", "currency": "EUR", "amount": "12.50"#{extra}})
    end

    preview =
      parse!([
        @deposit,
        ~s({"type": "PURCHASE", "account": "Test-Cash", "portfolio": "Test-Depot",
          "date": "2025-03-02", "currency": "EUR", "amount": "100.00", "shares": "10",
          #{@arbolia}}),
        no_security.("DIVIDEND", ""),
        no_security.("PURCHASE", ~s(, "shares": "1")),
        no_security.("SALE", ~s(, "shares": "1")),
        no_security.("INBOUND_DELIVERY", ~s(, "shares": "1")),
        no_security.("OUTBOUND_DELIVERY", ~s(, "shares": "1")),
        no_security.("SECURITY_TRANSFER", ~s(, "shares": "1", "otherPortfolio": "Depot-2")),
        no_security.("INTEREST", ""),
        no_security.("FEE", ""),
        no_security.("TAX", "")
      ])

    assert preview.errors == [
             %{row: 3, message: "dividend without a security — row not imported"},
             %{row: 4, message: "purchase without a security — row not imported"},
             %{row: 5, message: "sale without a security — row not imported"},
             %{row: 6, message: "inbound delivery without a security — row not imported"},
             %{row: 7, message: "outbound delivery without a security — row not imported"},
             %{row: 8, message: "security transfer without a security — row not imported"}
           ]

    assert Enum.map(preview.entries, & &1.kind) == ~w(deposit buy interest fee tax)

    transactions = apply!(preview, portfolio = target("No security"))
    assert [buy] = booked(transactions, "buy")
    assert Decimal.equal?(buy.quantity, Decimal.new("10"))

    [cash] = Portfolios.list_cash_accounts_for_portfolio(portfolio.id)
    balance = Ledger.cash_balances(portfolio_id: portfolio.id) |> Map.fetch!(cash.id)
    assert Decimal.equal?(balance, Decimal.new("887.50"))
  end
end
