defmodule Portfolixir.Portfolios.ValuationBondCharacterizationTest do
  @moduledoc """
  #330's discovery story (Sprint 16, Lane R): a characterization, not a
  specification. It pins what the valuation does TODAY with a bond imported
  from a Portfolio Performance export, so the issue's verdict rests on pinned
  behaviour. A change to how bonds are valued must change these expectations
  on purpose.

  The fixture is synthetic all the way down: one invented issuer, one made-up
  ISIN with a valid check digit (an `XS` prefix with letters in the national
  part, which no real `XS` number carries), invented amounts.

  Portfolio Performance has no percent quotation, so the export's `shares`
  figure for a bond is either a hundredth of the face amount (the percent
  price then reads as a per-share price) or the face amount itself. The same
  bond is imported once in each reading; the fixture carries the first, and
  the second rewrites only its one `shares` field.
  """

  use Portfolixir.DataCase, async: false

  import Portfolixir.WorldFixtures, only: [put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Applier.Result
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.Valuation

  @fixtures Path.expand("../../support/fixtures/portfolio_performance", __DIR__)
  @fixture "bond_invented.json"
  @isin "XSEXMPL20355"
  # The export's shares figure in the hundredth reading, as the fixture
  # spells it, and the face amount it stands for.
  @hundredth_shares ~s("shares": 100.0)
  @face_amount_shares ~s("shares": 10000.0)
  @quote_date ~D[2026-03-02]
  @today ~D[2026-03-31]

  defp import_bond!(body) do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Bond discovery",
        base_currency_code: "EUR"
      })

    {:ok, preview} = Imports.parse_portfolio_performance(body, filename: @fixture)

    assert {:ok, %Result{created_securities: 1, created_transactions: 3}} =
             Imports.apply(preview, %{portfolio_id: portfolio.id})

    bond = Enum.find(Catalog.list_securities(), &(&1.isin == @isin))
    %{portfolio: portfolio, bond: bond}
  end

  defp fixture_body, do: File.read!(Path.join(@fixtures, @fixture))

  defp face_amount_body do
    body = fixture_body()
    assert String.contains?(body, @hundredth_shares)
    String.replace(body, @hundredth_shares, @face_amount_shares)
  end

  defp only_position(portfolio_id) do
    assert %{positions: [position]} = valuation = Valuation.for_portfolio(portfolio_id)
    {valuation, position}
  end

  defp only_holding(portfolio_id) do
    assert [holding] = Ledger.holdings_for_portfolio(portfolio_id)
    holding
  end

  defp walk(portfolio_id) do
    {:ok, result} = Performance.for_portfolio(portfolio_id, period: "max", today: @today)
    result
  end

  defp dec(value), do: Decimal.new(value)

  defp assert_dec(actual, expected) do
    assert %Decimal{} = actual
    assert Decimal.equal?(actual, dec(expected)), "expected #{expected}, got #{actual}"
  end

  # User story (#330's discovery):
  # As the maintainer deciding what #330 needs,
  # I want to know what today's valuation does with a bond imported from a
  # Portfolio Performance export whose shares are a hundredth of the face
  # amount,
  # so that the issue's verdict rests on pinned behaviour, not on a guess.
  #
  # Acceptance criteria:
  # - The invented bond imports as one security, classified government_bond
  #   from its name; nothing bond-specific (coupon, maturity, face amount,
  #   quotation type) is stored anywhere.
  # - The position's quantity is the export's shares figure, unchanged; the
  #   buy's per-share price is derived as (amount - fees - taxes) / shares.
  # - Without a quote, the valuation prices the bond at that trade price.
  # - With a percent-of-nominal quote stored, the valuation multiplies the
  #   quantity by the quote as if it were a unit price — which in this reading
  #   is face amount x percent / 100, the correct market value.
  # - The cost basis is quantity x derived price (fees not folded in).
  # - The coupon, booked as INTEREST naming the bond, lands on the cash
  #   account without any link to the bond.
  # - The performance walk's end value agrees with the valuation. Its TTWROR
  #   treats the first quote's re-pricing as a basis step (#545), so the
  #   return is the deposit's growth by the coupon less the fee.
  test "a bond booked at a hundredth of its face amount: quantity x percent quote is its market value" do
    %{portfolio: portfolio, bond: bond} = import_bond!(fixture_body())

    assert %Security{name: "Republic of Examplia 2.25% 2035", currency_code: "EUR"} = bond
    assert Security.effective_asset_class(bond) == "government_bond"

    refute Enum.any?(
             Security.__schema__(:fields),
             &(Atom.to_string(&1) =~ ~r/coupon|maturity|nominal|face|quotation/)
           )

    # Trade-priced: the buy's derived price, per hundredth of face amount.
    {valuation, position} = only_position(portfolio.id)
    assert_dec(position.quantity, "100")
    assert position.price_source == :trade
    assert_dec(position.latest_price, "98.5")
    assert_dec(position.market_value, "9850.00")
    assert_dec(valuation.total_value, "9850.00")

    # A percent-of-nominal quote lands.
    put_quote!(bond, @quote_date, "97.25")

    {valuation, position} = only_position(portfolio.id)
    assert position.price_source == :quote
    assert_dec(position.latest_price, "97.25")
    assert_dec(position.market_value, "9725.00")
    assert_dec(valuation.total_cash, "370.00")
    assert_dec(valuation.total_with_cash, "10095.00")

    holding = only_holding(portfolio.id)
    assert_dec(holding.quantity, "100")
    assert_dec(holding.avg_cost, "98.5")
    assert_dec(holding.cost_basis, "9850.00")
    assert_dec(holding.market_value, "9725.00")
    assert_dec(holding.unrealized_pnl_abs, "-125.00")

    # The coupon is income on the cash account, attributed to no security.
    assert [coupon] = Ledger.list_transactions_for_portfolio(portfolio.id) |> interest_rows()
    assert coupon.security_id == nil
    assert_dec(coupon.gross_amount, "225.00")

    walk = walk(portfolio.id)
    assert_dec(walk.end_value, "10095.00")
    assert_dec(walk.ttwror, "0.022")
    assert_dec(walk.wealth_multiple, "1.0095")
  end

  # User story (#330's discovery):
  # As the maintainer deciding what #330 needs,
  # I want to know what today's valuation does with the same bond when the
  # export's shares are its face amount,
  # so that the verdict can branch on the one fact only the owner's own export
  # can confirm.
  #
  # Acceptance criteria:
  # - The quantity is the face amount; the derived trade price is a fraction
  #   (amount / face amount), so the trade-priced value is still right.
  # - With a percent-of-nominal quote stored, the valuation multiplies the
  #   face amount by the percent figure as if it were a unit price: the value
  #   is a hundred times the market value, in the valuation, the holdings and
  #   the performance walk's end value and wealth multiple alike.
  # - The TTWROR is the same as in the hundredth reading: the first quote's
  #   hundredfold step is neutralised as a basis step (#545), so the return
  #   figure cannot show the error that every money figure shows.
  test "the same bond booked at its face amount: a percent quote is multiplied as if it were a unit price" do
    %{portfolio: portfolio, bond: bond} = import_bond!(face_amount_body())

    {_valuation, position} = only_position(portfolio.id)
    assert_dec(position.quantity, "10000")
    assert position.price_source == :trade
    assert_dec(position.latest_price, "0.985")
    assert_dec(position.market_value, "9850.00")

    put_quote!(bond, @quote_date, "97.25")

    {valuation, position} = only_position(portfolio.id)
    assert position.price_source == :quote
    assert_dec(position.latest_price, "97.25")
    # 10000 x 97.25: the percent figure read as a price per unit of face amount.
    assert_dec(position.market_value, "972500.00")
    assert_dec(valuation.total_with_cash, "972870.00")

    holding = only_holding(portfolio.id)
    assert_dec(holding.avg_cost, "0.985")
    assert_dec(holding.cost_basis, "9850.00")
    assert_dec(holding.market_value, "972500.00")

    walk = walk(portfolio.id)
    assert_dec(walk.end_value, "972870.00")
    assert_dec(walk.ttwror, "0.022")
    assert_dec(walk.wealth_multiple, "97.2870")
  end

  defp interest_rows(transactions), do: Enum.filter(transactions, &(&1.type == "interest"))
end
