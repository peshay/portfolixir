defmodule Portfolixir.Imports.CouponImportTest do
  # ADR-0051 I10 (the amendment of 2026-10-09; risk-tier: money and import
  # idempotency, ADR-0036): a fresh import of an INTEREST row that names a
  # security stores that security on the booking and no depot, from a
  # Portfolio Performance JSON and CSV file alike; a row that names none
  # stores none. Point 4: two coupons of two bonds, equal in date, amount,
  # account and time, no longer collapse into one booking. Every name, ISIN
  # and amount is synthetic.
  #
  # async: false: the applier's after-commit enrichment runs in a task that
  # needs the shared sandbox connection.
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Applier.Result
  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  @fixtures Path.expand("../../support/fixtures/portfolio_performance", __DIR__)

  @larkspur "XSLARKSPUR33"
  @wrenfield "XSWRENFLD206"

  # I12's history as a Portfolio Performance CSV export writes it: the
  # coupon names its bond in the Wertpapier column, the account interest
  # names none.
  @coupon_csv """
  Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle
  2025-03-02 00:00:00;Einlage;;;;10.000,00;;;10.000,00;Coupon-Cash;;;
  2025-03-10 10:00:00;Kauf;Larkspur Rail AG 4,00 % Anleihe 2031;100;99,50;9.950,00;5,00;;9.955,00;Coupon-Depot;Coupon-Cash;;
  2026-03-31 00:00:00;Zinsen;;;;1,10;;;1,10;Coupon-Cash;;;
  2026-04-15 09:30:00;Zinsen;Larkspur Rail AG 4,00 % Anleihe 2031;;;400,00;;;400,00;Coupon-Cash;;;
  """

  # Two bonds paying an equal coupon on one day, to one account, at one time.
  @twin_coupons """
  {
    "version": 1,
    "transactions": [
      {"type": "DEPOSIT", "account": "Twin-Cash", "date": "2025-01-02",
       "currency": "EUR", "amount": 1000.00},
      {"type": "INTEREST", "account": "Twin-Cash", "date": "2026-05-15",
       "time": "08:00", "currency": "EUR", "amount": 50.00,
       "security": {"name": "Wrenfield Gardens AG 5,00 % Anleihe 2030",
                    "isin": "XSWRENFLD206", "currency": "EUR"}},
      {"type": "INTEREST", "account": "Twin-Cash", "date": "2026-05-15",
       "time": "08:00", "currency": "EUR", "amount": 50.00,
       "security": {"name": "Larkspur Rail AG 4,00 % Anleihe 2031",
                    "isin": "XSLARKSPUR33", "currency": "EUR"}}
    ]
  }
  """

  setup do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Coupon import",
        base_currency_code: "EUR"
      })

    %{portfolio: portfolio}
  end

  # Each test here holds its own copy of one history in several portfolios
  # on purpose, so every apply includes the others' rows deliberately (ADR-0050
  # as amended on 2026-11-01, #1313: held back by default).
  defp every_portfolio, do: Enum.map(Portfolios.list_portfolios(), & &1.id)

  defp apply!(body, filename, portfolio) do
    {:ok, preview} = PortfolioPerformance.parse(body, filename: filename)
    assert preview.errors == []

    assert {:ok, %Result{} = result} =
             Imports.apply(preview, %{
               portfolio_id: portfolio.id,
               include_portfolios: every_portfolio()
             })

    result
  end

  defp interest(portfolio) do
    portfolio.id
    |> Ledger.list_transactions_for_portfolio()
    |> Enum.filter(&(&1.type == "interest"))
    |> Enum.sort_by(&{Date.to_iso8601(&1.date), Decimal.to_string(&1.gross_amount)})
  end

  defp security(isin), do: Enum.find(Catalog.list_securities(), &(&1.isin == isin))

  defp bond_by_name(name), do: Enum.find(Catalog.list_securities(), &(&1.name == name))

  # User story (#928, Sprint 21 α4; ADR-0051 I10):
  # As the operator importing a bond's history from a Portfolio Performance
  # JSON file,
  # I want the coupon booked with the bond its row names,
  # so that the coupon can be counted as that bond's income.
  #
  # Acceptance criteria:
  # - bond_coupon.json's coupon (400.00 on 2026-04-15) stores the bond's id
  #   and no depot; its account interest (1.10 on 2026-03-31) stores no
  #   security and no depot.
  # - A coupon row that names a depot (`portfolio`) creates no depot: the
  #   name stays unread for an interest row (ADR-0050 §4).
  test "a JSON INTEREST row keeps the security it names, and no depot" do
    portfolio = create_portfolio!("Coupon JSON")
    body = File.read!(Path.join(@fixtures, "bond_coupon.json"))
    assert %Result{created_transactions: 4} = apply!(body, "bond_coupon.json", portfolio)

    bond = security(@larkspur)
    assert [account_interest, coupon] = interest(portfolio)

    assert account_interest.date == ~D[2026-03-31]
    assert Decimal.equal?(account_interest.gross_amount, Decimal.new("1.10"))
    assert account_interest.security_id == nil
    assert account_interest.securities_account_id == nil

    assert coupon.date == ~D[2026-04-15]
    assert Decimal.equal?(coupon.gross_amount, Decimal.new("400.00"))
    assert coupon.security_id == bond.id
    assert coupon.securities_account_id == nil

    # The coupon naming a depot of its own: no depot is created for it.
    named_depot =
      String.replace(
        body,
        ~s("date": "2026-04-15",),
        ~s("portfolio": "Coupon-Only-Depot",\n      "date": "2026-04-15",)
      )

    refute named_depot == body
    other = create_portfolio!("Coupon JSON, depot named")
    assert %Result{created_transactions: 4} = apply!(named_depot, "named.json", other)
    assert [_account_interest, other_coupon] = interest(other)
    assert other_coupon.security_id == bond.id
    assert other_coupon.securities_account_id == nil

    refute Enum.any?(Portfolios.list_securities_accounts(), &(&1.name == "Coupon-Only-Depot"))
  end

  # User story (#928, Sprint 21 α4; ADR-0051 I10):
  # As the operator importing a bond's history from a Portfolio Performance
  # CSV file,
  # I want the coupon booked with the bond its Wertpapier names,
  # so that the CSV path keeps the bond as the JSON path does.
  #
  # Acceptance criteria:
  # - The Zinsen row naming the bond stores the bond's id and no depot; the
  #   Zinsen row naming none stores no security.
  test "a CSV Zinsen row keeps the security it names, and no depot", %{portfolio: portfolio} do
    assert %Result{created_transactions: 4} = apply!(@coupon_csv, "coupon.csv", portfolio)

    bond = bond_by_name("Larkspur Rail AG 4,00 % Anleihe 2031")
    assert [account_interest, coupon] = interest(portfolio)

    assert account_interest.security_id == nil
    assert account_interest.securities_account_id == nil
    assert Decimal.equal?(coupon.gross_amount, Decimal.new("400.00"))
    assert coupon.security_id == bond.id
    assert coupon.securities_account_id == nil
  end

  # User story (#928, Sprint 21 α4; ADR-0051 amendment point 4, ADR-0050 §6):
  # As the operator importing two bonds that pay an equal coupon on the same
  # day to the same account,
  # I want both coupons booked, each with its bond,
  # so that a coupon is never lost by being taken for the other bond's.
  #
  # Acceptance criteria:
  # - A fresh import of the file books the deposit and both coupons; none
  #   collapses.
  # - Each coupon stores its own bond.
  test "two equal coupons of two bonds in one file are two bookings", %{portfolio: portfolio} do
    result = apply!(@twin_coupons, "twin.json", portfolio)

    assert result.created_transactions == 3
    assert result.collapsed_duplicates == []

    assert portfolio |> interest() |> Enum.map(& &1.security_id) |> Enum.sort() ==
             Enum.sort([security(@larkspur).id, security(@wrenfield).id])
  end

  defp create_portfolio!(name) do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{name: name, base_currency_code: "EUR"})

    portfolio
  end
end
