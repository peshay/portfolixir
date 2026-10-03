defmodule Portfolixir.Portfolios.BondsTest do
  # #330 (ADR-0052): the bond reading the security detail and the API serve,
  # over an invented bond — "Musterland Anleihe 2031", an ISIN with letters
  # in its national part (no real XS number carries them), invented amounts.
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 0, buy!: 3, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
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
             unit_scale_buys: 1,
             last_unit_scale_buy: %{price: price, date: ~D[2026-03-12]}
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
    assert finding.unit_scale_buys == 1
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

  # User story (#330, ADR-0052 §1):
  # As the operator whose security is not a bond,
  # I want no bond reading for it, whatever master data it carries,
  # so that the detail of a share or a fund does not change.
  #
  # Acceptance criteria:
  # - An ETF has no reading; a security whose class is inferred as a
  #   government bond from its name has one; a bond with no master data has
  #   a reading whose metrics name what is missing, and its nominal held.
  test "only the two bond classes have a reading" do
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
end
