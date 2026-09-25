defmodule Portfolixir.Input.BoundedDecimalTest do
  # E25 S4 (#889): one set of decimal bounds shared by every writer and every
  # query parser. G15: a parsed non-finite decimal reached a comparison and
  # answered 500. G16: an amount finer than its column's scale was rounded by
  # the database after validation, so validated, stored and journaled values
  # disagreed. G17: an amount past its column's precision failed in the
  # database instead of as a field error. G14: a weight of arbitrary precision
  # reached the allocation's renormalisation.
  use ExUnit.Case, async: true

  import Ecto.Changeset

  alias Portfolixir.Input.BoundedDecimal

  defp changeset(attrs) do
    cast({%{}, %{amount: :decimal}}, attrs, [:amount])
  end

  test "parse/1 accepts only a clean, finite decimal string" do
    assert BoundedDecimal.parse("0.02") == {:ok, Decimal.new("0.02")}
    assert BoundedDecimal.parse("-1.5") == {:ok, Decimal.new("-1.5")}

    for refused <- ["NaN", "nan", "Infinity", "-Infinity", "inf", "1.5x", "", " 1", nil, 1] do
      assert BoundedDecimal.parse(refused) == :error, "accepted #{inspect(refused)}"
    end
  end

  test "finite?/1 is false for every non-finite value and every non-decimal" do
    assert BoundedDecimal.finite?(Decimal.new("1"))
    refute BoundedDecimal.finite?(Decimal.new("NaN"))
    refute BoundedDecimal.finite?(Decimal.new("Infinity"))
    refute BoundedDecimal.finite?(Decimal.new("-Infinity"))
    refute BoundedDecimal.finite?("1")
  end

  test "quantize/3 rounds half up to the column scale, and only a value finer than it" do
    fine = changeset(%{"amount" => "1.1234565"}) |> BoundedDecimal.quantize(:amount, 6)
    assert Decimal.equal?(get_change(fine, :amount), Decimal.new("1.123457"))
    assert get_change(fine, :amount).exp == -6

    coarse = changeset(%{"amount" => "1.5"}) |> BoundedDecimal.quantize(:amount, 6)
    assert get_change(coarse, :amount) == Decimal.new("1.5")

    to_zero = changeset(%{"amount" => "0.0000004"}) |> BoundedDecimal.quantize(:amount, 6)
    assert Decimal.equal?(get_change(to_zero, :amount), 0)
  end

  test "validate_column/3 refuses a magnitude past the column's precision" do
    ok = changeset(%{"amount" => "99999999999999.999999"})
    assert BoundedDecimal.validate_column(ok, :amount, {20, 6}).valid?

    for refused <- ["100000000000000", "-100000000000000", "1e300"] do
      refused_changeset =
        changeset(%{"amount" => refused}) |> BoundedDecimal.validate_column(:amount, {20, 6})

      refute refused_changeset.valid?, "accepted #{refused}"
      assert [amount: {_message, _}] = refused_changeset.errors
    end
  end

  test "validate_scale/3 refuses more decimal places than allowed, trailing zeros aside" do
    assert changeset(%{"amount" => "0.123456"})
           |> BoundedDecimal.validate_scale(:amount, 6)
           |> Map.fetch!(:valid?)

    assert changeset(%{"amount" => "0.12345600"})
           |> BoundedDecimal.validate_scale(:amount, 6)
           |> Map.fetch!(:valid?)

    refute changeset(%{"amount" => "0.1234567"})
           |> BoundedDecimal.validate_scale(:amount, 6)
           |> Map.fetch!(:valid?)
  end
end
