defmodule Portfolixir.Portfolios.BondsTest do
  # #330 (ADR-0052): the bond reading the security detail and the API serve,
  # over an invented bond — "Musterland Anleihe 2031", an ISIN with letters
  # in its national part (no real XS number carries them), invented amounts.
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 0, buy!: 3, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios.Bonds

  @as_of ~D[2026-10-02]
  @isin "XSMUSTRL0311"

  defp bond!(attrs \\ %{}) do
    {:ok, security} =
      Catalog.create_security(
        Actor.owner_ui(),
        Map.merge(
          %{
            name: "Musterland Anleihe 2031",
            isin: @isin,
            currency_code: "EUR",
            asset_class: "government_bond",
            coupon_rate: "2.5",
            coupon_frequency: "annual",
            maturity_date: "2031-06-15",
            issue_date: "2021-06-15",
            face_value: "1000"
          },
          attrs
        )
      )

    security
  end

  defp dec(value), do: Decimal.new(value)

  defp deliver!(world, security, opts) do
    {:ok, delivery} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        security_id: security.id,
        type: "inbound_delivery",
        date: Keyword.fetch!(opts, :date),
        quantity: Keyword.fetch!(opts, :quantity),
        price: Keyword.fetch!(opts, :price),
        currency_code: "EUR"
      })

    delivery
  end

  defp assert_scale_6(actual, expected),
    do: assert(Decimal.to_string(actual, :normal) == expected)

  # User story (#330, ADR-0052 §2 and §3; board pick H3-A):
  # As the operator reading a bond held at a hundredth of its face amount,
  # I want its reading to carry the nominal I hold, the remaining term and
  # both yields from the price the valuation uses, each with its basis,
  # so that the detail and the agent read the same figures with their
  # derivation.
  #
  # Acceptance criteria:
  # - 100 units held are a nominal of 10000 in the face value's currency
  #   (the security's while none is set), and the reading states the
  #   hundredth convention.
  # - With a quote of 97.25 the yields use it: 0.025707 and 0.031718, price
  #   source quote with its date.
  # - Every metric carries a computation basis naming its input series,
  #   window, reference and gap treatment.
  # - Without a quote the yields use the last own trade price, 98.50.
  # - Nothing is named as priced on two scales.
  test "a bond held at a hundredth of its face amount reads its nominal, term and yields" do
    world = base_world()
    bond = bond!()
    buy!(world, bond, quantity: "100", price: "98.50", date: ~D[2026-03-12])

    trade_priced = Bonds.reading(bond, as_of: @as_of)
    assert trade_priced.current_yield.price.source == :trade
    assert Decimal.equal?(trade_priced.current_yield.price.value, dec("98.50"))
    assert_scale_6(trade_priced.current_yield.value, "0.025381")

    put_quote!(bond, ~D[2026-09-30], "97.25")
    reading = Bonds.reading(bond, as_of: @as_of)

    assert reading.as_of == @as_of
    assert Decimal.equal?(reading.quantity, dec("100"))
    assert Decimal.equal?(reading.nominal_held.amount, dec("10000"))
    assert reading.nominal_held.currency_code == "EUR"
    assert reading.nominal_held.computation_basis.assumptions =~ "a hundredth of the face amount"

    assert reading.remaining_term.days == 1717
    assert_scale_6(reading.current_yield.value, "0.025707")
    assert_scale_6(reading.yield_to_maturity.value, "0.031718")

    assert %{value: quote_close, date: ~D[2026-09-30], source: :quote} =
             reading.current_yield.price

    assert Decimal.equal?(quote_close, dec("97.25"))

    for metric <- [:nominal_held, :remaining_term, :current_yield, :yield_to_maturity] do
      basis = Map.fetch!(reading, metric).computation_basis

      for key <- [:input_series, :window, :reference, :gaps, :assumptions] do
        assert is_binary(Map.fetch!(basis, key)) and Map.fetch!(basis, key) != "",
               "#{metric}.computation_basis.#{key}"
      end
    end

    assert reading.yield_to_maturity.computation_basis.assumptions =~
             "(coupon + (100 − price) ÷ remaining years) ÷ price"

    assert reading.two_scales == nil
  end

  # User story (#330, the two-scales guard; bond discovery, point 5):
  # As the operator whose export may have booked a bond's nominal as its
  # quantity,
  # I want that bond named as priced on two scales where its figures are
  # read, and listed among the bonds a total holds,
  # so that a hundredfold value is visible although the TTWROR hides it.
  #
  # Acceptance criteria:
  # - 10000 units bought at 0.985 and a quote of 97.25: the reading names the
  #   quote, one buy on the unit scale and that buy, and its nominal reads
  #   1000000 — the figure is shown, not corrected.
  # - two_scales_findings/1 over a set of ids returns that bond, with its
  #   name, and leaves out a bond in the hundredth reading, an unquoted bond
  #   and a non-bond on the same two scales.
  test "a bond booked at its face amount is named as priced on two scales" do
    world = base_world()
    face = bond!()
    buy!(world, face, quantity: "10000", price: "0.985", date: ~D[2026-03-12])
    put_quote!(face, ~D[2026-09-30], "97.25")

    reading = Bonds.reading(face, as_of: @as_of)
    assert Decimal.equal?(reading.nominal_held.amount, dec("1000000"))

    assert %{
             latest_quote: %{close: close, date: ~D[2026-09-30]},
             unit_scale_bookings: 1,
             last_unit_scale_booking: %{price: price, date: ~D[2026-03-12]}
           } = reading.two_scales

    assert Decimal.equal?(close, dec("97.25"))
    assert Decimal.equal?(price, dec("0.985"))

    hundredth = bond!(%{name: "Musterland Anleihe 2029", isin: "XSMUSTRL0295"})
    buy!(world, hundredth, quantity: "50", price: "99.10", date: ~D[2026-03-12])
    put_quote!(hundredth, ~D[2026-09-30], "98.40")

    unquoted = bond!(%{name: "Nordwind Bank Anleihe 2027", isin: "XSNORDWB0270"})
    buy!(world, unquoted, quantity: "10000", price: "0.99", date: ~D[2026-03-12])

    {:ok, etf} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Examplia World ETF",
        currency_code: "EUR",
        asset_class: "etf"
      })

    buy!(world, etf, quantity: "10", price: "1", date: ~D[2026-03-12])
    put_quote!(etf, ~D[2026-09-30], "100")

    assert [finding] =
             Bonds.two_scales_findings([face.id, hundredth.id, unquoted.id, etf.id])

    assert finding.security_id == face.id
    assert finding.name == "Musterland Anleihe 2031"
    assert finding.unit_scale_bookings == 1
  end

  # User story (#330, closing act on U7, finding 4):
  # As the operator whose export delivered a bond in at its nominal rather
  # than buying it,
  # I want a priced inbound delivery read by the guard as a buy is,
  # so that a bond delivered at 0.985 per unit and quoted 97.25 is named,
  # since #779 the delivery's booked price opens its lot and drives its flow
  # exactly as a buy's does.
  #
  # Acceptance criteria:
  # - Delivered in at 0.985 and quoted 97.25: the reading names one booking
  #   on the unit scale and that booking, and two_scales_findings/1 lists the
  #   bond; the rule says "booked price per unit" and names the delivery.
  # - A delivery without a price is not a price per unit and is not read.
  test "a priced inbound delivery on the unit scale is named as a buy is" do
    world = base_world()
    delivered = bond!()
    deliver!(world, delivered, quantity: "10000", price: "0.985", date: ~D[2026-03-12])
    put_quote!(delivered, ~D[2026-09-30], "97.25")

    assert %{unit_scale_bookings: 1, last_unit_scale_booking: %{price: price}, rule: rule} =
             Bonds.reading(delivered, as_of: @as_of).two_scales

    assert Decimal.equal?(price, dec("0.985"))
    assert rule =~ "a booked price per unit (a buy or a priced inbound delivery)"

    unpriced = bond!(%{name: "Musterland Anleihe 2029", isin: "XSMUSTRL0295"})
    deliver!(world, unpriced, quantity: "10000", price: nil, date: ~D[2026-03-12])
    put_quote!(unpriced, ~D[2026-09-30], "97.25")

    assert Bonds.reading(unpriced, as_of: @as_of).two_scales == nil

    assert [%{security_id: id}] = Bonds.two_scales_findings([delivered.id, unpriced.id])
    assert id == delivered.id
  end

  # User story (#330, closing act on U7, finding 3):
  # As the operator's agent reading a bond whose export booked the nominal
  # as the quantity, with no quote stored yet,
  # I want the reading to refuse both yields and say why in the payload,
  # so that a ratio of a coupon to a price per unit of about 1 is never
  # read as a yield.
  #
  # Acceptance criteria:
  # - Bought 10000 at 0.984 without a quote: both yields are null with
  #   price_on_unit_scale true and the trade price they refused; the
  #   nominal held is shown as booked, 1000000.
  # - Each yield's computation basis states the rule: an own trade price of
  #   at most 5, the two-scales band's mirror.
  # - The guard stays silent: it needs a quote.
  test "a bond priced only by an own trade on the unit scale has no yield, and says why" do
    bond = bond!()
    buy!(base_world(), bond, quantity: "10000", price: "0.984", date: ~D[2026-03-12])

    reading = Bonds.reading(bond, as_of: @as_of)
    assert Decimal.equal?(reading.nominal_held.amount, dec("1000000"))

    for metric <- [:current_yield, :yield_to_maturity] do
      yield = Map.fetch!(reading, metric)

      assert yield.value == nil
      assert yield.price_on_unit_scale
      refute yield.insufficient_data
      assert yield.price.source == :trade
      assert Decimal.equal?(yield.price.value, dec("0.984"))
      assert yield.computation_basis.gaps =~ "price_on_unit_scale"
      assert yield.computation_basis.gaps =~ "at most 5"
    end

    assert reading.two_scales == nil
  end

  # User story (#330, ADR-0052 §1; #1068 for the unclassed case below):
  # As the operator whose security is classed as something other than a
  # bond,
  # I want no bond reading for it, whatever master data it carries,
  # so that the detail of a share or a fund does not change.
  #
  # Acceptance criteria:
  # - An ETF has no reading; a security whose class is inferred as a
  #   government bond from its name has one; a bond with no master data has
  #   a reading whose metrics name what is missing, and its nominal held.
  #   (A security with no class at all and bond master data is read as a
  #   bond: the next test.)
  test "only the two bond classes have a reading among classed securities" do
    {:ok, etf} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Examplia World ETF",
        currency_code: "EUR",
        asset_class: "etf",
        coupon_rate: "1"
      })

    assert Bonds.reading(etf, as_of: @as_of) == nil

    {:ok, inferred} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Republic of Examplia 2.25% 2035",
        currency_code: "USD"
      })

    reading = Bonds.reading(inferred, as_of: @as_of)
    assert reading.nominal_held.currency_code == "USD"
    assert Decimal.equal?(reading.nominal_held.amount, dec("0"))
    assert reading.current_yield.missing == ["coupon_rate", "price"]
    assert reading.remaining_term.missing == ["maturity_date"]
  end

  defp unclassed!(name, attrs \\ %{}) do
    {:ok, security} =
      Catalog.create_security(
        Actor.owner_ui(),
        Map.merge(%{name: name, currency_code: "EUR"}, attrs)
      )

    # The name inference misses each of these names, so nothing is stored.
    assert security.asset_class == nil
    security
  end

  # User story (#1068, D-15; board 02, pin 3):
  # As the operator holding a corporate bond the catalog has no class for,
  # because the name inference recognises only government-bond names and
  # explicit bond words (#1127), which its name does not carry,
  # I want the master data I entered (a maturity date or a coupon) to bring
  # it under the two-scales guard,
  # so that a bond on two scales is not silent because it has no class —
  # while an unclassed share that rose twentyfold stays unnamed.
  #
  # Acceptance criteria:
  # - A security with no class (none stored, none inferred) and a maturity
  #   date, bought 10000 at 0.991 and quoted 99.10, is a bond: its reading
  #   names it on two scales, and two_scales_findings/1 lists it as forward,
  #   saying it shows no class.
  # - A coupon alone is master data too.
  # - An unclassed security with no master data, quoted 25 times its buy
  #   price, is no bond: no reading, nothing named.
  # - A security whose stored class is not a bond class stays no bond,
  #   whatever master data it carries (ADR-0052 §1).
  test "an unclassed security carrying bond master data is guarded; one without is not" do
    world = base_world()

    corporate = unclassed!("Ostsee Logistik 4,10% 2028/2033", %{maturity_date: "2033-06-30"})
    buy!(world, corporate, quantity: "10000", price: "0.991", date: ~D[2026-03-12])
    put_quote!(corporate, ~D[2026-09-30], "99.10")

    coupon_only = unclassed!("Ostsee Hafen 3% 2031", %{coupon_rate: "3"})
    buy!(world, coupon_only, quantity: "5000", price: "0.98", date: ~D[2026-03-12])
    put_quote!(coupon_only, ~D[2026-09-30], "98.00")

    share = unclassed!("Ostsee Holz")
    buy!(world, share, quantity: "10", price: "4", date: ~D[2026-03-12])
    put_quote!(share, ~D[2026-09-30], "100")

    {:ok, etf} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Examplia World ETF",
        currency_code: "EUR",
        asset_class: "etf",
        maturity_date: "2033-06-30"
      })

    buy!(world, etf, quantity: "10", price: "1", date: ~D[2026-03-12])
    put_quote!(etf, ~D[2026-09-30], "100")

    assert Bonds.bond?(corporate)
    assert Bonds.bond?(coupon_only)
    refute Bonds.bond?(share)
    refute Bonds.bond?(etf)

    assert %{direction: :forward, unit_scale_bookings: 1} =
             Bonds.reading(corporate, as_of: @as_of).two_scales

    assert Bonds.reading(share, as_of: @as_of) == nil
    assert Bonds.reading(etf, as_of: @as_of) == nil

    assert [hafen, logistik] =
             Bonds.two_scales_findings([corporate.id, coupon_only.id, share.id, etf.id])

    assert %{name: "Ostsee Hafen 3% 2031", direction: :forward, effective_asset_class: nil} =
             hafen

    assert %{
             security_id: id,
             direction: :forward,
             effective_asset_class: nil,
             latest_quote: %{close: close}
           } = logistik

    assert id == corporate.id
    assert Decimal.equal?(close, dec("99.10"))
  end

  # User story (#1068, D-15; board 02, pin 4):
  # As the operator whose stored quotes for a bond sit near 1 while the
  # bond was booked at percent of face, near 100 per unit,
  # I want the bond named as priced on two scales in the reverse direction,
  # where its figures are read and among the bonds a total holds,
  # so that a bond counting a hundredfold too low is named as the forward
  # case is.
  #
  # Acceptance criteria:
  # - A government bond bought 100 at 98.40 and quoted 0.981: the reading's
  #   two_scales is reverse, with the quote and the buy; the nominal reads
  #   10000 as booked — nothing is converted.
  # - two_scales_findings/1 lists it as reverse, with its class.
  # - The rule states both bands, which bonds the guard reads (a bond class,
  #   or no class as shown and a maturity date or coupon), and that nothing
  #   is converted.
  test "a bond whose quotes sit near 1 beside bookings near 100 is named in reverse" do
    world = base_world()
    reverse = bond!()
    buy!(world, reverse, quantity: "100", price: "98.40", date: ~D[2026-03-12])
    put_quote!(reverse, ~D[2026-09-30], "0.981")

    reading = Bonds.reading(reverse, as_of: @as_of)
    assert Decimal.equal?(reading.nominal_held.amount, dec("10000"))

    assert %{
             direction: :reverse,
             latest_quote: %{close: close, date: ~D[2026-09-30]},
             unit_scale_bookings: 1,
             last_unit_scale_booking: %{price: price, date: ~D[2026-03-12]},
             rule: rule
           } = reading.two_scales

    assert Decimal.equal?(close, dec("0.981"))
    assert Decimal.equal?(price, dec("98.40"))

    assert [%{direction: :reverse, effective_asset_class: "government_bond"}] =
             Bonds.two_scales_findings([reverse.id])

    assert rule =~ "between 20 and 500 times a booked price per unit"

    assert rule =~
             "between 1/500 and 1/20 of one, both ends included, with the quote itself at most 5"

    assert rule =~ "direction forward"
    assert rule =~ "direction reverse"
    assert rule =~ "bond or government_bond"

    assert rule =~
             "no asset class as shown (none stored, none inferred), a maturity_date or coupon_rate"

    assert rule =~ "nothing is converted"
  end

  # User story (#1068, review of D-15's signal):
  # As the operator reading the asset class the list and the dialog show,
  # I want the master-data signal to apply only to a security they show
  # without a class, and never to a certificate,
  # so that a security shown as Equity is not badged "ohne Anlageklasse",
  # and a certificate whose expiry is stored as a maturity date is not
  # named as a bond.
  #
  # Acceptance criteria:
  # - A security with no stored class, an ISIN and a stored logo (shown as
  #   Equity by the logo rule) and a maturity date, on two scales, is no
  #   bond: no reading, nothing named.
  # - "Muster Indexzertifikat" with a maturity date, on two scales, is no
  #   bond either: the inference reads its name as a structured product.
  test "the master-data signal needs no class as shown and a name that is no certificate's" do
    world = base_world()

    logo_equity =
      unclassed!("Ostsee Logistik 4,10% 2028/2033", %{
        isin: "XSMUSTRL0303",
        maturity_date: "2033-06-30"
      })

    {:ok, logo_equity} =
      Catalog.put_logo_attributes(logo_equity, %{"logo_path" => "/logos/ostsee.png"})

    assert Security.effective_asset_class(logo_equity) == "equity"
    buy!(world, logo_equity, quantity: "10000", price: "0.991", date: ~D[2026-03-12])
    put_quote!(logo_equity, ~D[2026-09-30], "99.10")

    certificate = unclassed!("Muster Indexzertifikat", %{maturity_date: "2027-12-17"})
    buy!(world, certificate, quantity: "100", price: "1", date: ~D[2026-03-12])
    put_quote!(certificate, ~D[2026-09-30], "100")

    for security <- [logo_equity, certificate] do
      refute Bonds.bond?(security), security.name
      assert Bonds.reading(security, as_of: @as_of) == nil
    end

    assert Bonds.two_scales_findings([logo_equity.id, certificate.id]) == []
  end
end
