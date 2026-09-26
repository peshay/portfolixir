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

  # User story (E25 S5, F39):
  # As an operator importing an export I did not write,
  # I want a number too large for any ledger column refused where it is read,
  # so that no later arithmetic on it runs past what a Decimal can hold.
  #
  # Acceptance criteria:
  # - A value with more integer digits than the importer bounds is
  #   {:error, {:invalid_decimal, original}} on every input path: a German
  #   string, a plain string, an integer and an already-decoded Decimal.
  # - A value at the bound still parses.
  describe "integer-digit bound" do
    test "refuses a value past the bound on every path and keeps one at it" do
      max = Decimals.max_integer_digits()
      at = String.duplicate("9", max)
      past = String.duplicate("9", max + 1)

      assert {:ok, _} = Decimals.parse(at)
      assert {:ok, _} = Decimals.parse_de(at)

      assert {:error, {:invalid_decimal, ^past}} = Decimals.parse(past)
      assert {:error, {:invalid_decimal, ^past}} = Decimals.parse_de(past)
      assert {:error, {:invalid_decimal, _}} = Decimals.parse(String.to_integer(past))
      assert {:error, {:invalid_decimal, _}} = Decimals.parse(Decimal.new("9e999"))
      assert {:error, {:invalid_decimal, "1e40"}} = Decimals.parse("1e40")
      assert {:error, {:invalid_decimal, "1e40"}} = Decimals.parse_de("1e40")
    end
  end
end
