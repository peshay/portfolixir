defmodule Portfolixir.Imports.PortfolioPerformance do
  @moduledoc """
  Format dispatch for Portfolio Performance exports.

  Routes a raw upload to either the JSON v1 parser or the CSV parser
  based on content sniffing (with the original filename as a tie-
  breaker) and returns a `Portfolixir.Imports.Preview`.

  Out of scope for this story: PP XML (`*.xml`) and the
  binary `*.portfolio` workspace file — both are tracked as follow-up
  formats.
  """

  alias Portfolixir.Imports.PortfolioPerformance.CsvParser
  alias Portfolixir.Imports.PortfolioPerformance.JsonParser
  alias Portfolixir.Imports.Preview

  @spec parse(binary(), keyword()) :: {:ok, Preview.t()} | {:error, term()}
  def parse(body, opts \\ []) when is_binary(body) do
    case detect_format(body, Keyword.get(opts, :filename)) do
      :json -> JsonParser.parse(body, opts)
      :csv -> CsvParser.parse(body, opts)
      :unknown -> {:error, :unknown_format}
    end
  end

  defp detect_format(body, filename) do
    cond do
      filename && String.ends_with?(String.downcase(filename), ".json") -> :json
      filename && String.ends_with?(String.downcase(filename), ".csv") -> :csv
      starts_with_brace?(body) -> :json
      looks_like_pp_csv_header?(body) -> :csv
      true -> :unknown
    end
  end

  defp starts_with_brace?(body) do
    body
    |> String.trim_leading()
    |> String.starts_with?("{")
  end

  defp looks_like_pp_csv_header?(body) do
    body
    |> String.split("\n", parts: 2)
    |> List.first()
    |> Kernel.||("")
    |> String.contains?("Datum;Typ;Wertpapier")
  end
end
