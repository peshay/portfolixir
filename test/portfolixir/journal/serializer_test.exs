defmodule Portfolixir.Journal.SerializerTest do
  use ExUnit.Case, async: true

  alias Portfolixir.Journal.Serializer

  # ADR-0016: Decimals encode as strings (Jason's default would emit floats and
  # lose precision); dates as ISO strings; an unmapped type raises so a new field
  # cannot be silently dropped from the audit record.

  test "encodes Decimals as lossless strings, not floats" do
    # The exact stored representation is preserved (an audit record keeps the
    # value as written, trailing zeros and all) — and it is a string, never a float.
    assert Serializer.encode_value(Decimal.new("12.340")) == "12.340"
    assert Serializer.encode_value(Decimal.new("0.1")) == "0.1"
    assert is_binary(Serializer.encode_value(Decimal.new("0.1")))
  end

  test "encodes dates, datetimes, naive datetimes and times as ISO-8601 strings" do
    assert Serializer.encode_value(~D[2026-06-14]) == "2026-06-14"
    assert Serializer.encode_value(~U[2026-06-14 10:00:00Z]) == "2026-06-14T10:00:00Z"
    assert Serializer.encode_value(~N[2026-06-14 10:00:00]) == "2026-06-14T10:00:00"
    assert Serializer.encode_value(~T[10:00:00]) == "10:00:00"
  end

  test "encodes lists element-wise and recurses into nested structs" do
    assert Serializer.encode_value([Decimal.new("1.5"), ~D[2026-06-14], :etf]) ==
             ["1.5", "2026-06-14", "etf"]

    nested = Serializer.encode_value(%Portfolixir.Catalog.Security{name: "X", asset_class: "etf"})
    assert nested["name"] == "X"
    assert nested["asset_class"] == "etf"
  end

  test "encodes an unloaded association as nil" do
    assert Serializer.encode_value(%Ecto.Association.NotLoaded{
             __field__: :x,
             __owner__: nil,
             __cardinality__: :one
           }) == nil
  end

  defmodule PlainStruct do
    defstruct [:a, :b]
  end

  test "passes through JSON-native scalars" do
    assert Serializer.encode_value("x") == "x"
    assert Serializer.encode_value(7) == 7
    assert Serializer.encode_value(1.5) == 1.5
    assert Serializer.encode_value(true) == true
    assert Serializer.encode_value(nil) == nil
    assert Serializer.encode_value(:etf) == "etf"
  end

  test "snapshot/1 handles a plain (non-Ecto) struct via its fields" do
    snap = Serializer.snapshot(%PlainStruct{a: 1, b: Decimal.new("2.5")})
    assert snap == %{"a" => 1, "b" => "2.5"}
  end

  test "snapshot/1 drops association placeholders and stringifies keys" do
    snap = Serializer.snapshot(%{id: 1, name: "X", count: %Ecto.Association.NotLoaded{}})
    assert snap["id"] == 1
    assert snap["name"] == "X"
    assert snap["count"] == nil
  end

  test "raises on an unmapped type rather than dropping it" do
    assert_raise ArgumentError, ~r/no mapping for/, fn ->
      Serializer.encode_value(self())
    end
  end
end
