defmodule Portfolixir.Portfolios.Performance.ContributionCouponTest do
  # ADR-0051 I12 and I13 (the amendment of 2026-10-09; risk-tier: money,
  # ADR-0036): an interest booking that names a security is that position's
  # income, as a dividend is; the interest line holds the interest bookings
  # that name none. The fixture is I12's, imported from one Portfolio
  # Performance JSON file and invented throughout: the bond "Larkspur Rail AG
  # 4,00 % Anleihe 2031", ISIN XSLARKSPUR33 (its check digit holds, and no
  # real XS number has letters in its national part), 100 shares at 99.50.
  #
  #   2025-03-02  deposit 10,000.00 to Coupon-Cash
  #   2025-03-10  buy 100 @ 99.50, fee 5.00: amount 9,955.00, 45.00 left
  #   2025-12-31  quote 99.00
  #   2026-03-31  account interest 1.10, naming no security
  #   2026-04-15  the coupon, 400.00, naming the bond
  #   2026-06-30  quote 100.25
  #
  # The window 2026-01-01 to 2026-06-30: start 9,945.00 (bond 9,900.00, cash
  # 45.00), end 10,471.10 (bond 10,025.00, cash 446.10), no external flow,
  # so the result is 526.10.
  #
  # async: false: the applier's after-commit enrichment runs in a task that
  # needs the shared sandbox connection.
  use Portfolixir.DataCase, async: false

  import Ecto.Query
  import Portfolixir.WorldFixtures, only: [put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Applier.Result
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Income
  alias Portfolixir.Portfolios.Performance.Contribution

  @fixtures Path.expand("../../../support/fixtures/portfolio_performance", __DIR__)
  @fixture "bond_coupon.json"
  @isin "XSLARKSPUR33"
  @today ~D[2026-06-30]
  @window {:range, ~D[2026-01-01], ~D[2026-06-30]}

  defp dec(value), do: Decimal.new(value)

  defp assert_dec(actual, expected, label \\ nil) do
    assert %Decimal{} = actual
    assert Decimal.equal?(actual, dec(expected)), "#{label}: expected #{expected}, got #{actual}"
  end

  defp import_i12! do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Coupon contribution",
        base_currency_code: "EUR"
      })

    {:ok, preview} =
      Imports.parse_portfolio_performance(File.read!(Path.join(@fixtures, @fixture)),
        filename: @fixture
      )

    assert {:ok, %Result{created_securities: 1, created_transactions: 4}} =
             Imports.apply(preview, %{portfolio_id: portfolio.id})

    bond = Enum.find(Catalog.list_securities(), &(&1.isin == @isin))
    put_quote!(bond, ~D[2025-12-31], "99.00")
    put_quote!(bond, ~D[2026-06-30], "100.25")

    [cash] = Portfolios.list_cash_accounts_for_portfolio(portfolio.id)
    [depot] = Portfolios.list_securities_accounts_for_portfolio(portfolio.id)
    %{portfolio: portfolio, bond: bond, cash: cash, depot: depot}
  end

  # The coupon as an import before the amendment stored it: without its bond
  # (a test actor for the journal guard).
  defp clear_coupon_security!(portfolio) do
    {:ok, _cleared} =
      Repo.transaction(fn ->
        Repo.query!("SELECT set_config('portfolixir.journal_actor', 'test', true)")

        from(t in Transaction, where: t.portfolio_id == ^portfolio.id and t.type == "interest")
        |> Repo.update_all(set: [security_id: nil])
      end)

    :ok
  end

  defp view!(depots, cash_accounts) do
    {:ok, bucket} =
      Buckets.create_bucket(Actor.owner_ui(), %{
        name: "Coupon #{System.unique_integer([:positive])}"
      })

    for depot <- depots,
        do: :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), depot, [bucket.id])

    for cash <- cash_accounts,
        do: :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), cash, [bucket.id])

    {:ok, view} =
      Buckets.create_view(Actor.owner_ui(), %{
        name: "Coupon #{System.unique_integer([:positive])}",
        include_all: false
      })

    :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, [bucket.id], [])
    view
  end

  defp row(result, bond), do: Enum.find(result.positions, &(&1.security_id == bond.id))

  defp assert_row(nil, _expected), do: flunk("the scope keeps no row for the bond")

  defp assert_row(row, expected) do
    for {field, value} <- expected do
      case value do
        %Decimal{} -> assert_dec(Map.fetch!(row, field), Decimal.to_string(value), field)
        value when field in [:name, :isin] -> assert Map.fetch!(row, field) == value
        value when is_binary(value) -> assert_dec(Map.fetch!(row, field), value, field)
        value -> assert Map.fetch!(row, field) == value, "#{field}"
      end
    end
  end

  defp assert_lines(result, interest, fees, currency) do
    assert_dec(result.remainder.interest, interest, :interest)
    assert_dec(result.remainder.standalone_fees_and_taxes, fees, :standalone_fees_and_taxes)
    assert_dec(result.remainder.cash_currency_effect, currency, :cash_currency_effect)
  end

  # I1: the positions plus the remainder lines are the result, exactly.
  defp assert_sums(result) do
    sum =
      result.positions
      |> Enum.map(& &1.contribution)
      |> Enum.reduce(result.totals.remainder, &Decimal.add/2)

    assert Decimal.equal?(sum, result.totals.result)
  end

  # User story (#928, Sprint 21 α4; ADR-0051 I12):
  # As the operator holding a bond whose coupon I imported from Portfolio
  # Performance,
  # I want Wealth's contribution table to count the coupon as the bond's
  # income and the interest line to keep only the interest that names no
  # security,
  # so that the bond's contribution reads its whole return, not its price
  # move alone.
  #
  # Acceptance criteria:
  # - Over 2026-01-01 to 2026-06-30 the result is 526.10.
  # - The bond's row: start 9,900.00, end 10,025.00, net flows 0, income
  #   400.00, costs 0, contribution 525.00.
  # - The interest line is 1.10 and the other two lines 0; 525.00 + 1.10 =
  #   526.10, exact (I1).
  # - The view-less read across portfolios gives the same figures.
  test "a coupon naming its bond is the bond's income, and the interest line keeps the rest" do
    %{portfolio: portfolio, bond: bond} = import_i12!()

    {:ok, result} = Contribution.for_portfolio(portfolio.id, period: @window, today: @today)
    {:ok, everything} = Contribution.for_view(nil, period: @window, today: @today)

    for read <- [result, everything] do
      assert read.start_date == ~D[2026-01-01]
      assert_dec(read.totals.result, "526.10", :result)

      assert_row(row(read, bond),
        start_value: "9900.00",
        end_value: "10025.00",
        net_flows: "0",
        income: "400.00",
        costs: "0",
        contribution: "525.00",
        held_at_start: true,
        held_at_end: true
      )

      assert_lines(read, "1.10", "0", "0")
      assert_dec(read.totals.positions, "525.00", :positions)
      assert_sums(read)
    end
  end

  # User story (#928, Sprint 21 α4; ADR-0051 I12, "rows stored before stay as
  # they are"):
  # As the operator whose coupon was stored before the importer kept its bond,
  # I want that coupon to stay in the interest line, as its basis says,
  # so that nothing moves a row I did not change.
  #
  # Acceptance criteria:
  # - The same coupon stored without a security: the bond 125.00, the
  #   interest line 401.10, the result 526.10.
  test "the same coupon stored without its bond stays in the interest line" do
    %{portfolio: portfolio, bond: bond} = import_i12!()
    clear_coupon_security!(portfolio)

    {:ok, result} = Contribution.for_portfolio(portfolio.id, period: @window, today: @today)

    assert_dec(result.totals.result, "526.10", :result)
    assert_row(row(result, bond), income: "0", contribution: "125.00")
    assert_lines(result, "401.10", "0", "0")
    assert_sums(result)
  end

  # User story (#928, Sprint 21 α4; ADR-0051 I13):
  # As the operator reading a view that holds the bond's cash account but not
  # its depot,
  # I want the coupon credited to that account counted as the bond's income,
  # as a dividend is,
  # so that the view's result is explained by the position that paid it.
  #
  # Acceptance criteria:
  # - The bond's row: start and end 0, held at neither end, income and
  #   contribution 400.00; the interest line 1.10; the result 401.10 (cash
  #   45.00 to 446.10). Narrowing the portfolio and reading the view across
  #   portfolios agree.
  # - A view that holds the depot but not the account keeps no coupon: the
  #   bond 125.00, every line 0, the result 125.00.
  test "a view keeps a coupon only where it holds the account it was credited to" do
    %{portfolio: portfolio, bond: bond, cash: cash, depot: depot} = import_i12!()
    cash_view = view!([], [cash])
    depot_view = view!([depot], [])

    {:ok, narrowed} =
      Contribution.for_portfolio(portfolio.id, view: cash_view.id, period: @window, today: @today)

    {:ok, across} = Contribution.for_view(cash_view.id, period: @window, today: @today)

    for read <- [narrowed, across] do
      assert_dec(read.totals.result, "401.10", :result)

      assert_row(row(read, bond),
        start_value: "0",
        end_value: "0",
        net_flows: "0",
        income: "400.00",
        costs: "0",
        contribution: "400.00",
        held_at_start: false,
        held_at_end: false,
        name: "Larkspur Rail AG 4,00 % Anleihe 2031",
        isin: @isin
      )

      assert_lines(read, "1.10", "0", "0")
      assert_sums(read)
    end

    {:ok, narrowed} =
      Contribution.for_portfolio(portfolio.id,
        view: depot_view.id,
        period: @window,
        today: @today
      )

    {:ok, across} = Contribution.for_view(depot_view.id, period: @window, today: @today)

    for read <- [narrowed, across] do
      assert_dec(read.totals.result, "125.00", :result)

      assert_row(row(read, bond),
        start_value: "9900.00",
        end_value: "10025.00",
        income: "0",
        contribution: "125.00"
      )

      assert_lines(read, "0", "0", "0")
      assert_sums(read)
    end
  end

  # User story (#928, Sprint 21 α4; ADR-0051 amendment point 6, I12):
  # As the operator reading the Income facet,
  # I want a coupon that names its bond on the bond's row,
  # so that "Je Position" and "Top-Beiträge" say which position paid it.
  #
  # Acceptance criteria:
  # - The bond's row reads 400.00, one payment, last on 2026-04-15; the row
  #   without a security reads 1.10, one payment, last on 2026-03-31.
  # - 2026's interest total stays 401.10: the matrix splits by kind, not by
  #   security.
  test "the Income facet's per-position table puts the coupon on the bond's row" do
    %{portfolio: portfolio, bond: bond} = import_i12!()

    income = Income.for_portfolio(portfolio.id)

    assert [bond_row, account_row] = income.positions
    assert bond_row.security_id == bond.id
    assert_dec(bond_row.gross, "400.00")
    assert bond_row.payment_count == 1
    assert bond_row.last_payment == ~D[2026-04-15]

    assert account_row.security_id == nil
    assert_dec(account_row.gross, "1.10")
    assert account_row.payment_count == 1
    assert account_row.last_payment == ~D[2026-03-31]

    assert [year] = Enum.filter(income.annual, &(&1.year == 2026))
    assert_dec(year.interest_total, "401.10")
    assert_dec(year.dividends_total, "0")
  end
end
