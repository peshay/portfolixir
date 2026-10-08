defmodule Portfolixir.Imports.PortfolioPerformance.JsonParser do
  @moduledoc """
  Parses Portfolio Performance JSON export v1 (the JSON variant of the
  desktop app's "Export → All Transactions" output) into a
  `Portfolixir.Imports.Preview`.

  Input schema (top-level):

      {
        "version": 1,
        "transactions": [
          {"type": "PURCHASE"|"SALE"|...,
           "account": "<cash account name>",
           "portfolio": "<depot name>",
           "otherAccount": "<for CASH_TRANSFER>",
           "otherPortfolio": "<for SECURITY_TRANSFER>",
           "date": "2023-05-17",
           "time": "10:01",
           "currency": "EUR",
           "amount": <number>,
           "shares": <number>,
           "security": {
             "name": ..., "isin": ..., "wkn": ..., "ticker": ...,
             "currency": ...
           },
           "units": [
             {"type": "FEE"|"TAX", "amount": <number>}
           ]}
        ]
      }

  Numbers are decoded via `Jason.decode/2` with `floats: :decimals` so
  no float passes through. Unknown PP types end up in `preview.errors`
  rather than as silent `Entry` skips, and so does a row whose booking or
  security currency the catalog does not list (#948), and a credit whose own
  booking would move 0 or less (ADR-0053 A5, #1118).

  A negative TAX unit is split off into a `tax_refund` companion, and the
  row's own booking leaves it out of its `amount`, which already holds it
  (ADR-0053 A1); a purchase or sale is priced from its gross value, the
  taxes read with their sign (A2), while its content hash keeps reading the
  `amount` and the price derived before (§3, A3).
  """

  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Imports.Decimals
  alias Portfolixir.Imports.Entry
  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Imports.Preview
  alias Portfolixir.Input.BoundedDate

  @kind_map %{
    "PURCHASE" => "buy",
    "SALE" => "sell",
    "DIVIDEND" => "dividend",
    "INTEREST" => "interest",
    "DEPOSIT" => "deposit",
    "REMOVAL" => "removal",
    "FEE" => "fee",
    "TAX" => "tax",
    "TAX_REFUND" => "tax_refund",
    "CASH_TRANSFER" => "cash_transfer",
    "INBOUND_DELIVERY" => "inbound_delivery",
    "OUTBOUND_DELIVERY" => "outbound_delivery",
    "SECURITY_TRANSFER" => "security_transfer"
  }

  # Deliveries and security transfers move shares but settle no cash. PP often
  # records them with amount 0; persisting that as gross_amount 0 trips the
  # ledger's "gross_amount must be greater than 0" check (#482), so these kinds
  # carry no gross_amount.
  @no_cash_kinds ~w(inbound_delivery outbound_delivery security_transfer)

  @spec parse(binary(), keyword()) :: {:ok, Preview.t()} | {:error, term()}
  def parse(body, opts \\ []) when is_binary(body) do
    max_rows = PortfolioPerformance.max_rows()

    case Jason.decode(body, floats: :decimals) do
      {:ok, %{"version" => 1, "transactions" => txs}} when is_list(txs) ->
        rows = length(txs)

        # E25 S5 (F38): the cap counts the entries the file expands into —
        # each row plus the tax refunds it splits off — before any is built.
        cond do
          rows > max_rows -> {:error, {:too_many_rows, rows}}
          (entries = expanded_count(txs)) > max_rows -> {:error, {:too_many_entries, entries}}
          true -> {:ok, preview(txs, opts)}
        end

      # Version 1 with a transactions value that is not a list (#768).
      {:ok, %{"version" => 1}} ->
        {:error, :malformed_payload}

      {:ok, %{"version" => other}} ->
        {:error, {:unsupported_version, other}}

      {:ok, _} ->
        {:error, :malformed_payload}

      {:error, %Jason.DecodeError{} = e} ->
        {:error, {:invalid_json, Exception.message(e)}}
    end
  end

  defp expanded_count(txs) do
    Enum.reduce(txs, 0, fn tx, count -> count + 1 + refund_units(tx) end)
  end

  # The companions `sum_units/1` would split off: negative TAX units of a
  # units list within the per-row cap (a longer one is a row error).
  defp refund_units(%{"units" => units}) when is_list(units) do
    if length(units) > PortfolioPerformance.max_units(),
      do: 0,
      else: Enum.count(units, &refund_unit?/1)
  end

  defp refund_units(_tx), do: 0

  defp refund_unit?(%{"type" => "TAX"} = unit) do
    case Decimals.parse(Map.get(unit, "amount", 0)) do
      {:ok, %Decimal{} = amount} -> Decimal.negative?(amount)
      _other -> false
    end
  end

  defp refund_unit?(_unit), do: false

  defp preview(txs, opts) do
    {entries, errors, refused} =
      txs
      |> Enum.with_index(1)
      |> Enum.reduce({[], [], []}, fn {raw, row}, {acc_entries, acc_errors, acc_refused} ->
        case to_entry(raw, row) do
          {:ok, entry} ->
            {[entry | acc_entries], acc_errors, acc_refused}

          {:error, message} ->
            {acc_entries, [%{row: row, message: message} | acc_errors], acc_refused}

          # ADR-0053 A5: a refused credit keeps its would-be entry (#1118).
          {:refused, message, credit} ->
            {acc_entries, [%{row: row, message: message} | acc_errors],
             [Map.put(credit, :row, row) | acc_refused]}
        end
      end)

    %Preview{
      format: :json,
      source_filename: Keyword.get(opts, :filename),
      entries: Enum.reverse(entries),
      errors: Enum.reverse(errors),
      refused_credits: Enum.reverse(refused)
    }
  end

  defp to_entry(%{"type" => pp_type} = raw, row) do
    case Map.fetch(@kind_map, pp_type) do
      {:ok, kind} ->
        build_entry(kind, raw, row)

      :error ->
        {:error, gettext("unknown PP transaction type %{type}", type: inspect(pp_type))}
    end
  end

  defp to_entry(_other, _row), do: {:error, gettext("missing transaction type")}

  defp build_entry(kind, raw, row) do
    with {:ok, date} <- parse_date(Map.get(raw, "date")),
         {:ok, time} <- parse_time(Map.get(raw, "time")),
         {:ok, amount} <- Decimals.parse(Map.get(raw, "amount")),
         {:ok, shares} <- Decimals.parse(Map.get(raw, "shares")),
         {:ok, {fees, taxes, refund_amounts}} <- sum_units(Map.get(raw, "units", [])),
         {:ok, currency} <- parse_currency(:booking, Map.get(raw, "currency")),
         {:ok, security} <- parse_security(Map.get(raw, "security")) do
      pp_portfolio = present_string(Map.get(raw, "portfolio"))
      pp_account = present_string(Map.get(raw, "account"))

      companions =
        refund_amounts
        |> Enum.with_index(1)
        |> Enum.map(fn {refund, idx} ->
          %Entry{
            source_row: "#{row}.tax_refund.#{idx}",
            kind: "tax_refund",
            date: date,
            time: time,
            currency_code: currency,
            gross_amount: refund,
            hash_amount: refund,
            fees: Decimal.new(0),
            taxes: Decimal.new(0),
            quantity: nil,
            price: nil,
            security: security,
            pp_portfolio_name: pp_portfolio,
            pp_account_name: pp_account,
            note: "Auto-split tax refund from row #{row}"
          }
        end)

      # ADR-0053 A2: the price comes from the gross value, the taxes read with
      # their sign, as Portfolio Performance derives it; A3: the hash keeps
      # the price derived from the positive taxes alone.
      price = derive_price(kind, amount, shares, fees, signed_taxes(taxes, refund_amounts))
      old_price = derive_price(kind, amount, shares, fees, taxes)

      entry = %Entry{
        source_row: row,
        kind: kind,
        date: date,
        time: time,
        currency_code: currency,
        # ADR-0053 A1 (the amendment of 2026-10-07): PP's `amount` is the cash
        # the row moves, a negative tax unit inside it, so the row's own
        # booking leaves out the refunds split off beside it: a credit books
        # `amount` less them, a debit `amount` plus them.
        gross_amount:
          if(kind in @no_cash_kinds,
            do: nil,
            else:
              PortfolioPerformance.parent_cash(
                PortfolioPerformance.direction(kind, nil),
                amount,
                refund_total(refund_amounts)
              )
          ),
        # ADR-0053 §3 and A3: a JSON row's hash amount is its `amount`, which
        # it books too unless a refund is split off.
        hash_amount: if(kind in @no_cash_kinds, do: nil, else: amount),
        fees: fees,
        taxes: taxes,
        quantity: shares,
        price: price,
        # ADR-0053 A3: a trade with a negative tax unit keeps the price its
        # hash read before the amendment of 2026-10-07 as the hash's price
        # input. `derive_price/5` gives nil for a kind without a price.
        hash_price: if(refund_amounts != [], do: old_price),
        security: security,
        pp_portfolio_name: pp_portfolio,
        pp_account_name: pp_account,
        pp_counter_portfolio_name: present_string(Map.get(raw, "otherPortfolio")),
        pp_counter_account_name: present_string(Map.get(raw, "otherAccount")),
        note: present_string(Map.get(raw, "note")),
        companion_entries: companions
      }

      # #1044: a transfer without its other side first; then E25 S4 (G24)
      # and S5 (F33): a security that names nothing, and text the ledger would
      # refuse, are this row's error; so is a currency the catalog does not
      # list (#948); then a credit that would book 0 or less (ADR-0053 A5,
      # #1118).
      case counter_error(entry) || PortfolioPerformance.row_error(entry) do
        nil -> credit_refusal(kind, amount, refund_amounts, entry)
        message -> {:error, message}
      end
    else
      {:error, reason} when is_binary(reason) ->
        {:error, reason}

      {:error, {:invalid_decimal, value}} ->
        {:error, PortfolioPerformance.decimal_message(value)}

      {:error, {:invalid_currency, which, value}} ->
        {:error, PortfolioPerformance.currency_message(which, value)}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp parse_date(nil), do: {:error, :missing_date}

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, %Date{year: year}} when year < 1900 ->
        {:error,
         gettext(
           "implausible date %{date} (before 1900) — fix the booking in the source and re-import",
           date: value
         )}

      # The ledger's bounded date (E25 S4, F70), named here as the row's error
      # rather than failing the apply.
      {:ok, date} = ok ->
        if BoundedDate.within?(date) do
          ok
        else
          {:error,
           gettext(
             "implausible date %{date} (after %{latest}) — fix the booking in the source and re-import",
             date: value,
             latest: Date.to_iso8601(BoundedDate.latest())
           )}
        end

      {:error, _} = err ->
        err
    end
  end

  # A date that is not even a string (#768).
  defp parse_date(other), do: {:error, gettext("invalid date %{date}", date: inspect(other))}

  defp parse_time(nil), do: {:ok, nil}

  defp parse_time(value) when is_binary(value) do
    # PP exports HH:MM; pad to HH:MM:SS for Time.from_iso8601/1.
    padded =
      case String.length(value) do
        5 -> value <> ":00"
        _ -> value
      end

    case Time.from_iso8601(padded) do
      {:ok, _time} = ok -> ok
      {:error, _} -> {:ok, nil}
    end
  end

  defp parse_time(_other), do: {:ok, nil}

  # Folds the `units` array. Negative TAX units are extracted into a
  # `refunds` list — the parent entry takes `Decimal.abs/1` of every
  # value, and each negative TAX becomes a companion `tax_refund`
  # entry created in `build_entry/3`, which the parent's cash leaves out
  # (ADR-0053 A1). FEE units are always summed by absolute value (PP has no
  # "fee refund" kind).
  # A unit that is not a map, or whose amount is not a finite decimal, fails
  # the row instead of the process (#768).
  # E25 S5 (F38): a units list past the per-row cap is a row error.
  defp sum_units(units) when is_list(units) do
    if length(units) > PortfolioPerformance.max_units(),
      do: {:error, gettext("more units (fees and taxes) than one booking carries")},
      else: sum_bounded_units(units)
  end

  defp sum_units(_), do: {:ok, {Decimal.new(0), Decimal.new(0), []}}

  defp sum_bounded_units(units) do
    Enum.reduce_while(units, {:ok, {Decimal.new(0), Decimal.new(0), []}}, fn
      %{} = unit, {:ok, {fees, taxes, refunds}} ->
        case Decimals.parse(Map.get(unit, "amount", 0)) do
          {:ok, nil} ->
            {:cont, {:ok, {fees, taxes, refunds}}}

          {:ok, amount} ->
            {:cont, {:ok, fold_unit(Map.get(unit, "type"), amount, fees, taxes, refunds)}}

          {:error, _} ->
            {:halt, {:error, PortfolioPerformance.decimal_message(unit["amount"])}}
        end

      other, _acc ->
        {:halt, {:error, gettext("invalid unit %{unit}", unit: inspect(other))}}
    end)
    |> case do
      {:ok, {fees, taxes, refunds}} -> {:ok, {fees, taxes, Enum.reverse(refunds)}}
      {:error, _} = error -> error
    end
  end

  # ADR-0053 A5: a credit that would book 0 or less, named with its figures
  # as the file wrote them; the refusal keeps the row's would-be entry, so
  # the preview can tell a row already imported (#1118).
  defp credit_refusal(kind, amount, refunds, %Entry{gross_amount: booked} = entry) do
    refund = refund_total(refunds)

    written = %{
      cell: "amount",
      cash: amount && Decimal.to_string(amount, :normal),
      refund: refund && Decimal.to_string(refund, :normal),
      rest: booked && Decimal.to_string(booked, :normal)
    }

    case PortfolioPerformance.credit_refusal(
           PortfolioPerformance.direction(kind, nil),
           entry,
           written
         ) do
      nil -> {:ok, entry}
      {message, refused} -> {:refused, message, refused}
    end
  end

  # The row's taxes with their sign: the positive TAX units less the
  # negative ones split off as refunds. Without a refund, the taxes as they
  # are.
  defp signed_taxes(taxes, refunds), do: Enum.reduce(refunds, taxes, &Decimal.sub(&2, &1))

  # The refunds split off one row, together; `nil` when none is.
  defp refund_total([]), do: nil
  defp refund_total(refunds), do: Enum.reduce(refunds, &Decimal.add/2)

  defp fold_unit(type, amount, fees, taxes, refunds) do
    abs_amount = Decimal.abs(amount)
    negative? = Decimal.compare(amount, 0) == :lt

    case type do
      "FEE" -> {Decimal.add(fees, abs_amount), taxes, refunds}
      "TAX" when negative? -> {fees, taxes, [abs_amount | refunds]}
      "TAX" -> {fees, Decimal.add(taxes, abs_amount), refunds}
      _ -> {fees, taxes, refunds}
    end
  end

  defp parse_security(%{} = sec) do
    with {:ok, currency} <- parse_currency(:security, Map.get(sec, "currency")) do
      {:ok,
       %{
         name: present_string(Map.get(sec, "name")) |> normalize_letter_spacing(),
         isin: present_string(Map.get(sec, "isin")) |> normalize_isin(),
         wkn: present_string(Map.get(sec, "wkn")),
         ticker: present_string(Map.get(sec, "ticker")),
         currency: currency
       }}
    end
  end

  # Absent, or not a map at all (#768): no security on the row.
  defp parse_security(_other), do: {:ok, nil}

  # #1044: a transfer moves money or shares between two accounts or depots, so
  # one without its other side has nothing to book against; the apply would
  # otherwise refuse the whole file on the missing account.
  defp counter_error(%Entry{kind: "cash_transfer", pp_counter_account_name: nil}),
    do: gettext("transfer without a counter account — row not imported")

  defp counter_error(%Entry{kind: "security_transfer", pp_counter_portfolio_name: nil}),
    do: gettext("transfer without a counter account — row not imported")

  defp counter_error(%Entry{}), do: nil

  # PP sometimes exports letter-spaced names: "I b e r d r o l a S . A . A c c i o n e s".
  # When the strict majority of whitespace-separated tokens are single characters
  # (at least 4 tokens to avoid collapsing short abbreviations like "A G"),
  # collapse them by joining without spaces so heuristics can match legal suffixes.
  defp normalize_letter_spacing(nil), do: nil

  defp normalize_letter_spacing(name) when is_binary(name) do
    tokens = String.split(name, ~r/\s+/, trim: true)
    single_count = Enum.count(tokens, fn t -> String.length(t) == 1 end)

    if length(tokens) >= 4 and single_count * 2 > length(tokens) do
      Enum.join(tokens, "")
    else
      name
    end
  end

  # #948: a code is trimmed and upper-cased, and judged against the catalog's
  # list by `PortfolioPerformance.row_error/1`. An absent currency (no key,
  # `null`, or blank) is `nil`, which the apply reads as its default. A value
  # that is present but not a string is the row's error here, named as the
  # file wrote it, as a number the parser cannot read is.
  defp parse_currency(_which, value) when is_binary(value) do
    case value |> String.trim() |> String.upcase() do
      "" -> {:ok, nil}
      code -> {:ok, code}
    end
  end

  defp parse_currency(_which, nil), do: {:ok, nil}
  defp parse_currency(which, other), do: {:error, {:invalid_currency, which, other}}

  defp normalize_isin(nil), do: nil

  defp normalize_isin(value) when is_binary(value) do
    value |> String.trim() |> String.upcase()
  end

  defp present_string(nil), do: nil

  defp present_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present_string(_), do: nil

  # For buy/sell PP gives both `amount` (the cash paid or received,
  # fees and taxes included) and `shares`. The per-share `price` is
  # derived from the gross value, as PP derives it
  # (`PortfolioTransaction.getGrossValueAmount`): the amount net of fees
  # and taxes for buys, with them added back for sells, the taxes read
  # with their sign (ADR-0053 A2), so the ledger keeps a normalised
  # per-unit cost basis matching what PP shows in its trade table, and a
  # sale's proceeds equal the cash its own booking moves.
  defp derive_price("buy", amount, %Decimal{} = shares, fees, taxes)
       when not is_nil(amount) do
    if Decimal.equal?(shares, 0) do
      nil
    else
      amount
      |> Decimal.sub(fees || Decimal.new(0))
      |> Decimal.sub(taxes || Decimal.new(0))
      |> Decimal.div(shares)
    end
  end

  defp derive_price("sell", amount, %Decimal{} = shares, fees, taxes)
       when not is_nil(amount) do
    if Decimal.equal?(shares, 0) do
      nil
    else
      amount
      |> Decimal.add(fees || Decimal.new(0))
      |> Decimal.add(taxes || Decimal.new(0))
      |> Decimal.div(shares)
    end
  end

  defp derive_price(_kind, _amount, _shares, _fees, _taxes), do: nil
end
