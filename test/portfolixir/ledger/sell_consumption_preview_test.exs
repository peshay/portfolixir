defmodule Portfolixir.Ledger.SellConsumptionPreviewTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Splits

  # All figures are synthetic. The preview is presentational (ADR-0031
  # correction 1 / issue #620): it shows a GROSS gain and changes nothing
  # about how cost basis is stored or projected.

  defp world do
    world = base_world(name: "Sell Preview", cash_name: "SP Cash", depot_name: "SP Depot")
    security = create_security!(name: "SP Equity", ticker: "SPE", asset_class: "equity")
    Map.put(world, :security, security)
  end

  # User story (issue #620):
  # As a local portfolio maintainer deciding a sale on the transaction form,
  # I want to see which FIFO purchase tranches the sale would consume and
  # the resulting gross gain per tranche,
  # so that I can judge the sale where it is decided, without re-deriving
  # the lot matching myself.
  #
  # Acceptance criteria:
  # - Lots are consumed first-in, first-out, partial last lot included.
  # - Per tranche: open date, consumed quantity, buy price, gross gain
  #   (consumed x (sale price - buy price)), exact Decimals.
  # - The total is the sum of the tranche gains.
  # - The figure is a gross gain: fees and the moving-average basis play no
  #   role here, and nothing about the stored cost basis changes.
  test "walks the FIFO lots for the entered quantity with per-lot gross gains" do
    w = world()
    buy!(w, w.security, quantity: "10", price: "100", date: ~D[2026-01-02])
    buy!(w, w.security, quantity: "10", price: "120", date: ~D[2026-02-02])

    preview =
      Ledger.sell_consumption_preview(w.security.id, Decimal.new("15"), price: Decimal.new("150"))

    assert preview.price_source == :entered
    assert Decimal.equal?(preview.sell_price, Decimal.new("150"))
    assert [first, second] = preview.lots

    assert first.open_date == ~D[2026-01-02]
    assert Decimal.equal?(first.quantity, Decimal.new("10"))
    assert Decimal.equal?(first.buy_price_native, Decimal.new("100"))
    assert Decimal.equal?(first.gross_gain, Decimal.new("500"))

    assert second.open_date == ~D[2026-02-02]
    assert Decimal.equal?(second.quantity, Decimal.new("5"))
    assert Decimal.equal?(second.buy_price_native, Decimal.new("120"))
    assert Decimal.equal?(second.gross_gain, Decimal.new("150"))

    assert Decimal.equal?(preview.total_gross_gain, Decimal.new("650"))
    assert Decimal.equal?(preview.shortfall, Decimal.new("0"))
  end

  # User story (ADR-0028 — splits scale the lots):
  # As a maintainer selling after a split,
  # I want the preview's lots split-scaled exactly like the trade matcher,
  # so that the two surfaces cannot disagree.
  test "split-scaled lots price the preview in the post-split basis" do
    w = world()
    buy!(w, w.security, quantity: "10", price: "100", date: ~D[2026-01-02])
    put_quote!(w.security, ~D[2026-03-01], "55")

    {:ok, _} =
      Splits.book_split(Actor.owner_ui(), %{
        security_id: w.security.id,
        date: ~D[2026-03-01],
        ratio_numerator: 2,
        ratio_denominator: 1
      })

    preview =
      Ledger.sell_consumption_preview(w.security.id, Decimal.new("10"), price: Decimal.new("60"))

    assert [lot] = preview.lots
    assert Decimal.equal?(lot.quantity, Decimal.new("10"))
    assert Decimal.equal?(lot.buy_price_native, Decimal.new("50"))
    assert Decimal.equal?(lot.gross_gain, Decimal.new("100"))
    assert Decimal.equal?(preview.total_gross_gain, Decimal.new("100"))
  end

  # User story (over-sell honesty):
  # As a maintainer entering more quantity than the open lots hold,
  # I want the preview to name the shortfall,
  # so that an over-sell is visible before the ledger rejects or orphans it.
  test "an over-sell reports the uncovered shortfall" do
    w = world()
    buy!(w, w.security, quantity: "10", price: "100", date: ~D[2026-01-02])

    preview =
      Ledger.sell_consumption_preview(w.security.id, Decimal.new("12"), price: Decimal.new("150"))

    assert [lot] = preview.lots
    assert Decimal.equal?(lot.quantity, Decimal.new("10"))
    assert Decimal.equal?(preview.shortfall, Decimal.new("2"))
    assert Decimal.equal?(preview.total_gross_gain, Decimal.new("500"))
  end

  # User story (price fallback):
  # As a maintainer who has not typed a price yet,
  # I want the preview priced at the latest stored quote,
  # so that the tranche view appears as soon as security and quantity are
  # chosen.
  test "falls back to the latest price when no price is entered" do
    w = world()
    buy!(w, w.security, quantity: "10", price: "100", date: ~D[2026-01-02])
    put_quote!(w.security, ~D[2026-06-01], "130")

    preview = Ledger.sell_consumption_preview(w.security.id, Decimal.new("4"))

    assert preview.price_source == :latest
    assert Decimal.equal?(preview.sell_price, Decimal.new("130"))
    assert [lot] = preview.lots
    assert Decimal.equal?(lot.gross_gain, Decimal.new("120"))
  end

  # User story (#620 hard constraint — adopts the #569 currency basis):
  # As a maintainer selling an imported cross-currency position,
  # I want the preview's lots priced on the same security-currency basis and,
  # for cross-currency lots, the same price/currency decomposition as the
  # holdings and lot surfaces,
  # so that the sale preview can never disagree with them.
  #
  # Acceptance criteria (ADR-0033 fixture, sale at USD 110, rate 0.90):
  # - gross gain native: 10 x (110 - 100) = USD 100.
  # - price return 90.00 EUR, currency return 100.00 EUR, total 190.00 EUR.
  test "a cross-currency lot carries the ADR-0033 decomposition" do
    w = base_world(name: "SP FX", cash_name: "SPF Cash", depot_name: "SPF Depot")
    security = create_security!(name: "SP US Equity", ticker: "SPU", currency: "USD")

    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: w.portfolio.id,
        securities_account_id: w.depot.id,
        cash_account_id: w.cash.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-01-15],
        quantity: "10",
        price: "80.00",
        currency_code: "EUR",
        security_amount: "1000.00",
        settlement_amount: "800.00",
        settlement_fx_rate: "0.80"
      })

    preview =
      Ledger.sell_consumption_preview(security.id, Decimal.new("10"),
        price: Decimal.new("110.00"),
        fx_rates: %{"USD" => Decimal.new("0.90")}
      )

    assert [lot] = preview.lots
    assert Decimal.equal?(lot.buy_price_native, Decimal.new("100.00"))
    assert Decimal.equal?(lot.gross_gain, Decimal.new("100.00"))
    assert lot.decomposed
    assert lot.base_currency == "EUR"
    assert Decimal.equal?(lot.price_return_abs, Decimal.new("90.00"))
    assert Decimal.equal?(lot.currency_return_abs, Decimal.new("100.00"))
    assert Decimal.equal?(lot.total_return_base_abs, Decimal.new("190.00"))
  end

  # User story (honesty over availability):
  # As a maintainer whose imported lot has no derivable native leg,
  # I want the preview to show no gain for that lot instead of a blind
  # cross-currency figure, and no total,
  # so that the preview inherits the #569 honesty rules.
  test "a lot with no derivable native leg yields no gain and no total" do
    w = base_world(name: "SP Legacy", cash_name: "SPL Cash", depot_name: "SPL Depot")
    security = create_security!(name: "SP US Legacy", ticker: "SPL", currency: "USD")

    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: w.portfolio.id,
        securities_account_id: w.depot.id,
        cash_account_id: w.cash.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-01-15],
        quantity: "10",
        price: "80.00",
        currency_code: "EUR"
      })

    preview =
      Ledger.sell_consumption_preview(security.id, Decimal.new("10"),
        price: Decimal.new("110.00")
      )

    assert [lot] = preview.lots
    assert lot.buy_price_native == nil
    assert lot.gross_gain == nil
    refute lot.decomposed
    assert lot.undecomposed_reason == :missing_native_cost
    assert preview.total_gross_gain == nil
  end
end
