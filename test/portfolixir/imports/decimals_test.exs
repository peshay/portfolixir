defmodule Portfolixir.Imports.DecimalsTest do
  use ExUnit.Case, async: true

  alias Portfolixir.Imports.Decimals

  # User story:
  # As an import author parsing Portfolio Performance CSV/JSON,
  # I want number strings to decode into exact `Decimal` values without
  # passing through floats,
  # so that imported values remain auditable down to the last cent.

  describe "parse_de/1" do
    test "parses positive German amounts with thousands separator" do
      assert {:ok, value} = Decimals.parse_de("23.685,40")
      assert Decimal.equal?(value, Decimal.new("23685.40"))
    end

    test "parses values without thousands separator" do
      assert {:ok, value} = Decimals.parse_de("9,13")
      assert Decimal.equal?(value, Decimal.new("9.13"))
    end

    test "parses integers without a decimal comma" do
      assert {:ok, value} = Decimals.parse_de("100")
      assert Decimal.equal?(value, Decimal.new("100"))
    end

    test "returns nil for empty string and nil" do
      assert {:ok, nil} = Decimals.parse_de("")
      assert {:ok, nil} = Decimals.parse_de(nil)
    end

    test "errors on non-numeric input" do
      assert {:error, {:invalid_decimal, "abc"}} = Decimals.parse_de("abc")
    end
  end

  describe "parse/1" do
    test "passes through an existing Decimal" do
      d = Decimal.new("1.23")
      assert {:ok, ^d} = Decimals.parse(d)
    end

    test "parses an integer" do
      assert {:ok, value} = Decimals.parse(42)
      assert Decimal.equal?(value, Decimal.new("42"))
    end

    test "parses a plain numeric string" do
      assert {:ok, value} = Decimals.parse("123.45")
      assert Decimal.equal?(value, Decimal.new("123.45"))
    end

    test "returns nil for nil input" do
      assert {:ok, nil} = Decimals.parse(nil)
    end

    test "rejects bare floats so callers cannot accidentally lose precision" do
      assert {:error, {:invalid_decimal, _}} = Decimals.parse(1.5)
    end
  end
end
