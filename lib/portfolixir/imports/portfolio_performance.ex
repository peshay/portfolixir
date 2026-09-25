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

  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Imports.Entry
  alias Portfolixir.Imports.PortfolioPerformance.CsvParser
  alias Portfolixir.Imports.PortfolioPerformance.JsonParser
  alias Portfolixir.Imports.Preview
  alias Portfolixir.Imports.SecurityResolver
  alias Portfolixir.Input.Text

  @default_max_rows 100_000

  @doc """
  The most rows one export may carry (#768): a bound on how much of one file
  the preview holds in memory. Configurable as `:import_max_rows`.
  """
  @spec max_rows() :: pos_integer()
  def max_rows, do: Application.get_env(:portfolixir, :import_max_rows, @default_max_rows)

  @spec parse(binary(), keyword()) :: {:ok, Preview.t()} | {:error, term()}
  def parse(body, opts \\ []) when is_binary(body) do
    # E25 S5 (F34): a body that is not UTF-8 is a named file error before any
    # row is read, so no cell of it can reach the preview the page parks.
    if String.valid?(body) do
      parse_valid(body, opts)
    else
      {:error, :invalid_encoding}
    end
  rescue
    # The parsers run in the operator's LiveView process; untrusted input
    # must never reach that process boundary as an exception (#768).
    _exception -> {:error, :malformed_payload}
  end

  defp parse_valid(body, opts) do
    case detect_format(body, Keyword.get(opts, :filename)) do
      :json -> JsonParser.parse(body, opts)
      :csv -> CsvParser.parse(body, opts)
      :unknown -> {:error, :unknown_format}
    end
  end

  # The text of an entry the ledger stores, each with the rule its column
  # applies (E25 S4, G24): a name is one line within its column's width, a
  # note keeps its line breaks.
  @name_rule [max: 255]
  @note_rule [multiline: true]

  @doc """
  Why a parsed entry cannot be a row of the preview, as the row's message, or
  `nil`. Both parsers run it on every entry they build, so a row the apply
  could never book is named in the preview instead:

    * a security reference that names nothing — no name, ISIN, WKN or ticker
      in catalog normal form — is not a security (E25 S5, F33);
    * text the ledger would refuse (`text_error/1`, E25 S4, G24).
  """
  @spec row_error(Entry.t()) :: String.t() | nil
  def row_error(%Entry{} = entry) do
    blank_security_error(entry) || text_error(entry)
  end

  defp blank_security_error(%Entry{security: %{} = security}) do
    if SecurityResolver.blank_ref?(SecurityResolver.normalize_ref(security)),
      do: gettext("security without a name and without an ISIN — row not imported")
  end

  defp blank_security_error(%Entry{}), do: nil

  @doc """
  The first piece of an entry's text the ledger would refuse, as the row's
  error message, or `nil` (E25 S4, G24). Both parsers run it on every entry
  they build, so the preview names the row instead of the apply failing on
  it; the changesets apply the same rule (`Portfolixir.Input.Text`).
  """
  @spec text_error(Entry.t()) :: String.t() | nil
  def text_error(%Entry{} = entry) do
    security = entry.security || %{}

    [
      {gettext("security name"), Map.get(security, :name), @name_rule},
      {gettext("security ISIN"), Map.get(security, :isin), @name_rule},
      {gettext("security WKN"), Map.get(security, :wkn), @name_rule},
      {gettext("security ticker"), Map.get(security, :ticker), @name_rule},
      {gettext("portfolio"), entry.pp_portfolio_name, @name_rule},
      {gettext("account"), entry.pp_account_name, @name_rule},
      {gettext("counter portfolio"), entry.pp_counter_portfolio_name, @name_rule},
      {gettext("counter account"), entry.pp_counter_account_name, @name_rule},
      {gettext("note"), entry.note, @note_rule}
    ]
    |> Enum.find_value(fn {label, value, rule} ->
      case Text.check(value, rule) do
        :ok -> nil
        {:error, refusal} -> refusal_message(label, refusal)
      end
    end)
  end

  defp refusal_message(label, :too_long),
    do: gettext("%{field} is longer than 255 characters", field: label)

  defp refusal_message(label, :control_characters),
    do: gettext("%{field} contains a control character", field: label)

  defp refusal_message(label, :invalid_encoding),
    do: gettext("%{field} is not valid UTF-8 text", field: label)

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
