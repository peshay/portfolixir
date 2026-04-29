defmodule Portfolixir.Catalog.SecurityCsv do
  @moduledoc "CSV helpers for security master data."

  alias Portfolixir.Catalog.Security

  @header [
    "name",
    "symbol",
    "currency_code",
    "active",
    "isin",
    "wkn",
    "provider_symbol",
    "exchange_code",
    "notes"
  ]

  @required_headers ["name", "symbol", "currency_code"]

  def render_csv(securities) when is_list(securities) do
    [@header | Enum.map(securities, &security_row/1)]
    |> Enum.map(&encode_csv_row/1)
    |> Enum.join("\n")
  end

  def preview_csv_rows(raw_csv_text, opts \\ [])

  def preview_csv_rows(raw_csv_text, opts) when is_binary(raw_csv_text) do
    valid_currency_codes = MapSet.new(opts[:valid_currency_codes] || [])

    raw_csv_text
    |> String.trim()
    |> parse_csv_rows()
    |> parse_preview_headers_and_rows(valid_currency_codes)
  end

  defp security_row(%Security{} = security) do
    [
      security.name || "",
      security.symbol || "",
      security.currency_code || "",
      to_string(security.active),
      security.isin || "",
      security.wkn || "",
      security.provider_symbol || "",
      security.exchange_code || "",
      security.notes || ""
    ]
  end

  defp parse_preview_headers_and_rows({:error, reason}, _currency_codes), do: {:error, reason}

  defp parse_preview_headers_and_rows([], _currency_codes),
    do: {:error, "CSV input is empty."}

  defp parse_preview_headers_and_rows({:ok, rows}, valid_currency_codes),
    do: parse_preview_headers_and_rows(rows, valid_currency_codes)

  defp parse_preview_headers_and_rows(rows, valid_currency_codes) when is_list(rows) do
    with {:ok, header_map, data_rows} <- parse_header_row(rows),
         :ok <- validate_data_rows_present(data_rows) do
      parsed_rows =
        data_rows
        |> Enum.with_index(1)
        |> Enum.map(fn {row, index} ->
          parse_preview_row(row, index, header_map, valid_currency_codes)
        end)

      {:ok, %{rows: parsed_rows}}
    end
  end

  defp parse_header_row([]), do: {:error, "CSV is missing a header row."}

  defp parse_header_row([header_row | data_rows]) do
    header_map =
      header_row
      |> Enum.with_index()
      |> Enum.map(fn {header, index} -> {normalize_header(header), index} end)
      |> Map.new()

    missing_headers =
      @required_headers
      |> Enum.reject(&Map.has_key?(header_map, &1))

    if Enum.empty?(missing_headers) do
      {:ok, header_map, data_rows}
    else
      {:error, "Missing required headers: #{Enum.join(missing_headers, ", ")}"}
    end
  end

  defp validate_data_rows_present(data_rows) do
    non_empty_rows =
      Enum.reject(data_rows, fn row ->
        blank_csv_row?(row)
      end)

    if Enum.empty?(non_empty_rows) do
      {:error, "CSV has no data rows."}
    else
      :ok
    end
  end

  defp blank_csv_row?(row), do: row == [""]

  defp parse_preview_row(row, row_number, header_map, valid_currency_codes) do
    name = fetch_csv_field(row, header_map, "name")
    symbol = fetch_csv_field(row, header_map, "symbol")
    currency_code = fetch_csv_field(row, header_map, "currency_code")
    active_raw = fetch_csv_field(row, header_map, "active")
    isin = fetch_csv_field(row, header_map, "isin")
    wkn = fetch_csv_field(row, header_map, "wkn")
    provider_symbol = fetch_csv_field(row, header_map, "provider_symbol")
    exchange_code = fetch_csv_field(row, header_map, "exchange_code")
    notes = fetch_csv_field(row, header_map, "notes")

    active = parse_active_value(active_raw)
    active_errors = active_errors(active_raw)
    name_errors = required_field_errors("name", name)
    symbol_errors = required_field_errors("symbol", symbol)
    currency_errors = required_currency_errors(currency_code, valid_currency_codes)

    errors =
      []
      |> add_errors(name_errors)
      |> add_errors(symbol_errors)
      |> add_errors(active_errors)
      |> add_errors(currency_errors)

    status = if Enum.empty?(errors), do: :valid, else: :invalid

    %{
      row_number: row_number,
      status: status,
      errors: errors,
      name: name,
      symbol: symbol,
      currency_code: currency_code,
      active: active,
      isin: isin,
      wkn: wkn,
      provider_symbol: provider_symbol,
      exchange_code: exchange_code,
      notes: notes
    }
  end

  defp parse_active_value(raw) do
    case parse_active(raw) do
      {:ok, value} -> value
      _ -> nil
    end
  end

  defp active_errors(active_raw) do
    case parse_active(active_raw) do
      {:ok, _} -> []
      {:error, error} -> [error]
    end
  end

  defp parse_active(raw) do
    case String.downcase(String.trim(raw)) do
      "" -> {:ok, true}
      "true" -> {:ok, true}
      "false" -> {:ok, false}
      _ -> {:error, "active must be true or false"}
    end
  end

  defp required_field_errors("name", value) do
    if String.trim(value) == "" do
      ["name is required"]
    else
      []
    end
  end

  defp required_field_errors("symbol", value) do
    if String.trim(value) == "" do
      ["symbol is required"]
    else
      []
    end
  end

  defp required_field_errors(_field, _value), do: []

  defp required_currency_errors(currency_code, valid_currency_codes) do
    currency_code = String.trim(currency_code)

    cond do
      currency_code == "" ->
        ["currency_code is required"]

      MapSet.size(valid_currency_codes) > 0 and
          not MapSet.member?(valid_currency_codes, currency_code) ->
        ["currency_code is unknown"]

      true ->
        []
    end
  end

  defp fetch_csv_field(row, header_map, header) do
    header_index = Map.get(header_map, header)

    case header_index do
      nil -> ""
      index -> Enum.at(row, index, "") |> String.trim()
    end
  end

  defp add_errors(errors, []), do: errors
  defp add_errors(errors, new_errors), do: errors ++ new_errors

  defp normalize_header(header) do
    header
    |> String.trim()
    |> String.downcase()
  end

  defp parse_csv_rows(text) when is_binary(text) do
    if text == "" do
      {:error, "CSV input is empty."}
    else
      do_parse_csv_rows(text, "", [], false, [])
    end
  end

  defp do_parse_csv_rows("", field, row_fields, false, rows) do
    {:ok, Enum.reverse(append_row(field, row_fields, rows))}
  end

  defp do_parse_csv_rows("", _field, _row_fields, true, _rows) do
    {:error, "Malformed CSV: unterminated quoted field"}
  end

  defp do_parse_csv_rows(<<?,, rest::binary>>, field, row_fields, false, rows) do
    do_parse_csv_rows(rest, "", [field | row_fields], false, rows)
  end

  defp do_parse_csv_rows(<<?\r, ?\n, rest::binary>>, field, row_fields, false, rows) do
    do_parse_csv_rows(rest, "", [], false, append_row(field, row_fields, rows))
  end

  defp do_parse_csv_rows(<<?\r, rest::binary>>, field, row_fields, false, rows) do
    do_parse_csv_rows(rest, "", [], false, append_row(field, row_fields, rows))
  end

  defp do_parse_csv_rows(<<?\n, rest::binary>>, field, row_fields, false, rows) do
    do_parse_csv_rows(rest, "", [], false, append_row(field, row_fields, rows))
  end

  defp do_parse_csv_rows(<<?\", ?\", rest::binary>>, field, row_fields, true, rows) do
    do_parse_csv_rows(rest, <<field::binary, ?\">>, row_fields, true, rows)
  end

  defp do_parse_csv_rows(<<?\", rest::binary>>, field, row_fields, true, rows) do
    do_parse_csv_rows(rest, field, row_fields, false, rows)
  end

  defp do_parse_csv_rows(<<?\", rest::binary>>, field, row_fields, false, rows) do
    do_parse_csv_rows(rest, field, row_fields, true, rows)
  end

  defp do_parse_csv_rows(<<char::utf8, rest::binary>>, field, row_fields, in_quotes, rows) do
    do_parse_csv_rows(rest, <<field::binary, char::utf8>>, row_fields, in_quotes, rows)
  end

  defp append_row(field, row_fields, rows) do
    row = Enum.reverse([field | row_fields])

    if blank_csv_row?(row) do
      rows
    else
      [row | rows]
    end
  end

  defp encode_csv_row(fields) when is_list(fields) do
    Enum.map_join(fields, ",", &encode_csv_field/1)
  end

  defp encode_csv_field(value) do
    value
    |> to_string()
    |> then(fn field ->
      if needs_csv_quotes?(field) do
        "\"#{String.replace(field, "\"", "\"\"")}\""
      else
        field
      end
    end)
  end

  defp needs_csv_quotes?(field) do
    String.contains?(field, [",", "\"", "\r", "\n"])
  end
end
