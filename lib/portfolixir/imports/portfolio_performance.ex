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

  alias Portfolixir.Catalog.Currencies
  alias Portfolixir.Catalog.IdentifierAlias
  alias Portfolixir.Catalog.Isin
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

  # ADR-0053 §2: the kinds by the way they move money on the row's cash
  # account. A cash transfer's direction comes from its side; the kinds
  # without cash have none.
  @debit_kinds ~w(buy removal fee tax)
  @credit_kinds ~w(sell dividend interest deposit tax_refund)

  @doc """
  The way a row of `kind` moves money on its own cash account (ADR-0053 §2):
  `:debit`, `:credit`, or `nil` for a kind without cash. A cash transfer
  debits on its sending side (`:sending`, and a JSON row, which always names
  the sender in `account`) and credits on its receiving side (`:receiving`,
  #1023).
  """
  @spec direction(String.t(), :sending | :receiving | nil) :: :debit | :credit | nil
  def direction("cash_transfer", :receiving), do: :credit
  def direction("cash_transfer", _sending), do: :debit
  def direction(kind, _side) when kind in @debit_kinds, do: :debit
  def direction(kind, _side) when kind in @credit_kinds, do: :credit
  def direction(_kind, _side), do: nil

  @doc """
  The cash a row's own booking moves (ADR-0053 §5 and the amendment of
  2026-10-07, A1), given the way it moves money, the row's **cash cell** and
  the tax refund split off it into a companion (`nil` when none):

    * the cash cell is a Portfolio Performance CSV row's Gesamtpreis, a
      converter-written row's Betrag, or a JSON row's `amount`, each the
      cash the row moves, the refund inside it;
    * the refund books beside the row, so the row's own booking is credited
      the cash cell less the refund, or debited the cash cell plus it, and
      the two together move the cash cell.

  Without a refund the cash cell books as it is; without a direction or a
  cash cell there is nothing to book (`nil`).
  """
  @spec parent_cash(:debit | :credit | nil, Decimal.t() | nil, Decimal.t() | nil) ::
          Decimal.t() | nil
  def parent_cash(nil, _cash, _refund), do: nil
  def parent_cash(_direction, nil, _refund), do: nil
  def parent_cash(_direction, %Decimal{} = cash, nil), do: cash
  def parent_cash(:credit, %Decimal{} = cash, %Decimal{} = refund), do: Decimal.sub(cash, refund)
  def parent_cash(:debit, %Decimal{} = cash, %Decimal{} = refund), do: Decimal.add(cash, refund)

  @doc """
  The row message for a credit whose own booking would move 0 or less
  (ADR-0053 A5, #1118), or `nil`. Only a positive amount is importable, so
  the apply would skip such a row, its split-off refund with it, and leave a
  sale's position held; the preview names it instead, with the remedy, and
  the rest of the file previews. It fails closed, as §2 does, whether or not
  a refund was split off, and no hash changes.

  `written` names the row's figures as the file wrote them: `cell`, the
  column or field of the cash cell; `cash`, its value; `refund`, the refund
  split off (`nil` when none); and `rest`, what the booking would credit.
  """
  @spec credit_error(:debit | :credit | nil, Decimal.t() | nil, map()) :: String.t() | nil
  def credit_error(:credit, %Decimal{} = booked, written) do
    if Decimal.compare(booked, 0) != :gt, do: credit_message(written)
  end

  def credit_error(_direction, _booked, _written), do: nil

  @doc """
  The row message for a credit `credit_error/3` refuses when the stored
  history already holds the row's content hash (a live booking, or a hash a
  merge retired): the row was imported under
  an older reading, before A5 refused it (#1118). Its cash would be 0 or
  less, so the correction cannot rewrite it (how it is corrected is #1193),
  and following the refusal's remedy would book it twice; the message says
  so and points to the handbook. `written` as for `credit_error/3`.
  """
  @spec stored_credit_message(map()) :: String.t()
  def stored_credit_message(%{refund: nil} = written),
    do:
      gettext(
        "%{cell} %{cash} leaves nothing to credit — already imported, and it cannot be corrected here, as its cash would be 0 or less — do not enter it again; see “A negative tax inside a row” in the product documentation",
        cell: written.cell,
        cash: written.cash
      )

  def stored_credit_message(written),
    do:
      gettext(
        "%{cell} %{cash} less the tax refund %{refund} leaves %{rest} to credit — already imported, and it cannot be corrected here, as its cash would be 0 or less — do not enter it again; see “A negative tax inside a row” in the product documentation",
        cell: written.cell,
        cash: written.cash,
        refund: written.refund,
        rest: written.rest
      )

  @doc """
  `credit_error/3`, with what the preview keeps of a refused row: `nil`
  when the credit is booked, otherwise `{message, refused}`, where
  `refused` holds the row's would-be `entry` and the message it shows
  instead when the stored history holds that entry's content hash
  (`stored_credit_message/1`).
  """
  @spec credit_refusal(:debit | :credit | nil, Entry.t(), map()) ::
          nil | {String.t(), %{entry: Entry.t(), message: String.t()}}
  def credit_refusal(direction, %Entry{} = entry, written) do
    case credit_error(direction, entry.gross_amount, written) do
      nil -> nil
      message -> {message, %{entry: entry, message: stored_credit_message(written)}}
    end
  end

  defp credit_message(%{refund: nil} = written),
    do:
      gettext(
        "%{cell} %{cash} leaves nothing to credit — enter this booking by hand — row not imported",
        cell: written.cell,
        cash: written.cash
      )

  defp credit_message(written),
    do:
      gettext(
        "%{cell} %{cash} less the tax refund %{refund} leaves %{rest} to credit — enter this booking by hand, and the refund as a tax refund of its own — row not imported",
        cell: written.cell,
        cash: written.cash,
        refund: written.refund,
        rest: written.rest
      )

  # The text of an entry the ledger stores, each with the rule its column
  # applies (E25 S4, G24): a name is one line within its column's width, a
  # note keeps its line breaks.
  @name_rule [max: 255]
  @note_rule [multiline: true, max: Text.free_text_max()]

  @doc """
  Why a parsed entry cannot be a row of the preview, as the row's message, or
  `nil`. Both parsers run it on every entry they build, so a row the apply
  could never book is named in the preview instead:

    * a security reference that names nothing — no name, ISIN, WKN or ticker
      in catalog normal form — is not a security (E25 S5, F33);
    * an ISIN that fails the catalog's predicate (`Portfolixir.Catalog.Isin`,
      check digit included) is no ISIN (E25 S5, G23);
    * text the ledger would refuse (`text_error/1`, E25 S4, G24);
    * a booking currency or a security currency the catalog does not list
      (`Portfolixir.Catalog.Currencies.supported?/1`, #948), each with its
      own message (`currency_message/2`). An absent currency passes: the
      apply reads it as its default. The CSV parser books every row in EUR
      and writes no security currency, so it never trips this check.
  """
  @spec row_error(Entry.t()) :: String.t() | nil
  def row_error(%Entry{} = entry) do
    blank_security_error(entry) || isin_error(entry) || text_error(entry) ||
      bounds_error(entry) || currency_error(entry)
  end

  # #948: both currencies are judged by the catalog's one list, the rule the
  # security and exchange-rate changesets apply, so a code the instance could
  # never value — "EURO", or a three-letter "XEU" — never books an account or
  # a booking in it. An absent currency is `nil`; a value that is not a string
  # never reaches an entry (the JSON parser names it as its row's error).
  defp currency_error(%Entry{} = entry) do
    booking_currency_error(entry.currency_code) || security_currency_error(entry.security)
  end

  defp booking_currency_error(currency) when is_binary(currency) do
    unless Currencies.supported?(currency), do: currency_message(:booking, currency)
  end

  defp booking_currency_error(_absent), do: nil

  defp security_currency_error(%{currency: currency}) when is_binary(currency) do
    unless Currencies.supported?(currency), do: currency_message(:security, currency)
  end

  defp security_currency_error(_security), do: nil

  @doc """
  The row message for a currency the catalog does not list (#948), the
  booking's (`:booking`) or its security's (`:security`), naming the value as
  the file wrote it: a string as the parser normalised it (trimmed and
  upper-cased), a number with its digits, anything else as compact JSON. The
  value is cut at 40 characters, the cut marked "…", and then every character
  the operator could not see, or that would break the warning's one line, is
  spelled `[U+XXXX]`.
  """
  @spec currency_message(:booking | :security, term()) :: String.t()
  def currency_message(:booking, value),
    do:
      gettext("currency “%{currency}” is not supported — row not imported",
        currency: shown_value(value)
      )

  def currency_message(:security, value),
    do:
      gettext("security currency “%{currency}” is not supported — row not imported",
        currency: shown_value(value)
      )

  @shown_max 40
  @controls ~r/[\x{0}-\x{1F}\x{7F}-\x{9F}]/u

  defp shown_value(value) do
    written = written(value)

    if String.length(written) > @shown_max,
      do: escape_shown(String.slice(written, 0, @shown_max)) <> "…",
      else: escape_shown(written)
  end

  defp written(value) when is_binary(value), do: value
  defp written(value) when is_integer(value), do: Integer.to_string(value)
  defp written(%Decimal{} = value), do: decimal_text(value)

  defp written(value) do
    case Jason.encode(json_term(value)) do
      {:ok, json} -> json
      {:error, _} -> inspect(value, limit: 5, printable_limit: @shown_max)
    end
  end

  # A JSON number decodes to a `Decimal`; it is shown with its digits, as the
  # file wrote them ("1.50"), unless its exponent alone would outrun the cap.
  defp decimal_text(%Decimal{exp: exp} = value) when abs(exp) <= @shown_max,
    do: Decimal.to_string(value, :normal)

  defp decimal_text(value), do: Decimal.to_string(value, :scientific)

  defp json_term(%Decimal{} = value), do: Jason.Fragment.new(decimal_text(value))
  defp json_term(%{} = map), do: Map.new(map, fn {key, value} -> {key, json_term(value)} end)
  defp json_term(list) when is_list(list), do: Enum.map(list, &json_term/1)
  defp json_term(other), do: other

  defp escape_shown(text) do
    text
    |> Text.escape_invisible()
    |> then(&Regex.replace(@controls, &1, fn control -> spell(control) end))
  end

  defp spell(<<code_point::utf8>>),
    do: "[U+" <> (code_point |> Integer.to_string(16) |> String.pad_leading(4, "0")) <> "]"

  # E25 S5 (G23): an ISIN is checked with the catalog's one predicate, check
  # digit included; a lookalike never reaches the matching or a creation.
  defp isin_error(%Entry{security: %{} = security}) do
    case IdentifierAlias.normalize_isin(Map.get(security, :isin)) do
      nil ->
        nil

      isin ->
        unless Isin.valid?(isin),
          do:
            gettext("ISIN %{isin} is not a valid ISIN (shape or check digit) — row not imported",
              isin: inspect(isin)
            )
    end
  end

  defp isin_error(%Entry{}), do: nil

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
      # A security's name is stored without its format characters (E25 S5,
      # G23), so it is judged as stored; what that keeps, a run of variation
      # selectors, is still refused (E25 S7, G20).
      {gettext("security name"), stored_security_name(Map.get(security, :name)), @name_rule},
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
        {:error, :invisible_characters} -> invisible_message(label, value)
        {:error, refusal} -> refusal_message(label, refusal, rule)
      end
    end)
  end

  defp stored_security_name(name) when is_binary(name), do: Text.strip_format_characters(name)
  defp stored_security_name(name), do: name

  # E25 S7, G20: the row names the characters, which the operator cannot see
  # in the file either.
  defp invisible_message(label, value),
    do:
      gettext("%{field} contains invisible characters (%{characters})",
        field: label,
        characters: value |> Text.invisible_characters() |> Enum.join(", ")
      )

  defp refusal_message(label, :too_long, rule),
    do: gettext("%{field} is longer than %{count} characters", field: label, count: rule[:max])

  defp refusal_message(label, :control_characters, _rule),
    do: gettext("%{field} contains a control character", field: label)

  defp refusal_message(label, :invalid_encoding, _rule),
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
