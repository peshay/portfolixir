defmodule Portfolixir.Catalog.Isin do
  @moduledoc """
  The catalog's one rule for an ISIN (ISO 6166), in catalog normal form
  (trimmed, uppercase): two letters, nine letters or digits, and one digit —
  twelve characters (E25 S4, G17) — whose check digit agrees (E25 S5, G23).

  `valid?/1` is the predicate every path that judges an ISIN uses: a new ISIN
  recorded against an existing security
  (`Portfolixir.Catalog.record_isin_change/4`), an ISIN changed on a stored
  security, an ISIN a Portfolio Performance export carries, and the
  reconcile's identifier typing (`Portfolixir.Portfolios.Reconcile.isin?/1`).
  A lookalike (a letter from another script, an invisible character, a
  wrong check digit) is no ISIN at all rather than a different one.
  """

  @shape ~r/\A[A-Z]{2}[A-Z0-9]{9}[0-9]\z/

  @doc "Whether `value` has the shape of an ISIN in catalog normal form."
  @spec shape?(term()) :: boolean()
  def shape?(value) when is_binary(value), do: Regex.match?(@shape, value)
  def shape?(_value), do: false

  @doc """
  Whether `value` is an ISIN in catalog normal form: the shape of `shape?/1`
  and an ISO 6166 check digit that agrees (the Luhn check over the string
  with each letter as its two-digit base-36 value, A=10 … Z=35).
  """
  @spec valid?(term()) :: boolean()
  def valid?(value), do: shape?(value) and luhn_valid?(value)

  defp luhn_valid?(value) do
    value
    |> String.to_charlist()
    |> Enum.flat_map(&digitize/1)
    |> Enum.reverse()
    |> Enum.with_index()
    |> Enum.reduce(0, fn {digit, position}, sum -> sum + luhn_digit(digit, position) end)
    |> rem(10) == 0
  end

  defp digitize(char) when char in ?0..?9, do: [char - ?0]
  defp digitize(char) when char in ?A..?Z, do: [div(char - ?A + 10, 10), rem(char - ?A + 10, 10)]

  defp luhn_digit(digit, position) when rem(position, 2) == 1 do
    doubled = digit * 2
    if doubled > 9, do: doubled - 9, else: doubled
  end

  defp luhn_digit(digit, _position), do: digit
end
