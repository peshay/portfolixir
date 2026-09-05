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

  @default_max_rows 100_000

  @doc """
  The most rows one export may carry (#768): a bound on how much of one file
  the preview holds in memory. Configurable as `:import_max_rows`.
  """
  @spec max_rows() :: pos_integer()
  def max_rows, do: Application.get_env(:portfolixir, :import_max_rows, @default_max_rows)

  @spec parse(binary(), keyword()) :: {:ok, Preview.t()} | {:error, term()}
  def parse(body, opts \\ []) when is_binary(body) do
    case detect_format(body, Keyword.get(opts, :filename)) do
      :json -> JsonParser.parse(body, opts)
      :csv -> CsvParser.parse(body, opts)
      :unknown -> {:error, :unknown_format}
    end
  rescue
    # The parsers run in the operator's LiveView process; untrusted input
    # must never reach that process boundary as an exception (#768).
    _exception -> {:error, :malformed_payload}
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
