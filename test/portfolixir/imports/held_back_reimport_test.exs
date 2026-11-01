defmodule Portfolixir.Imports.HeldBackReimportTest do
  # ADR-0050, the amendment of 2026-11-01 (#1313; risk-tier: import
  # idempotency, ADR-0036). The content hash covers the portfolio, so a file
  # first imported into another portfolio used to preview as new on the
  # Imports page, which books into the default portfolio (ADR-0024), and one
  # confirm booked the history twice. The preview now reads the hashes of
  # every portfolio, names a row already imported elsewhere and holds it back
  # by default; the operator includes a portfolio's group deliberately, and
  # the apply judges again under its locks.
  #
  # The identities the building batch pins are X1, X2 and X3 of the
  # amendment, one test each. Every name, ISIN and amount is synthetic.
  #
  # async: false: the applier's after-commit enrichment runs in a task that
  # needs the shared sandbox connection.
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Applier.Result
  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  # Four entries: a deposit, a bond buy and two coupons.
  @coupons """
  {
    "version": 1,
    "transactions": [
      {"type": "DEPOSIT", "account": "Coupon-Cash", "date": "2026-03-12",
       "currency": "EUR", "amount": 10000.00},
      {"type": "PURCHASE", "account": "Coupon-Cash", "portfolio": "Coupon-Depot",
       "date": "2026-03-13", "time": "10:00", "currency": "EUR", "amount": 9950.00,
       "shares": 100.0,
       "security": {"name": "Larkspur Rail AG 4,00 % Anleihe 2031",
                    "isin": "XSLARKSPUR33", "currency": "EUR"}},
      {"type": "INTEREST", "account": "Coupon-Cash", "date": "2026-06-30",
       "time": "09:30", "currency": "EUR", "amount": 200.00,
       "security": {"name": "Larkspur Rail AG 4,00 % Anleihe 2031",
                    "isin": "XSLARKSPUR33", "currency": "EUR"}},
      {"type": "INTEREST", "account": "Coupon-Cash", "date": "2026-09-30",
       "time": "09:30", "currency": "EUR", "amount": 200.00,
       "security": {"name": "Larkspur Rail AG 4,00 % Anleihe 2031",
                    "isin": "XSLARKSPUR33", "currency": "EUR"}}
    ]
  }
  """

  # The first half of the same history: the deposit and the buy.
  @first_half """
  {
    "version": 1,
    "transactions": [
      {"type": "DEPOSIT", "account": "Coupon-Cash", "date": "2026-03-12",
       "currency": "EUR", "amount": 10000.00},
      {"type": "PURCHASE", "account": "Coupon-Cash", "portfolio": "Coupon-Depot",
       "date": "2026-03-13", "time": "10:00", "currency": "EUR", "amount": 9950.00,
       "shares": 100.0,
       "security": {"name": "Larkspur Rail AG 4,00 % Anleihe 2031",
                    "isin": "XSLARKSPUR33", "currency": "EUR"}}
    ]
  }
  """

  setup do
    # The default portfolio the Imports page books into is the first one.
    {:ok, main} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Hauptportfolio",
        base_currency_code: "EUR"
      })

    {:ok, bonds} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Anleihen",
        base_currency_code: "EUR"
      })

    %{main: main, bonds: bonds}
  end

  defp parse!(body) do
    {:ok, preview} = PortfolioPerformance.parse(body, filename: "kupons-2026.json")
    assert preview.errors == []
    preview
  end

  # The import an agent or a script makes into a named portfolio.
  defp import_into!(body, portfolio) do
    assert {:ok, %Result{} = result} =
             Imports.apply(parse!(body), %{portfolio_id: portfolio.id})

    result
  end

  # The Imports page's confirm: the mapped apply, bound to the default
  # portfolio, every file name resolved as the prefill resolves it.
  defp page_apply(preview, include \\ []) do
    Imports.apply(preview, %{cash_accounts: %{}, depots: %{}, include_portfolios: include})
  end

  # The ledger stores amounts at six places.
  defp booked(portfolio) do
    portfolio.id
    |> Ledger.list_transactions_for_portfolio()
    |> Enum.map(&{&1.type, &1.gross_amount})
    |> Enum.sort()
  end

  # User story (#1313; ADR-0050 as amended on 2026-11-01, X1):
  # As the operator whose bond history an agent imported into "Anleihen",
  # I want the Imports page to name that history when I drop the file again,
  # so that one confirm does not book it a second time in my main portfolio.
  #
  # Acceptance criteria:
  # - Every row reads "already imported into Anleihen" in the preview's
  #   counts, none of them new, in one group for that portfolio.
  # - The confirm books nothing and its result counts the rows as held back.
  test "X1: a file imported into another portfolio is held back on the page", %{
    main: main,
    bonds: bonds
  } do
    first = import_into!(@coupons, bonds)
    assert first.created_transactions == 4

    preview = parse!(@coupons)
    counts = Imports.reimport_counts(preview)

    assert counts.total.held_back == 4
    assert counts.total.new == 0
    assert counts.cash_accounts["Coupon-Cash"].held_back == 4
    assert counts.depots["Coupon-Depot"].held_back == 1

    assert [group] = counts.held_back
    assert group.portfolio_id == bonds.id
    assert group.portfolio_name == "Anleihen"
    assert group.count == 4
    refute group.included

    assert Enum.map(group.entries, & &1.gross_amount) ==
             [
               Decimal.new("10000.00"),
               Decimal.new("9950.00"),
               Decimal.new("200.00"),
               Decimal.new("200.00")
             ]

    # The hash layers alone say the same.
    assert Imports.reimport_counts(preview, dry_run: false).total.held_back == 4

    assert {:ok, %Result{} = result} = page_apply(preview)
    assert result.created_transactions == 0
    assert result.created_cash_accounts == 0
    assert result.created_securities_accounts == 0
    assert length(result.held_back_entries) == 4
    assert Enum.all?(result.held_back_entries, &(&1.portfolio_id == bonds.id))
    assert booked(main) == []
  end

  # User story (#1313; ADR-0050 as amended on 2026-11-01, X2):
  # As the operator who keeps the history in two portfolios on purpose,
  # I want to take the held-back group over deliberately,
  # so that the second copy is my choice and is still booked only once.
  #
  # Acceptance criteria:
  # - With "Anleihen" included the four rows book into the main portfolio,
  #   each once, with the file's exact amounts.
  # - A third drop of the file books nothing: the main portfolio's own hash
  #   holds every row now.
  test "X2: an included group books once, and a third drop books nothing", %{
    main: main,
    bonds: bonds
  } do
    import_into!(@coupons, bonds)
    preview = parse!(@coupons)

    included = Imports.reimport_counts(preview, include_portfolios: [bonds.id])
    assert included.total.held_back == 0
    assert included.total.new == 4
    assert [%{included: true, count: 4}] = included.held_back

    assert {:ok, %Result{} = result} = page_apply(preview, [bonds.id])
    assert result.created_transactions == 4
    assert result.held_back_entries == []

    expected = [
      {"buy", Decimal.new("9950.000000")},
      {"deposit", Decimal.new("10000.000000")},
      {"interest", Decimal.new("200.000000")},
      {"interest", Decimal.new("200.000000")}
    ]

    assert booked(main) == expected
    assert booked(bonds) == expected

    third = parse!(@coupons)
    assert Imports.reimport_counts(third).total.hash == 4
    assert Imports.reimport_counts(third).held_back == []

    assert {:ok, %Result{} = again} = page_apply(third)
    assert again.created_transactions == 0
    assert again.already_imported.hash == 4
    assert again.held_back_entries == []
    assert booked(main) == expected
  end

  # User story (#1313; ADR-0050 as amended on 2026-11-01, X3):
  # As the operator whose file is half in "Anleihen" and half new,
  # I want the new half booked and the other half held back,
  # so that nothing books twice and nothing new is lost.
  #
  # Acceptance criteria:
  # - The two coupons book into the main portfolio; the deposit and the buy
  #   are held back.
  # - Booked and held back add up to the file's four rows.
  test "X3: a half-imported file books its new half and holds back the rest", %{
    main: main,
    bonds: bonds
  } do
    import_into!(@first_half, bonds)
    preview = parse!(@coupons)

    counts = Imports.reimport_counts(preview)
    assert counts.total.held_back == 2
    assert counts.total.new == 2
    assert [%{portfolio_name: "Anleihen", count: 2}] = counts.held_back

    assert {:ok, %Result{} = result} = page_apply(preview)
    assert result.created_transactions == 2
    assert length(result.held_back_entries) == 2
    assert result.created_transactions + length(result.held_back_entries) == 4

    assert booked(main) == [
             {"interest", Decimal.new("200.000000")},
             {"interest", Decimal.new("200.000000")}
           ]
  end

  # The apply judges again (the amendment, point 3): a row that became a
  # cross-portfolio hit after the preview counted it new is held back by the
  # confirm, as every row a layer refuses is skipped.
  test "the confirm holds back a row imported elsewhere since the preview", %{
    main: main,
    bonds: bonds
  } do
    preview = parse!(@coupons)
    assert Imports.reimport_counts(preview).total.new == 4

    import_into!(@coupons, bonds)

    assert {:ok, %Result{} = result} = page_apply(preview)
    assert result.created_transactions == 0
    assert length(result.held_back_entries) == 4
    assert booked(main) == []
  end
end
