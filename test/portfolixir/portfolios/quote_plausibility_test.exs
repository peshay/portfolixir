defmodule Portfolixir.Portfolios.QuotePlausibilityTest do
  # #1101 (Sprint 20 β B4, plan D-7; board ux-design-2026-10-07/02-money-findings,
  # pick L2 A): the shell half of the implausible_quote guard. It loads each
  # buy, sell and priced inbound delivery with the latest stored quote of its
  # 7-day window, puts the booked price in the security's currency, and
  # leaves out a security the two-scales guard already names.
  #
  # The data is invented. "Arbolia Inc." and "Wrenfield Gardens AG" are the
  # board's: Arbolia (USD) sold 03.04.2026 at 61,40 with no quote stored that
  # day and 618,90 the day before; Wrenfield (EUR) bought 12.05.2026 at 48,20
  # with 4,87 that day.
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, put_quote!: 3, sell!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quote, as: SecurityQuote
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Splits
  alias Portfolixir.Portfolios.Bonds
  alias Portfolixir.Portfolios.QuotePlausibility

  defp d(value), do: Decimal.new(value)

  defp board! do
    usd = base_world(name: "USD Depot", currency: "USD")
    eur = base_world(name: "EUR Depot")

    arbolia = create_security!(name: "Arbolia Inc.", ticker: "ARBL", currency: "USD")
    buy!(usd, arbolia, quantity: "50", price: "58.20", currency: "USD", date: ~D[2025-11-03])
    sell!(usd, arbolia, quantity: "10", price: "61.40", currency: "USD", date: ~D[2026-04-03])
    put_quote!(arbolia, ~D[2026-04-02], "618.90")
    put_quote!(arbolia, ~D[2026-10-06], "619.40")

    wrenfield = create_security!(name: "Wrenfield Gardens AG", ticker: "WGA")
    buy!(eur, wrenfield, quantity: "120", price: "48.20", date: ~D[2026-05-12])
    put_quote!(wrenfield, ~D[2026-05-12], "4.87")

    # A real rise: each booking matched its own day's quote.
    riser = create_security!(name: "Halden Robotics AG", ticker: "HRB")
    buy!(eur, riser, quantity: "30", price: "10.00", date: ~D[2024-01-10])
    put_quote!(riser, ~D[2024-01-10], "10.20")
    sell!(eur, riser, quantity: "10", price: "200.00", date: ~D[2026-03-02])
    put_quote!(riser, ~D[2026-03-02], "198.00")
    put_quote!(riser, ~D[2026-10-06], "210.00")

    %{usd: usd, eur: eur, arbolia: arbolia, wrenfield: wrenfield, riser: riser}
  end

  # User story (#1101, D-7):
  # As the operator whose ticker was mapped to another listing,
  # I want each such security named with the booking its quotes contradict,
  # so that I can check its quote source, then the booking.
  #
  # Acceptance criteria (exact Decimal expectations):
  # - Arbolia: sell 2026-04-03 at 61.40 USD, quote of 2026-04-02 618.90 (no
  #   quote stored on the day), ratio 618.90 / 61.40, one booking outside
  #   (its buy of 2025-11-03 has no quote in its window and is not compared).
  # - Wrenfield: buy 2026-05-12 at 48.20 EUR, quote that day 4.87, ratio
  #   4.87 / 48.20.
  # - The twentyfold riser is not named, though its latest quote is 21 times
  #   its buy. The findings are sorted by name.
  test "names a mis-mapped series with the booking it contradicts, never a real rise" do
    %{arbolia: arbolia, wrenfield: wrenfield, riser: riser} = board!()

    assert [first, second] = QuotePlausibility.findings([arbolia.id, wrenfield.id, riser.id])

    assert first.security_id == arbolia.id
    assert first.name == "Arbolia Inc."
    assert first.currency_code == "USD"
    assert first.kind == "sell"
    assert first.date == ~D[2026-04-03]
    assert Decimal.equal?(first.price, d("61.40"))
    assert first.quote_date == ~D[2026-04-02]
    assert Decimal.equal?(first.close, d("618.90"))
    assert Decimal.equal?(first.ratio, Decimal.div(d("618.90"), d("61.40")))
    assert first.bookings_outside == 1

    assert second.security_id == wrenfield.id
    assert second.currency_code == "EUR"
    assert second.kind == "buy"
    assert second.date == ~D[2026-05-12]
    assert Decimal.equal?(second.price, d("48.20"))
    assert second.quote_date == ~D[2026-05-12]
    assert Decimal.equal?(second.close, d("4.87"))
    assert Decimal.equal?(second.ratio, Decimal.div(d("4.87"), d("48.20")))

    assert QuotePlausibility.findings([riser.id]) == []
  end

  # User story (board 02, found while drawing 3):
  # As the operator holding a bond of a 1.000 denomination booked per piece
  # beside percent quotes,
  # I want it named here, since the two-scales bands do not reach a ratio
  # of 1/10,
  # so that its fix — the booked quantity — is asked for ("then the
  # booking").
  #
  # Acceptance criteria:
  # - Bought 10 at 985.00 per piece, quoted 98.50 that day: the two-scales
  #   guard is silent, and this one names it, ratio 0.1.
  test "a bond booked per piece beside percent quotes is named, outside both two-scales bands" do
    world = base_world(name: "Anleihen")

    {:ok, bond} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Talgrund Energie Anleihe 2030 3,10%",
        currency_code: "EUR",
        asset_class: "bond",
        face_value: "1000"
      })

    buy!(world, bond, quantity: "10", price: "985.00", date: ~D[2026-06-15])
    put_quote!(bond, ~D[2026-06-15], "98.50")

    assert Bonds.two_scales_among([bond]) == []
    assert [finding] = QuotePlausibility.findings([bond.id])
    assert Decimal.equal?(finding.ratio, d("0.1"))
  end

  # User story (#1101, D-7 "Overlap"):
  # As the operator,
  # I want a bond the two-scales guard names left out of this finding,
  # so that one fault is named once, by the rule that names its cause more
  # precisely.
  #
  # Acceptance criteria:
  # - A bond bought at 0.985 per unit and quoted 97.25 that day (ratio about
  #   98.7, outside [1/2, 2]) is in the two-scales findings and not here.
  test "a security the two-scales guard names is not counted again" do
    world = base_world(name: "Anleihen")

    {:ok, bond} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Kestrel Anleihe 2030 2,75%",
        currency_code: "EUR",
        asset_class: "bond"
      })

    buy!(world, bond, quantity: "10000", price: "0.985", date: ~D[2026-03-12])
    put_quote!(bond, ~D[2026-03-12], "97.25")

    assert [%{direction: :forward}] = Bonds.two_scales_among([bond])
    assert QuotePlausibility.findings([bond.id]) == []
  end

  # User story (board 02, found while drawing 1; ADR-0028 §2):
  # As the operator whose security split,
  # I want a provider's back-adjusted quotes read on my booking's basis,
  # so that a recorded split is not named and an unrecorded one is.
  #
  # Acceptance criteria (10 bought at 100.00 on 2026-01-05, a provider
  # quote of 10.05 that day after a 10:1 split effective 2026-02-01):
  # - With the split recorded: nothing named.
  # - Without it: named, ratio 0.1005 — the remedy is to record the split.
  test "a recorded split is not named, an unrecorded one is" do
    world = base_world(name: "Splits")

    recorded = create_security!(name: "Lindmoor Werke AG", ticker: "LMW")
    unrecorded = create_security!(name: "Saltcombe Mills AG", ticker: "SCM")

    for security <- [recorded, unrecorded] do
      buy!(world, security, quantity: "10", price: "100.00", date: ~D[2026-01-05])

      {:ok, _} =
        %SecurityQuote{}
        |> SecurityQuote.changeset(%{
          security_id: security.id,
          date: ~D[2026-01-05],
          close: d("10.05"),
          source: "portfolio_performance"
        })
        |> Repo.insert()
    end

    {:ok, _} =
      Splits.book_split(Actor.owner_ui(), %{
        security_id: recorded.id,
        date: ~D[2026-02-01],
        ratio_numerator: 10,
        ratio_denominator: 1
      })

    assert [finding] = QuotePlausibility.findings([recorded.id, unrecorded.id])
    assert finding.security_id == unrecorded.id
    assert Decimal.equal?(finding.ratio, d("0.1005"))
  end

  # User story (#1101, D-7 "in the same currency"):
  # As the operator who booked a USD security in EUR,
  # I want the booking compared in the security's currency,
  # so that a EUR price is never set against a USD quote.
  #
  # Acceptance criteria (USD quotes of 101.00 and 9.10 on the booking day):
  # - Booked in EUR at 92.00 with a security_amount of 1000.00 USD for 10:
  #   compared at 100 USD, not named.
  # - Booked in EUR at 92.00 with no security_amount: not compared (it
  #   would read ratio 0.099 against 9.10 if it were).
  # - Booked in EUR with a security_amount of 100.00 USD for 10: compared at
  #   10 USD against 101.00 and named, price 10, currency USD.
  test "a booking in another currency is compared at its security-currency leg, or not at all" do
    world = base_world(name: "Kreuzwährung")

    eur_buy = fn security, extra ->
      {:ok, _} =
        Ledger.create_transaction(
          Actor.owner_ui(),
          Map.merge(
            %{
              portfolio_id: world.portfolio.id,
              securities_account_id: world.depot.id,
              cash_account_id: world.cash.id,
              security_id: security.id,
              type: "buy",
              date: ~D[2026-05-12],
              quantity: "10",
              price: "92.00",
              currency_code: "EUR"
            },
            extra
          )
        )
    end

    legged = create_security!(name: "Corvane Systems Inc.", ticker: "CVS", currency: "USD")
    eur_buy.(legged, %{security_amount: "1000.00", gross_amount: "920.00"})
    put_quote!(legged, ~D[2026-05-12], "101.00")

    legless = create_security!(name: "Dunmere Freight Inc.", ticker: "DFR", currency: "USD")
    eur_buy.(legless, %{})
    put_quote!(legless, ~D[2026-05-12], "9.10")

    off = create_security!(name: "Ellwood Biotech Inc.", ticker: "EWB", currency: "USD")
    eur_buy.(off, %{security_amount: "100.00", gross_amount: "920.00"})
    put_quote!(off, ~D[2026-05-12], "101.00")

    assert [finding] = QuotePlausibility.findings([legged.id, legless.id, off.id])
    assert finding.security_id == off.id
    assert finding.currency_code == "USD"
    assert Decimal.equal?(finding.price, d("10"))
    assert Decimal.equal?(finding.ratio, d("10.1"))
  end

  # User story (#1101, D-7 basis; the AGENTS.md metric rule):
  # As the agent reading the finding,
  # I want its computation basis stated in the payload's terms,
  # so that I can check what was compared, over which window, and what was
  # skipped.
  #
  # Acceptance criteria:
  # - input_series, reference, window, gaps and threshold, each naming its
  #   rule: the stored quotes, each booking's price per unit, 7 days before
  #   the booking date, a booking with no quote in the window is not
  #   compared, and 2.
  test "the computation basis states the series, the reference, the window, the gaps and the threshold" do
    basis = QuotePlausibility.computation_basis()

    assert basis.input_series =~ "the stored quotes"
    assert basis.input_series =~ "ADR-0028 §2"
    assert basis.reference =~ "each booking's price per unit"
    assert basis.reference =~ "a price of 0 has no ratio"
    assert basis.window =~ "7 days before the booking date"
    assert basis.gaps =~ "a booking with no quote in the window is not compared"
    assert basis.threshold =~ "2:"
    assert basis.threshold =~ "below 1/2 or above 2"
    assert basis.assumptions =~ "two_scales"
  end
end
