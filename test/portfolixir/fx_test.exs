defmodule Portfolixir.FxTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Fx

  # User story:
  # As a portfolio maintainer holding securities in several currencies,
  # I want amounts converted between currencies from stored EUR-hub rates,
  # so that values and weights are precise and meaningful in one base currency.
  #
  # Acceptance criteria:
  # - Same-currency conversion is the identity (no rounding).
  # - Direct, inverse, and cross-currency conversions triangulate through EUR.
  # - GBX (pence) is handled as GBP x 100.
  # - A missing rate path returns {:error, :no_rate} rather than a wrong number.
  # - A dated conversion uses the most recent rate on or before that date.

  defp rate(quote, value, date \\ ~D[2026-06-04]) do
    %{base_currency: "EUR", quote_currency: quote, date: date, rate: value, source: "manual"}
  end

  defp seed_rates! do
    {:ok, _} = Fx.upsert_many([rate("USD", "1.25"), rate("GBP", "0.8")])
  end

  defp d(value), do: Decimal.new(value)

  test "same-currency conversion is the identity" do
    assert {:ok, amount} = Fx.convert(d("100"), "USD", "USD")
    assert Decimal.equal?(amount, d("100"))
  end

  test "converts directly and inversely against the EUR hub" do
    seed_rates!()

    assert {:ok, usd} = Fx.convert(d("100"), "EUR", "USD")
    assert Decimal.equal?(usd, d("125"))

    assert {:ok, eur} = Fx.convert(d("100"), "USD", "EUR")
    assert Decimal.equal?(eur, d("80"))
  end

  test "triangulates a cross pair through EUR" do
    seed_rates!()

    assert {:ok, gbp} = Fx.convert(d("100"), "USD", "GBP")
    assert Decimal.equal?(gbp, d("64"))
  end

  test "treats GBX as GBP x 100 in both directions" do
    seed_rates!()

    assert {:ok, gbx} = Fx.convert(d("5"), "GBP", "GBX")
    assert Decimal.equal?(gbx, d("500"))

    assert {:ok, gbp} = Fx.convert(d("500"), "GBX", "GBP")
    assert Decimal.equal?(gbp, d("5"))

    assert {:ok, gbx_from_usd} = Fx.convert(d("1"), "USD", "GBX")
    assert Decimal.equal?(gbx_from_usd, d("64"))
  end

  test "returns :no_rate when no path to the target currency exists" do
    seed_rates!()
    assert {:error, :no_rate} = Fx.convert(d("100"), "USD", "JPY")
  end

  test "a dated conversion uses the most recent rate on or before the date" do
    {:ok, _} =
      Fx.upsert_many([
        rate("USD", "1.20", ~D[2026-06-01]),
        rate("USD", "1.25", ~D[2026-06-04])
      ])

    assert {:ok, on_date} = Fx.convert(d("100"), "EUR", "USD", ~D[2026-06-02])
    assert Decimal.equal?(on_date, d("120"))

    assert {:ok, latest} = Fx.convert(d("100"), "EUR", "USD")
    assert Decimal.equal?(latest, d("125"))
  end
end
