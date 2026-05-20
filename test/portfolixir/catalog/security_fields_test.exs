defmodule Portfolixir.Catalog.SecurityFieldsTest do
  use ExUnit.Case, async: true

  alias Portfolixir.Catalog.Security
  alias Portfolixir.Catalog.SecurityFields
  alias Portfolixir.Catalog.SecurityFields.Field

  describe "visible_default/0" do
    test "lists at least name, ticker_symbol, isin, currency_code, asset_class" do
      defaults = SecurityFields.visible_default()

      for key <- [:name, :ticker_symbol, :isin, :currency_code, :asset_class] do
        assert key in defaults, "expected #{inspect(key)} to be a default-visible column"
      end
    end
  end

  describe "value/2" do
    test "extracts column values" do
      field = SecurityFields.get!(:name)
      security = %Security{name: "Apple Inc."}
      assert SecurityFields.value(field, security) == "Apple Inc."
    end

    test "infers asset class display value for imported securities with blank asset_class" do
      field = SecurityFields.get!(:asset_class)

      assert SecurityFields.value(field, %Security{
               name: "iShares Core MSCI Emerging Markets IMI UCITS ETF",
               asset_class: nil
             }) == "etf"

      assert SecurityFields.value(field, %Security{
               name: "Anleihe USA 20/50",
               isin: "US912810SN90",
               asset_class: nil
             }) == "government_bond"
    end

    test "extracts JSONB-backed values via the registered key" do
      field = SecurityFields.get!(:attr_exchange_name)
      security = %Security{attributes: %{"exchange_name" => "NASDAQ"}}
      assert SecurityFields.value(field, security) == "NASDAQ"
    end

    test "returns nil when JSONB key is missing" do
      field = SecurityFields.get!(:attr_exchange_name)
      security = %Security{attributes: %{}}
      assert SecurityFields.value(field, security) == nil
    end
  end

  describe "valid_filter?/3" do
    test "string fields accept contains/starts_with/eq/neq" do
      assert SecurityFields.valid_filter?(:name, :contains, "foo")
      assert SecurityFields.valid_filter?(:name, :starts_with, "f")
      assert SecurityFields.valid_filter?(:name, :eq, "x")
      assert SecurityFields.valid_filter?(:name, :neq, "x")
    end

    test "string fields reject gt/lt" do
      refute SecurityFields.valid_filter?(:name, :gt, "x")
      refute SecurityFields.valid_filter?(:name, :lt, "x")
    end

    test "boolean fields only accept is_true / is_false" do
      assert SecurityFields.valid_filter?(:is_retired, :is_true, nil)
      assert SecurityFields.valid_filter?(:is_retired, :is_false, nil)
      refute SecurityFields.valid_filter?(:is_retired, :eq, true)
    end

    test "JSONB attribute-backed fields are not filterable in v1" do
      # Filters mirror what Portfolio Performance offers; attribute-backed
      # fields are intentionally non-filterable until we add typed casts.
      refute SecurityFields.valid_filter?(:attr_market_cap_rank, :gt, "10")
      refute SecurityFields.valid_filter?(:attr_market_cap_rank, :eq, "10")
      refute SecurityFields.valid_filter?(:attr_exchange_name, :eq, "NASDAQ")
    end

    test "unknown keys are rejected" do
      refute SecurityFields.valid_filter?(:nope, :eq, "foo")
    end
  end

  describe "filterable/0 and sortable/0" do
    test "returns only Field structs with the respective flag set" do
      Enum.each(SecurityFields.filterable(), fn %Field{filterable?: f} -> assert f end)
      Enum.each(SecurityFields.sortable(), fn %Field{sortable?: f} -> assert f end)
    end
  end
end
