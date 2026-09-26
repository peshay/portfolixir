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
        finite(other, value)
    end
  end

  @doc """
  Parse a plain decimal value (string or already-`Decimal`) into a
  `Decimal`. Used for JSON-source values where the upstream parser
  has already produced a `Decimal` thanks to `Jason.decode/2` with
  `floats: :decimals`.
  """
  def parse(nil), do: {:ok, nil}
  def parse(%Decimal{} = d), do: bounded(d, d)
  def parse(value) when is_integer(value), do: bounded(Decimal.new(value), value)

  def parse(value) when is_binary(value), do: finite(String.trim(value), value)

  def parse(other), do: {:error, {:invalid_decimal, other}}

  # E25 S5 (F39): the most digits before the decimal point a parsed value may
  # carry. Wider than every ledger column (whose own bound the parsers name
  # per row), so that no arithmetic in the parser starts from a value past
  # what a column could ever hold.
  @max_integer_digits 30

  @doc "The most integer digits a parsed value may carry (E25 S5, F39)."
  @spec max_integer_digits() :: pos_integer()
  def max_integer_digits, do: @max_integer_digits

  # `Decimal.new/1` accepts "NaN" and "Infinity", and the first arithmetic on
  # them raises inside the parser (#768). A money value is finite or invalid.
  defp finite(text, original) do
    bounded(Decimal.new(text), original)
  rescue
    Decimal.Error -> {:error, {:invalid_decimal, original}}
  end

  defp bounded(%Decimal{} = decimal, original) do
    if Decimal.nan?(decimal) or Decimal.inf?(decimal) or
         integer_digits(decimal) > @max_integer_digits do
      {:error, {:invalid_decimal, original}}
    else
      {:ok, decimal}
    end
  end

  defp integer_digits(%Decimal{coef: 0}), do: 0

  defp integer_digits(%Decimal{coef: coef, exp: exp}),
    do: max(byte_size(Integer.to_string(coef)) + exp, 0)
end
