defmodule Portfolixir.Imports.PortfolioPerformanceTest do
  use ExUnit.Case, async: true

  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Imports.Preview

  @fixtures Path.expand("../../support/fixtures/portfolio_performance", __DIR__)

  defp read!(name), do: File.read!(Path.join(@fixtures, name))

  # User story:
  # As the LiveView upload handler receiving an arbitrary
  # drag-and-drop file,
  # I want one entry point that figures out whether the bytes are
  # PP JSON v1 or PP CSV and routes to the right parser,
  # so that the user does not have to tell us the format.

  describe "parse/2 format detection" do
    test "routes JSON bodies to the JSON parser" do
      body = read!("sample.json")
      assert {:ok, %Preview{format: :json}} = PortfolioPerformance.parse(body)
    end

    test "routes CSV bodies to the CSV parser" do
      body = read!("sample.csv")
      assert {:ok, %Preview{format: :csv}} = PortfolioPerformance.parse(body)
    end

    test "uses the filename hint when content sniffing is ambiguous" do
      body = read!("sample.json")
      assert {:ok, %Preview{format: :json}} = PortfolioPerformance.parse(body, filename: "x.json")
    end

    test "errors on neither-json-nor-csv input" do
      assert {:error, :unknown_format} = PortfolioPerformance.parse("hello world")
    end
  end
end
