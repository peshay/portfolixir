defmodule PortfolixirWeb.LiveParamTest do
  use ExUnit.Case, async: true

  alias PortfolixirWeb.LiveParam

  @max_int8 9_223_372_036_854_775_807

  test "an id is a positive integer within the bigint range, or nil" do
    assert LiveParam.id("42") == 42
    assert LiveParam.id(42) == 42
    assert LiveParam.id(Integer.to_string(@max_int8)) == @max_int8

    for value <- [
          Integer.to_string(@max_int8 + 1),
          @max_int8 + 1,
          "0",
          "-1",
          "4x",
          " 4",
          "",
          "total",
          nil,
          4.0,
          ["4"],
          %{"id" => "4"}
        ] do
      assert LiveParam.id(value) == nil, "#{inspect(value)} read as an id"
      assert LiveParam.fetch_id(value) == :error
    end

    assert LiveParam.fetch_id("7") == {:ok, 7}
  end

  test "ids keep what is an id and drop the rest" do
    assert LiveParam.ids(["1", 2, "x", "99999999999999999999999", nil]) == [1, 2]
    assert LiveParam.ids("3, 4,,x") == [3, 4]
    assert LiveParam.ids(%{"a" => "1"}) == []
    assert LiveParam.ids(nil) == []
  end

  test "a year is one a calendar names and an int4 column holds" do
    assert LiveParam.year("2025") == 2025
    assert LiveParam.year(1) == 1
    assert LiveParam.year("9999") == 9999

    for value <- ["0", "10000", "2147483648", "99999999999999999999999", "20x5", nil, ["2025"]] do
      assert LiveParam.year(value) == nil, "#{inspect(value)} read as a year"
    end
  end

  test "a bounded integer is inside its range or nil" do
    assert LiveParam.integer("3", 0..5) == 3
    assert LiveParam.integer(0, 0..5) == 0
    assert LiveParam.integer("6", 0..5) == nil
    assert LiveParam.integer("-1", 0..5) == nil
    assert LiveParam.integer(%{}, 0..5) == nil
  end

  test "a string and a form map are what they say or nothing" do
    assert LiveParam.string("a") == "a"
    assert LiveParam.string(1) == nil
    assert LiveParam.map(%{"a" => 1}) == %{"a" => 1}
    assert LiveParam.map("a") == %{}
    assert LiveParam.map(["a"]) == %{}
    assert LiveParam.map(~D[2026-01-01]) == %{}
  end
end
