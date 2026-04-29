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

  def render_csv(securities) when is_list(securities) do
    [@header | Enum.map(securities, &security_row/1)]
    |> Enum.map(&encode_csv_row/1)
    |> Enum.join("\n")
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
