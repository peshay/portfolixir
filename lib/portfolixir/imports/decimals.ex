defmodule Portfolixir.Imports.Decimals do
  @moduledoc """
  Decimal-parsing helpers for the import pipeline.

  AGENTS.md forbids `Decimal.from_float/1` on persisted financial
  values: floats round on entry and the rounded value is what you
  store. Both helpers below therefore go through `Decimal.new/1` with
  a string, which preserves the literal digits from the export.
  """

  @doc """
  Parse a German-formatted decimal string (e.g. `"23.685,40"` →
  `#Decimal<23685.40>`).

  Returns `{:ok, %Decimal{}}` or `{:error, reason}`. Empty strings and
  `nil` return `{:ok, nil}` so cash-only PP rows with blank price/qty
  cells stay normalised.
  """
  def parse_de(nil), do: {:ok, nil}
  def parse_de(""), do: {:ok, nil}

  def parse_de(value) when is_binary(value) do
    cleaned =
      value
      |> String.trim()
      |> String.replace(".", "")
      |> String.replace(",", ".")

    case cleaned do
      "" ->
        {:ok, nil}

      other ->
        try do
          {:ok, Decimal.new(other)}
        rescue
          Decimal.Error -> {:error, {:invalid_decimal, value}}
        end
    end
  end

  @doc """
  Parse a plain decimal value (string or already-`Decimal`) into a
  `Decimal`. Used for JSON-source values where the upstream parser
  has already produced a `Decimal` thanks to `Jason.decode/2` with
  `floats: :decimals`.
  """
  def parse(nil), do: {:ok, nil}
  def parse(%Decimal{} = d), do: {:ok, d}
  def parse(value) when is_integer(value), do: {:ok, Decimal.new(value)}

  def parse(value) when is_binary(value) do
    try do
      {:ok, Decimal.new(String.trim(value))}
    rescue
      Decimal.Error -> {:error, {:invalid_decimal, value}}
    end
  end

  def parse(other), do: {:error, {:invalid_decimal, other}}
end
