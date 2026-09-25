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
  alias Portfolixir.Input.BoundedDecimal
  alias Portfolixir.Input.Text
  alias Portfolixir.Ledger.Transaction

  @default_max_rows 100_000

  @doc """
  The most rows one export may carry (#768): a bound on how much of one file
  the preview holds in memory. Configurable as `:import_max_rows`.
  """
  @spec max_rows() :: pos_integer()
  def max_rows, do: Application.get_env(:portfolixir, :import_max_rows, @default_max_rows)

  # E25 S5 (F38): the most units (fees and taxes) one transaction of a JSON
  # export may carry; each negative tax unit becomes an entry of its own.
  @max_units 64

  @doc """
  The most units one JSON transaction may carry (E25 S5, F38); a row with
  more is a row error.
  """
  @spec max_units() :: pos_integer()
  def max_units, do: @max_units

  # E25 S5 (F35): how many distinct names one preview renders a mapping row
  # for. Account and depot names are counted together, because the preview
  # offers every cash account of the file on every depot row; securities are
  # counted by their unique reference, one mapping row each.
  @default_max_names %{accounts: 100, securities: 1_000}

  @doc """
  The most distinct names one export may carry (E25 S5, F35): `accounts`
  bounds the cash-account and depot names of the file together, `securities`
  its unique security references. Past either, the file is refused as
  `{:error, :too_many_names}`: the preview renders one mapping row per name,
  and a depot row offers every cash account of the file. Configurable as
  `:import_max_names`.
  """
  @spec max_names() :: %{accounts: pos_integer(), securities: pos_integer()}
  def max_names do
    Map.merge(
      @default_max_names,
      Map.new(Application.get_env(:portfolixir, :import_max_names, []))
    )
  end

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
    parsed =
      case detect_format(body, Keyword.get(opts, :filename)) do
        :json -> JsonParser.parse(body, opts)
        :csv -> CsvParser.parse(body, opts)
        :unknown -> {:error, :unknown_format}
      end

    with {:ok, preview} <- parsed,
         :ok <- within_name_caps(preview) do
      {:ok, preview}
    end
  end

  # One pass over every entry and its companions (E25 S5, F35).
  defp within_name_caps(%Preview{entries: entries}) do
    %{accounts: max_accounts, securities: max_securities} = max_names()

    {cash, depots, securities} =
      entries
      |> Entry.flatten()
      |> Enum.reduce({MapSet.new(), MapSet.new(), MapSet.new()}, fn entry, {cash, depots, refs} ->
        {
          put_names(cash, [entry.pp_account_name, entry.pp_counter_account_name]),
          put_names(depots, [entry.pp_portfolio_name, entry.pp_counter_portfolio_name]),
          put_ref(refs, entry)
        }
      end)

    if MapSet.size(cash) + MapSet.size(depots) > max_accounts or
         MapSet.size(securities) > max_securities,
       do: {:error, :too_many_names},
       else: :ok
  end

  defp put_names(set, names) do
    Enum.reduce(names, set, fn
      nil, set -> set
      name, set -> MapSet.put(set, name)
    end)
  end

  defp put_ref(refs, %Entry{security: nil}), do: refs

  defp put_ref(refs, %Entry{} = entry),
    do: MapSet.put(refs, SecurityResolver.effective_ref(entry))

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
    blank_security_error(entry) || text_error(entry) || bounds_error(entry)
  end

  # E25 S5 (F39): every amount of the entry and of its split-off refunds,
  # rounded to its column's scale as the ledger rounds it, fits its column.
  #
  # The values the file wrote are named before the price the JSON parser
  # derives from them.
  @bounds_order [:quantity, :gross_amount, :fees, :taxes, :price]

  defp bounds_error(%Entry{} = entry) do
    columns =
      Transaction.amount_columns()
      |> Enum.filter(fn {field, _column} -> field in @bounds_order end)
      |> Enum.sort_by(fn {field, _column} -> Enum.find_index(@bounds_order, &(&1 == field)) end)

    [entry | entry.companion_entries]
    |> Enum.flat_map(fn row ->
      for {field, column} <- columns,
          value = Map.fetch!(row, field),
          match?(%Decimal{}, value),
          do: {amount_label(row, field), value, column}
    end)
    |> Enum.find_value(fn {label, value, {precision, scale} = column} ->
      unless BoundedDecimal.fits_column?(BoundedDecimal.round_to_scale(value, scale), column) do
        gettext("%{field} has more than %{digits} digits before the decimal point",
          field: label,
          digits: precision - scale
        )
      end
    end)
  end

  # A split-off refund's source row is "<row>.tax_refund.<n>".
  defp amount_label(%Entry{source_row: row}, :gross_amount) when is_binary(row),
    do: gettext("tax refund")

  defp amount_label(_row, :gross_amount), do: gettext("gross amount")
  defp amount_label(_row, :quantity), do: gettext("quantity")
  defp amount_label(_row, :price), do: gettext("price")
  defp amount_label(_row, :fees), do: gettext("fees")
  defp amount_label(_row, :taxes), do: gettext("taxes")
  defp amount_label(_row, field), do: to_string(field)

  @doc """
  The row message for a number the parser could not read or that is past
  its bound (`Portfolixir.Imports.Decimals`), naming the value as the file
  wrote it, shortened (E25 S5, F39).
  """
  @spec decimal_message(term()) :: String.t()
  def decimal_message(value) do
    shown =
      case value do
        %Decimal{} = decimal -> Decimal.to_string(decimal)
        value when is_binary(value) or is_integer(value) -> to_string(value)
        other -> inspect(other, limit: 5)
      end

    gettext("number %{value} cannot be read or is out of range",
      value: String.slice(shown, 0, 40)
    )
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
