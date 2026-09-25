defmodule Portfolixir.Catalog.Isin do
  @moduledoc """
  The shape of an ISIN (ISO 6166), in catalog normal form (trimmed,
  uppercase): two letters, nine letters or digits, and one digit — twelve
  characters (E25 S4, G17).

  The shape is checked where a new ISIN is recorded against an existing
  security (`Portfolixir.Catalog.record_isin_change/4`), so an identifier
  that cannot be an ISIN is never moved into the alias table the import
  ladder resolves against. The check digit is a separate rule.
  """

  @shape ~r/\A[A-Z]{2}[A-Z0-9]{9}[0-9]\z/

  @doc "Whether `value` has the shape of an ISIN in catalog normal form."
  @spec shape?(term()) :: boolean()
  def shape?(value) when is_binary(value), do: Regex.match?(@shape, value)
  def shape?(_value), do: false
end
