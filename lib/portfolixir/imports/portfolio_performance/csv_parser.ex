defmodule Portfolixir.Imports.PortfolioPerformance.CsvParser do
  @moduledoc """
  Parses Portfolio Performance CSV export (semicolon-separated, German
  locale) into a `Portfolixir.Imports.Preview`.

  Expected columns (PP "All transactions" export, German):

      Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;
      Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle

  Important caveats relative to the JSON variant:

  - The CSV only exposes a free-form security `name`. No ISIN, WKN or
    ticker is exported, so security matching downstream falls back to
    name+currency comparison. The parser emits a per-entry warning for
    every row carrying a security.
  - Numbers use German formatting (`23.685,40`). Parsing goes through
    `Portfolixir.Imports.Decimals.parse_de/1` to keep the digits
    exact — no float round-trip.
  - The CSV uses `Konto`/`Gegenkonto` to disambiguate cash-source vs.
    cash-target accounts. For trades, `Konto` is the depot (PP
    "portfolio") and `Gegenkonto` is the cash account. For cash-only
    entries, `Konto` is the cash account. The parser maps fields based
    on the German type label.
  """

  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Imports.Decimals
  alias Portfolixir.Imports.Entry
  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Imports.Preview

  NimbleCSV.define(__MODULE__.Parser, separator: ";", escape: "\"")

  @kind_map %{
    "Kauf" => "buy",
    "Verkauf" => "sell",
    "Dividende" => "dividend",
    "Zinsen" => "interest",
    "Einlage" => "deposit",
    "Entnahme" => "removal",
    "Gebühren" => "fee",
    "Steuern" => "tax",
    "Steuerrückerstattung" => "tax_refund",
    "Umbuchung (Ausgang)" => "cash_transfer",
    "Umbuchung (Eingang)" => "cash_transfer",
    "Einlieferung" => "inbound_delivery",
    "Auslieferung" => "outbound_delivery",
    "Umbuchung (Wertpapier)" => "security_transfer"
  }

  # Deliveries and security transfers move shares but settle no cash; they carry
  # no gross_amount so a 0/blank amount does not trip the ledger's
  # "gross_amount must be greater than 0" check (#482).
  @no_cash_kinds ~w(inbound_delivery outbound_delivery security_transfer)

  @spec parse(binary(), keyword()) :: {:ok, Preview.t()} | {:error, term()}
  def parse(body, opts \\ []) when is_binary(body) do
    case __MODULE__.Parser.parse_string(body, skip_headers: false) do
      [] ->
        {:error, :empty_csv}

      [header_row | data_rows] ->
        with :ok <- validate_header(header_row),
             :ok <- validate_row_count(data_rows) do
          {entries, errors} =
            data_rows
            |> Enum.with_index(1)
            |> Enum.reduce({[], []}, fn {raw, row}, {acc_entries, acc_errors} ->
              case to_entry(header_row, raw, row) do
                {:ok, entry} ->
                  {[entry | acc_entries], acc_errors}

                {:error, message} ->
                  {acc_entries, [%{row: row, message: message} | acc_errors]}
              end
            end)

          {:ok,
           %Preview{
             format: :csv,
             source_filename: Keyword.get(opts, :filename),
             entries: Enum.reverse(entries),
             errors: Enum.reverse(errors)
           }}
        end
    end
  rescue
    e in NimbleCSV.ParseError -> {:error, {:invalid_csv, Exception.message(e)}}
  end

  @required_columns ~w(Datum Typ Wertpapier Stück Kurs Betrag Gebühren Steuern Konto)

  # #768: a bound on how much of one file the preview holds in memory.
  defp validate_row_count(rows) do
    max = PortfolioPerformance.max_rows()
    count = length(rows)
    if count > max, do: {:error, {:too_many_rows, count}}, else: :ok
  end

  defp validate_header(header_row) do
    missing = @required_columns -- header_row

    if missing == [] do
      :ok
    else
      {:error, {:missing_columns, missing}}
    end
  end

  defp to_entry(header, row, source_row) do
    cells = Enum.zip(header, row) |> Map.new()
    pp_type = Map.get(cells, "Typ", "") |> String.trim()

    case Map.fetch(@kind_map, pp_type) do
      {:ok, kind} ->
        build_entry(kind, cells, source_row)

      :error ->
        {:error, gettext("unknown PP CSV type %{type}", type: inspect(pp_type))}
    end
  end

  defp build_entry(kind, cells, source_row) do
    with {:ok, date_time} <- parse_datetime(Map.get(cells, "Datum")),
         {:ok, quantity} <- Decimals.parse_de(Map.get(cells, "Stück")),
         {:ok, price} <- Decimals.parse_de(Map.get(cells, "Kurs")),
         {:ok, gross} <- Decimals.parse_de(Map.get(cells, "Betrag")),
         {:ok, raw_fees} <- Decimals.parse_de(Map.get(cells, "Gebühren")),
         {:ok, raw_taxes} <- Decimals.parse_de(Map.get(cells, "Steuern")) do
      {date, time} = date_time
      security_name = present_string(Map.get(cells, "Wertpapier"))
      konto = present_string(Map.get(cells, "Konto"))
      gegenkonto = present_string(Map.get(cells, "Gegenkonto"))

      {pp_portfolio, pp_account, pp_counter_portfolio, pp_counter_account} =
        map_accounts(kind, konto, gegenkonto)

      security =
        if security_name do
          %{name: security_name, isin: nil, wkn: nil, ticker: nil, currency: nil}
        end

      warnings = if security_name, do: ["csv-without-isin"], else: []

      {fees, taxes, tax_refund} = normalize_fees_taxes(raw_fees, raw_taxes)

      companions =
        case tax_refund do
          nil ->
            []

          refund_amount ->
            [
              %Entry{
                source_row: "#{source_row}.tax_refund.1",
                kind: "tax_refund",
                date: date,
                time: time,
                currency_code: "EUR",
                gross_amount: refund_amount,
                fees: Decimal.new(0),
                taxes: Decimal.new(0),
                quantity: nil,
                price: nil,
                security: security,
                pp_portfolio_name: pp_portfolio,
                pp_account_name: pp_account,
                note: "Auto-split tax refund from row #{source_row}"
              }
            ]
        end

      entry = %Entry{
        source_row: source_row,
        kind: kind,
        date: date,
        time: time,
        currency_code: "EUR",
        gross_amount: if(kind in @no_cash_kinds, do: nil, else: gross),
        fees: fees,
        taxes: taxes,
        quantity: quantity,
        price: price,
        security: security,
        pp_portfolio_name: pp_portfolio,
        pp_account_name: pp_account,
        pp_counter_portfolio_name: pp_counter_portfolio,
        pp_counter_account_name: pp_counter_account,
        note: present_string(Map.get(cells, "Notiz")),
        warnings: warnings,
        companion_entries: companions
      }

      {:ok, entry}
    else
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  # PP CSV exports a single signed value per fee/tax column. Mirror the
  # JSON-parser semantics: abs() the magnitude into the parent entry,
  # emit a companion `tax_refund` for any negative tax amount.
  defp normalize_fees_taxes(raw_fees, raw_taxes) do
    fees = raw_fees |> normalize_decimal() |> Decimal.abs()
    taxes_raw = normalize_decimal(raw_taxes)

    if Decimal.compare(taxes_raw, 0) == :lt do
      {fees, Decimal.new(0), Decimal.abs(taxes_raw)}
    else
      {fees, taxes_raw, nil}
    end
  end

  defp normalize_decimal(nil), do: Decimal.new(0)
  defp normalize_decimal(%Decimal{} = d), do: d

  # PP CSV writes "2026-04-29 13:00:00". For purely cash-only rows the
  # time is "00:00:00"; we keep it nil there.
  defp parse_datetime(nil), do: {:error, :missing_date}

  defp parse_datetime(value) when is_binary(value) do
    case String.split(value, " ", parts: 2) do
      [date_part] ->
        with {:ok, date} <- parse_plausible_date(date_part) do
          {:ok, {date, nil}}
        end

      [date_part, time_part] ->
        with {:ok, date} <- parse_plausible_date(date_part) do
          time =
            case Time.from_iso8601(String.trim(time_part)) do
              {:ok, %Time{hour: 0, minute: 0, second: 0}} -> nil
              {:ok, t} -> t
              {:error, _} -> nil
            end

          {:ok, {date, time}}
        end
    end
  end

  defp parse_plausible_date(value) do
    case Date.from_iso8601(String.trim(value)) do
      {:ok, %Date{year: year}} when year < 1900 ->
        {:error,
         gettext(
           "implausible date %{date} (before 1900) — fix the booking in the source and re-import",
           date: String.trim(value)
         )}

      other ->
        other
    end
  end

  # For trades (Kauf/Verkauf) the PP CSV uses Konto=depot,
  # Gegenkonto=cash. For cash-only entries Konto=cash. For
  # cash_transfer Konto=source-cash, Gegenkonto=target-cash. For
  # security_transfer Konto=source-depot, Gegenkonto=target-depot.
  defp map_accounts(kind, konto, gegenkonto) when kind in ["buy", "sell"] do
    {konto, gegenkonto, nil, nil}
  end

  defp map_accounts("cash_transfer", konto, gegenkonto) do
    {nil, konto, nil, gegenkonto}
  end

  defp map_accounts("security_transfer", konto, gegenkonto) do
    {konto, nil, gegenkonto, nil}
  end

  defp map_accounts(kind, konto, _gegenkonto)
       when kind in [
              "dividend",
              "interest",
              "deposit",
              "removal",
              "fee",
              "tax",
              "tax_refund"
            ] do
    {nil, konto, nil, nil}
  end

  defp map_accounts(kind, konto, _gegenkonto)
       when kind in ["inbound_delivery", "outbound_delivery"] do
    {konto, nil, nil, nil}
  end

  defp map_accounts(_kind, konto, gegenkonto), do: {konto, gegenkonto, nil, nil}

  defp present_string(nil), do: nil

  defp present_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present_string(_), do: nil
end
