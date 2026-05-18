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
  rather than as silent `Entry` skips.
  """

  alias Portfolixir.Imports.Decimals
  alias Portfolixir.Imports.Entry
  alias Portfolixir.Imports.Preview

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

  @spec parse(binary(), keyword()) :: {:ok, Preview.t()} | {:error, term()}
  def parse(body, opts \\ []) when is_binary(body) do
    case Jason.decode(body, floats: :decimals) do
      {:ok, %{"version" => 1, "transactions" => txs}} when is_list(txs) ->
        {entries, errors} =
          txs
          |> Enum.with_index(1)
          |> Enum.reduce({[], []}, fn {raw, row}, {acc_entries, acc_errors} ->
            case to_entry(raw, row) do
              {:ok, entry} -> {[entry | acc_entries], acc_errors}
              {:error, message} -> {acc_entries, [%{row: row, message: message} | acc_errors]}
            end
          end)

        {:ok,
         %Preview{
           format: :json,
           source_filename: Keyword.get(opts, :filename),
           entries: Enum.reverse(entries),
           errors: Enum.reverse(errors)
         }}

      {:ok, %{"version" => other}} ->
        {:error, {:unsupported_version, other}}

      {:ok, _} ->
        {:error, :malformed_payload}

      {:error, %Jason.DecodeError{} = e} ->
        {:error, {:invalid_json, Exception.message(e)}}
    end
  end

  defp to_entry(%{"type" => pp_type} = raw, row) do
    case Map.fetch(@kind_map, pp_type) do
      {:ok, kind} ->
        build_entry(kind, raw, row)

      :error ->
        {:error, "unknown PP transaction type #{inspect(pp_type)}"}
    end
  end

  defp to_entry(_other, _row), do: {:error, "missing transaction type"}

  defp build_entry(kind, raw, row) do
    with {:ok, date} <- parse_date(Map.get(raw, "date")),
         {:ok, time} <- parse_time(Map.get(raw, "time")),
         {:ok, amount} <- Decimals.parse(Map.get(raw, "amount")),
         {:ok, shares} <- Decimals.parse(Map.get(raw, "shares")),
         {fees, taxes, refund_amounts} <- sum_units(Map.get(raw, "units", [])) do
      currency = normalize_currency(Map.get(raw, "currency"))
      security = parse_security(Map.get(raw, "security"))
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

      entry = %Entry{
        source_row: row,
        kind: kind,
        date: date,
        time: time,
        currency_code: currency,
        gross_amount: amount,
        fees: fees,
        taxes: taxes,
        quantity: shares,
        price: derive_price(kind, amount, shares, fees, taxes),
        security: security,
        pp_portfolio_name: pp_portfolio,
        pp_account_name: pp_account,
        pp_counter_portfolio_name: present_string(Map.get(raw, "otherPortfolio")),
        pp_counter_account_name: present_string(Map.get(raw, "otherAccount")),
        note: present_string(Map.get(raw, "note")),
        companion_entries: companions
      }

      {:ok, entry}
    else
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp parse_date(nil), do: {:error, :missing_date}

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, _date} = ok -> ok
      {:error, _} = err -> err
    end
  end

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

  # Folds the `units` array. Negative TAX units are extracted into a
  # `refunds` list — the parent entry takes `Decimal.abs/1` of every
  # value, and each negative TAX becomes a companion `tax_refund`
  # entry created in `build_entry/3`. FEE units are always summed by
  # absolute value (PP has no "fee refund" kind).
  defp sum_units(units) when is_list(units) do
    Enum.reduce(units, {Decimal.new(0), Decimal.new(0), []}, fn unit, {fees, taxes, refunds} ->
      {:ok, amount} = Decimals.parse(Map.get(unit, "amount", 0))
      abs_amount = Decimal.abs(amount)
      negative? = Decimal.compare(amount, 0) == :lt

      case Map.get(unit, "type") do
        "FEE" ->
          {Decimal.add(fees, abs_amount), taxes, refunds}

        "TAX" when negative? ->
          {fees, taxes, [abs_amount | refunds]}

        "TAX" ->
          {fees, Decimal.add(taxes, abs_amount), refunds}

        _ ->
          {fees, taxes, refunds}
      end
    end)
    |> then(fn {fees, taxes, refunds} -> {fees, taxes, Enum.reverse(refunds)} end)
  end

  defp sum_units(_), do: {Decimal.new(0), Decimal.new(0), []}

  defp parse_security(nil), do: nil

  defp parse_security(%{} = sec) do
    %{
      name: present_string(Map.get(sec, "name")),
      isin: present_string(Map.get(sec, "isin")) |> normalize_isin(),
      wkn: present_string(Map.get(sec, "wkn")),
      ticker: present_string(Map.get(sec, "ticker")),
      currency: normalize_currency(Map.get(sec, "currency"))
    }
  end

  defp normalize_currency(value) when is_binary(value) do
    value |> String.trim() |> String.upcase()
  end

  defp normalize_currency(_), do: nil

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

  # For buy/sell PP gives both `amount` (gross paid/received including
  # fees+taxes) and `shares`. We persist `gross_amount` as PP's
  # amount; the per-share `price` is derived (net of fees/taxes for
  # buys, adding them back for sells) so the ledger keeps a normalised
  # per-unit cost basis matching what PP shows in its trade table.
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
