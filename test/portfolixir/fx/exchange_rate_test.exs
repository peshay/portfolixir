defmodule Portfolixir.Fx.ExchangeRateTest do
  use ExUnit.Case, async: true

  alias Portfolixir.Fx.ExchangeRate

  # User story:
  # As a maintainer storing EUR-hub exchange rates,
  # I want each rate row validated and its currency codes normalised,
  # so that the rate log holds only supported, positively-rated, well-formed
  # entries regardless of how the input was cased or typed.
  #
  # Acceptance criteria:
  # - sources/0 exposes the closed set of rate provenance tags.
  # - A valid row normalises currency codes to trimmed upper case.
  # - A non-positive rate, unsupported currency or unknown source is rejected.
  # - A non-binary currency code is left untouched and fails currency
  #   validation rather than crashing.

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        base_currency: "eur",
        quote_currency: " usd ",
        date: ~D[2026-06-01],
        rate: Decimal.new("1.25"),
        source: "manual"
      },
      overrides
    )
  end

  test "sources/0 lists the known provenance tags" do
    assert ExchangeRate.sources() == ~w(auto manual ecb)
  end

  test "a valid row normalises currency codes to trimmed upper case" do
    changeset = ExchangeRate.changeset(%ExchangeRate{}, valid_attrs())

    assert changeset.valid?
    assert Ecto.Changeset.get_change(changeset, :base_currency) == "EUR"
    assert Ecto.Changeset.get_change(changeset, :quote_currency) == "USD"
  end

  test "rejects a non-positive rate" do
    changeset = ExchangeRate.changeset(%ExchangeRate{}, valid_attrs(%{rate: Decimal.new("0")}))

    refute changeset.valid?
    assert %{rate: _} = errors_on(changeset)
  end

  test "rejects an unsupported currency and an unknown source" do
    bad_currency = ExchangeRate.changeset(%ExchangeRate{}, valid_attrs(%{quote_currency: "ZZZ"}))
    refute bad_currency.valid?
    assert %{quote_currency: _} = errors_on(bad_currency)

    bad_source = ExchangeRate.changeset(%ExchangeRate{}, valid_attrs(%{source: "bogus"}))
    refute bad_source.valid?
    assert %{source: _} = errors_on(bad_source)
  end

  test "leaves a non-binary currency code untouched and fails validation" do
    changeset = ExchangeRate.changeset(%ExchangeRate{}, valid_attrs(%{base_currency: 978}))

    refute changeset.valid?
    # The normalize_code/1 fallback returned the integer unchanged; currency
    # validation then rejects it without raising.
    assert %{base_currency: _} = errors_on(changeset)
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end
end
