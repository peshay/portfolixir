defmodule Portfolixir.Imports.RefusedRowBookedTest do
  # Sprint 22 R3, #1219 (risk tier: import idempotency, ADR-0036; board
  # ux-design-2026-11-01-sprint22/03 ③). A row the preview refuses with a
  # remedy (ADR-0053 A8, A9) carried that remedy, "book it by hand", even
  # when the booking it asks for already exists: entered by hand after an
  # earlier drop (its booking carries no import hash), or imported from an
  # export whose hashed fields drifted since. The preview now matches the
  # remedy's booking by its figures on the economic layer, against every
  # stored booking of the portfolio, and names the bookings it finds instead
  # of the remedy. ADR-0053's note of 2026-11-01 records the rule.
  #
  # Every name and amount is synthetic.
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Imports
  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  @arbolia ~s("security": {"name": "Arbolia Inc.", "isin": "DE000ACME016", "currency": "EUR"})

  @history [
    ~s({"type": "DEPOSIT", "account": "Test-Cash", "date": "2026-02-02",
      "currency": "EUR", "amount": "2000.00"}),
    ~s({"type": "PURCHASE", "account": "Test-Cash", "portfolio": "Test-Depot",
      "date": "2026-02-04", "currency": "EUR", "amount": "501.00", "shares": "5",
      #{@arbolia}, "units": [{"type": "FEE", "amount": "1.00"}]})
  ]

  # Row 3: K18's purchase, a FEE unit of -2.00 (A9); row 4: K16's inbound
  # delivery with a TAX unit of -0.40 (A8), for which nothing is booked.
  @refused [
    ~s({"type": "PURCHASE", "account": "Test-Cash", "portfolio": "Test-Depot",
      "date": "2026-03-03", "currency": "EUR", "amount": "1003.00", "shares": "10",
      #{@arbolia},
      "units": [{"type": "FEE", "amount": "5.00"}, {"type": "FEE", "amount": "-2.00"}]}),
    ~s({"type": "INBOUND_DELIVERY", "portfolio": "Test-Depot", "date": "2026-03-04",
      "currency": "EUR", "amount": "999.60", "shares": "4", #{@arbolia},
      "units": [{"type": "TAX", "amount": "-0.40"}]})
  ]

  @late_deposit ~s({"type": "DEPOSIT", "account": "Test-Cash", "date": "2026-03-05",
    "currency": "EUR", "amount": "50.00"})

  defp parse!(rows) do
    {:ok, preview} =
      PortfolioPerformance.parse(~s({"version": 1, "transactions": [#{Enum.join(rows, ",")}]}),
        filename: "history.json"
      )

    preview
  end

  defp by_hand!(portfolio, attrs) do
    [cash] = Portfolios.list_cash_accounts_for_portfolio(portfolio.id)
    [depot] = Portfolios.list_securities_accounts_for_portfolio(portfolio.id)
    [security] = Catalog.list_securities()

    {:ok, transaction} =
      Ledger.create_transaction(
        Actor.owner_ui(),
        Map.merge(
          %{
            portfolio_id: portfolio.id,
            type: "buy",
            date: ~D[2026-03-03],
            security_id: security.id,
            securities_account_id: depot.id,
            cash_account_id: cash.id,
            currency_code: "EUR",
            quantity: Decimal.new("10"),
            price: Decimal.new("100.00"),
            fees: Decimal.new("3.00"),
            taxes: Decimal.new("0")
          },
          attrs
        )
      )

    transaction
  end

  defp booked(errors, row) do
    case Enum.find(errors, &(&1.row == row)) do
      %{booked: %{bookings: bookings}} -> Enum.map(bookings, & &1.id)
      %{} -> nil
    end
  end

  # User story (#1219):
  # As the operator dropping an export again after I booked a refused row
  # by hand, as its warning told me,
  # I want the warning to say that the row is already booked and name the
  # booking it found, instead of telling me again to book it by hand,
  # so that following the preview never books one purchase twice.
  #
  # Acceptance criteria:
  # - Before any hand booking, both refused rows keep their remedy (no
  #   `booked`).
  # - A hand purchase whose cash differs (10 at 100.10 with fees 3.00,
  #   Test-Cash -1004.00) is not the row's booking: row 3 keeps its remedy.
  # - The remedy's booking (10 Arbolia Inc. at 100.00 with fees 3.00 on
  #   2026-03-03, Test-Cash -1003.00, the cash Portfolio Performance shows)
  #   is found: row 3 names it, by hand, with its kind, its head and the
  #   sentence that ends it ("Do not enter the booking again."); row 4,
  #   with no match, keeps its remedy.
  # - A second equal hand booking makes two matches: row 3 names both and
  #   chooses neither.
  # - A booking another row of the file holds by its content hash is never
  #   the refused row's.
  # - The inbound delivery, which moves no cash, is found by its security,
  #   depot, date and quantity: a hand delivery of 4 shares names it, one of
  #   5 does not.
  test "a refused row whose booking exists names it instead of its remedy" do
    portfolio = Portfolios.default_portfolio(Actor.owner_ui())
    {:ok, _result} = Imports.apply(parse!(@history), %{portfolio_id: portfolio.id})
    preview = parse!(@history ++ @refused)
    errors = fn -> Imports.row_errors(preview, portfolio_id: portfolio.id) end

    assert Enum.map(preview.errors, & &1.row) == [3, 4]
    assert booked(errors.(), 3) == nil
    assert booked(errors.(), 4) == nil

    _other = by_hand!(portfolio, %{price: Decimal.new("100.10")})
    assert booked(errors.(), 3) == nil

    hand = by_hand!(portfolio, %{})
    assert Decimal.equal?(Ledger.Projection.cash_amount(hand), Decimal.new("-1003.00"))

    [row3, row4] = errors.()
    assert row3.booked.bookings |> Enum.map(& &1.id) == [hand.id]

    assert row3.booked.head ==
             "booking with a negative fee (-2.00): the import does not book a fee refund yet"

    assert row3.booked.again == "Do not enter the booking again."
    assert row3.message == hd(preview.errors).message
    refute Map.has_key?(row4, :booked)

    twin = by_hand!(portfolio, %{})
    assert booked(errors.(), 3) == [hand.id, twin.id]

    # A row of the file whose content hash a stored booking holds claims
    # that booking: it is that row's, never the refused row's. The twin
    # stands in for such a booking, under the hash of the file's row 5.
    claimed = parse!(@history ++ @refused ++ [@late_deposit])
    [late] = Enum.filter(claimed.entries, &(&1.source_row == 5))
    [[hash | _]] = Imports.Applier.row_hashes([late], portfolio.id)

    {:ok, {1, _}} =
      Repo.transaction(fn ->
        Repo.query!("SELECT set_config('portfolixir.journal_actor', 'test', true)")

        from(t in Ledger.Transaction, where: t.id == ^twin.id)
        |> Repo.update_all(set: [import_hash: hash])
      end)

    assert claimed
           |> Imports.row_errors(portfolio_id: portfolio.id)
           |> booked(3) == [hand.id]

    # A8's delivery moves no cash: its booking is found by its security,
    # depot, date and quantity, 4 shares; 5 shares are another booking.
    _five =
      by_hand!(portfolio, %{
        type: "inbound_delivery",
        date: ~D[2026-03-04],
        quantity: Decimal.new("5"),
        cash_account_id: nil,
        fees: nil,
        taxes: nil,
        price: nil
      })

    assert booked(errors.(), 4) == nil

    delivery =
      by_hand!(portfolio, %{
        type: "inbound_delivery",
        date: ~D[2026-03-04],
        quantity: Decimal.new("4"),
        cash_account_id: nil,
        fees: nil,
        taxes: nil,
        price: nil
      })

    assert booked(errors.(), 4) == [delivery.id]
  end
end
