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
  - **Betrag is PP's gross value, Gesamtpreis the cash** (ADR-0053).
    Portfolio Performance writes Kurs as the gross price per share, Betrag
    as the gross value before fees and taxes, Gebühren and Steuern as the
    row's fee and tax units, and Gesamtpreis as the cash that moved, always.
    A row with a Gesamtpreis books it as its `gross_amount` (§1); a row
    without one, as a converter writes it, books its Betrag. A negative
    Steuern split off as a refund is taken out of a Gesamtpreis-booking
    parent, so the row's bookings still move its Gesamtpreis (§5). The
    content hash keeps reading the Betrag (`hash_amount`, §3). The kinds
    without cash ignore every money cell.
  - The CSV uses `Konto`/`Gegenkonto` to disambiguate cash-source vs.
    cash-target accounts. For trades, `Konto` is the depot (PP
    "portfolio") and `Gegenkonto` is the cash account. For cash-only
    entries, `Konto` is the cash account. The parser maps fields based
    on the German type label.
  - Transfers (#1023), as Portfolio Performance writes them: `Konto` is the
    row's own account or depot and `Gegenkonto` the other side. "Umbuchung
    (Ausgang)" is the sending side and "Umbuchung (Eingang)" the receiving
    side, for a cash account and a depot alike; a row naming a security is a
    depot's. PP's "All transactions" export writes the sending side only; an
    account's or a security's own list writes the receiving side too, so a
    file assembled from such lists can carry both. Each transfer is booked
    once, from the sending row, and the receiving row it pairs with is a row
    warning naming that row.
  """

  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Imports.Decimals
  alias Portfolixir.Imports.Entry
  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Imports.Preview
  alias Portfolixir.Input.BoundedDate

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
    "Einlieferung" => "inbound_delivery",
    "Auslieferung" => "outbound_delivery",
    "Umbuchung (Wertpapier)" => "security_transfer"
  }

  # #1023: Portfolio Performance labels a cash account's and a depot's
  # transfer alike (`labels_de.properties`: account.TRANSFER_OUT and
  # portfolio.TRANSFER_OUT are both "Umbuchung (Ausgang)"), so the side comes
  # from the label and the kind from whether the row names a security.
  @transfer_sides %{
    "Umbuchung (Ausgang)" => :sending,
    "Umbuchung (Eingang)" => :receiving
  }

  # "Umbuchung (Wertpapier)" above is not a PP label: it is the one
  # Portfolixir's converter prompt writes, always a security transfer read
  # like PP's sending row (Konto the sender), so a PP receiving row of the
  # same transfer pairs with it as with PP's own.
  @sending_kind_labels ["Umbuchung (Wertpapier)"]

  # Deliveries and security transfers move shares but settle no cash; they carry
  # no gross_amount so a 0/blank amount does not trip the ledger's
  # "gross_amount must be greater than 0" check (#482).
  @no_cash_kinds ~w(inbound_delivery outbound_delivery security_transfer)

  @spec parse(binary(), keyword()) :: {:ok, Preview.t()} | {:error, term()}
  def parse(body, opts \\ []) when is_binary(body) do
    # A UTF-8 byte-order mark ahead of "Datum" is not part of the header.
    body = String.replace_prefix(body, "\uFEFF", "")

    case __MODULE__.Parser.parse_string(body, skip_headers: false) do
      [] ->
        {:error, :empty_csv}

      [header_row | data_rows] ->
        with :ok <- validate_header(header_row),
             :ok <- validate_row_count(data_rows),
             :ok <- validate_entry_count(header_row, data_rows) do
          {tagged, errors} =
            data_rows
            |> Enum.with_index(1)
            |> Enum.reduce({[], []}, fn {raw, row}, {acc_entries, acc_errors} ->
              case to_entry(header_row, raw, row) do
                {:ok, entry, side} ->
                  {[{entry, side} | acc_entries], acc_errors}

                {:error, message} ->
                  {acc_entries, [%{row: row, message: message} | acc_errors]}
              end
            end)

          {entries, paired} = pair_transfer_sides(Enum.reverse(tagged))

          {:ok,
           %Preview{
             format: :csv,
             source_filename: Keyword.get(opts, :filename),
             entries: entries,
             errors: Enum.sort_by(Enum.reverse(errors) ++ paired, & &1.row)
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

  # E25 S5 (F38): the cap counts the entries the file expands into — each
  # row plus the tax refund a negative `Steuern` cell splits off — before any
  # is built. A header naming a column twice is read as `to_entry/3` reads it,
  # the last cell winning, so the count and the rows agree.
  defp validate_entry_count(header_row, rows) do
    max = PortfolioPerformance.max_rows()

    taxes_at =
      length(header_row) - 1 - Enum.find_index(Enum.reverse(header_row), &(&1 == "Steuern"))

    count =
      Enum.reduce(rows, 0, fn row, count ->
        count + 1 + refund_cell(Enum.at(row, taxes_at))
      end)

    if count > max, do: {:error, {:too_many_entries, count}}, else: :ok
  end

  defp refund_cell(cell) do
    case Decimals.parse_de(cell) do
      {:ok, %Decimal{} = taxes} -> if Decimal.negative?(taxes), do: 1, else: 0
      _other -> 0
    end
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

    case kind(pp_type, cells) do
      {:ok, kind, side} ->
        with {:ok, entry} <- build_entry(kind, side, cells, source_row), do: {:ok, entry, side}

      :error ->
        {:error, gettext("unknown PP CSV type %{type}", type: inspect(pp_type))}
    end
  end

  defp kind(pp_type, cells) do
    case Map.fetch(@transfer_sides, pp_type) do
      {:ok, side} ->
        if present_string(Map.get(cells, "Wertpapier")),
          do: {:ok, "security_transfer", side},
          else: {:ok, "cash_transfer", side}

      :error ->
        side = if pp_type in @sending_kind_labels, do: :sending

        with {:ok, kind} <- Map.fetch(@kind_map, pp_type), do: {:ok, kind, side}
    end
  end

  # #1023: both sides of one transfer in one file. A receiving row, its
  # direction turned, equals the sending row in every field the ledger books,
  # so it pairs one to one with such a row and is left out, named as a row
  # warning with the row it was booked from. Different transfers between the
  # same accounts differ in a booked field and never pair.
  defp pair_transfer_sides(tagged) do
    sending =
      tagged
      |> Enum.filter(fn {_entry, side} -> side == :sending end)
      |> Enum.group_by(fn {entry, _} -> transfer_key(entry) end, fn {entry, _} ->
        entry.source_row
      end)

    {kept, paired, _sending} =
      Enum.reduce(tagged, {[], [], sending}, fn
        {entry, :receiving}, {kept, paired, sending} ->
          key = transfer_key(entry)

          case Map.get(sending, key, []) do
            [booked_row | rest] ->
              message =
                gettext(
                  "receiving side of the transfer in row %{row} — booked once, from that row",
                  row: booked_row
                )

              {kept, [%{row: entry.source_row, message: message} | paired],
               Map.put(sending, key, rest)}

            [] ->
              {[entry | kept], paired, sending}
          end

        {entry, _side}, {kept, paired, sending} ->
          {[entry | kept], paired, sending}
      end)

    {Enum.reverse(kept), Enum.reverse(paired)}
  end

  # ADR-0053: the two sides compare on the file's Betrag, as the content hash
  # does. Each books its own Gesamtpreis, Betrag + U on the sending row and
  # Betrag − U on the receiving one, so the booked cash of one transfer's
  # two sides differs whenever it carries units.
  defp transfer_key(%Entry{} = entry) do
    entry
    |> Map.put(:gross_amount, entry.hash_amount || entry.gross_amount)
    |> Map.take([
      :kind,
      :date,
      :time,
      :security,
      :quantity,
      :price,
      :gross_amount,
      :fees,
      :taxes,
      :pp_portfolio_name,
      :pp_account_name,
      :pp_counter_portfolio_name,
      :pp_counter_account_name
    ])
    |> Map.new(fn
      {field, %Decimal{} = value} -> {field, Decimal.normalize(value)}
      pair -> pair
    end)
  end

  defp build_entry(kind, side, cells, source_row) do
    with {:ok, date_time} <- parse_datetime(Map.get(cells, "Datum")),
         {:ok, quantity} <- Decimals.parse_de(Map.get(cells, "Stück")),
         {:ok, price} <- Decimals.parse_de(Map.get(cells, "Kurs")),
         {:ok, gross} <- Decimals.parse_de(Map.get(cells, "Betrag")),
         {:ok, total} <- gesamtpreis(kind, cells),
         {:ok, raw_fees} <- Decimals.parse_de(Map.get(cells, "Gebühren")),
         {:ok, raw_taxes} <- Decimals.parse_de(Map.get(cells, "Steuern")) do
      {date, time} = date_time
      security_name = present_string(Map.get(cells, "Wertpapier"))

      {konto, gegenkonto} =
        own_and_other(
          side,
          present_string(Map.get(cells, "Konto")),
          present_string(Map.get(cells, "Gegenkonto"))
        )

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
                hash_amount: refund_amount,
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
        gross_amount: booked_cash(direction(kind, side), gross, total, tax_refund),
        # ADR-0053 §3: the content hash reads the file's Betrag.
        hash_amount: if(kind in @no_cash_kinds, do: nil, else: gross),
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

      # E25 S4 (G24) and S5 (F33): a security that names nothing, and text
      # the ledger would refuse, are this row's error; then a Gesamtpreis
      # that contradicts the Betrag (ADR-0053 §2), so a value no column
      # holds is named first.
      readings = %{betrag: gross, total: total, fees: raw_fees, taxes: raw_taxes}

      case PortfolioPerformance.row_error(entry) ||
             reading_error(direction(kind, side), readings, cells) do
        nil -> {:ok, entry}
        message -> {:error, message}
      end
    else
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, {:invalid_decimal, value}} -> {:error, PortfolioPerformance.decimal_message(value)}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  # ADR-0053 §1: the kinds without cash ignore every money cell, the
  # Gesamtpreis included, as they did before it was read.
  defp gesamtpreis(kind, _cells) when kind in @no_cash_kinds, do: {:ok, nil}
  defp gesamtpreis(_kind, cells), do: Decimals.parse_de(Map.get(cells, "Gesamtpreis"))

  # ADR-0053 §2: the way a row's kind moves money on its cash account. A cash
  # transfer's comes from its label (#1023): the sending row debits, the
  # receiving row credits. The kinds without cash have none.
  @debit_kinds ~w(buy removal fee tax)
  @credit_kinds ~w(sell dividend interest deposit tax_refund)

  defp direction("cash_transfer", :receiving), do: :credit
  defp direction("cash_transfer", _sending), do: :debit
  defp direction(kind, _side) when kind in @debit_kinds, do: :debit
  defp direction(kind, _side) when kind in @credit_kinds, do: :credit
  defp direction(_kind, _side), do: nil

  # ADR-0053 §1 and §5: the cash a row books. A row with a Gesamtpreis books
  # it, the cash Portfolio Performance writes; a row without one books its
  # Betrag, as a converter writes it. A refund split off a Gesamtpreis row is
  # booked beside it, so the parent books the rest and the two together move
  # the Gesamtpreis: a credit's parent is credited G − r, a debit's parent is
  # debited G + r.
  defp booked_cash(nil, _betrag, _total, _refund), do: nil
  defp booked_cash(_direction, betrag, nil, _refund), do: betrag
  defp booked_cash(:credit, _betrag, total, refund), do: Decimal.sub(total, refund || 0)
  defp booked_cash(:debit, _betrag, total, refund), do: Decimal.add(total, refund || 0)

  # ADR-0053 §2: a row carrying both readings books only when they agree to
  # the cent, both sides rounded to two places. U is Gebühren as booked (its
  # magnitude) plus Steuern as written, a negative Steuern with its sign: a
  # debit's Gesamtpreis is Betrag + U, a credit's Betrag − U, as Portfolio
  # Performance computes its gross value. A row that disagrees is
  # refused with the cells as the file wrote them; the import does not guess
  # which one is wrong. A row missing either reading, and a kind without
  # cash, is not checked.
  defp reading_error(nil, _readings, _cells), do: nil
  defp reading_error(_direction, %{betrag: nil}, _cells), do: nil
  defp reading_error(_direction, %{total: nil}, _cells), do: nil

  defp reading_error(direction, %{betrag: betrag, total: total} = readings, cells) do
    units = Decimal.add(Decimal.abs(readings.fees || Decimal.new(0)), readings.taxes || 0)

    expected =
      case direction do
        :debit -> Decimal.add(betrag, units)
        :credit -> Decimal.sub(betrag, units)
      end

    unless Decimal.equal?(Decimal.round(expected, 2), Decimal.round(total, 2)),
      do: reading_message(readings, cells)
  end

  defp reading_message(readings, cells) do
    written = fn column -> cells |> Map.get(column, "") |> String.trim() end
    total = written.("Gesamtpreis")
    amount = written.("Betrag")

    case {readings.fees, readings.taxes} do
      {nil, nil} ->
        gettext("Gesamtpreis %{total} does not match Betrag %{amount} — row not imported",
          total: total,
          amount: amount
        )

      {_fees, nil} ->
        gettext(
          "Gesamtpreis %{total} does not match Betrag %{amount} and Gebühren %{fees} — row not imported",
          total: total,
          amount: amount,
          fees: written.("Gebühren")
        )

      {nil, _taxes} ->
        gettext(
          "Gesamtpreis %{total} does not match Betrag %{amount} and Steuern %{taxes} — row not imported",
          total: total,
          amount: amount,
          taxes: written.("Steuern")
        )

      {_fees, _taxes} ->
        gettext(
          "Gesamtpreis %{total} does not match Betrag %{amount}, Gebühren %{fees} and Steuern %{taxes} — row not imported",
          total: total,
          amount: amount,
          fees: written.("Gebühren"),
          taxes: written.("Steuern")
        )
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

      # The ledger's bounded date (E25 S4, F70), named here as the row's error
      # rather than failing the apply.
      {:ok, date} ->
        if BoundedDate.within?(date),
          do: {:ok, date},
          else: {:error, too_late(String.trim(value))}

      other ->
        other
    end
  end

  defp too_late(value) do
    gettext(
      "implausible date %{date} (after %{latest}) — fix the booking in the source and re-import",
      date: value,
      latest: Date.to_iso8601(BoundedDate.latest())
    )
  end

  # A receiving row names itself in `Konto` and the sender in `Gegenkonto`:
  # turned, it reads as the sending row does (#1023).
  defp own_and_other(:receiving, konto, gegenkonto), do: {gegenkonto, konto}
  defp own_and_other(_side, konto, gegenkonto), do: {konto, gegenkonto}

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
