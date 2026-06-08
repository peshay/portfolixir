defmodule Portfolixir.Catalog.AssetClasses do
  @moduledoc """
  Curated list of asset classes Portfolixir supports.

  These are the only values the UI offers — and the only values
  `Security` accepts in its `asset_class` field. New classes are added
  here, not by users.
  """

  use Gettext, backend: PortfolixirWeb.Gettext

  @ordered ~w(
    equity etf fund government_bond bond crypto commodity index
    warrant knock_out factor_certificate
    discount_certificate bonus_certificate express_certificate reverse_convertible
    other
  )

  @doc "Internal codes used in the database (stable, do not translate)."
  def codes, do: @ordered

  @doc "Returns `[{label, code}, ...]` for use in <select> options."
  def options do
    Enum.map(@ordered, fn code -> {label(code), code} end)
  end

  @doc "Localized display label for an asset class code."
  def label("equity"), do: gettext("Equity")
  def label("etf"), do: gettext("ETF")
  def label("fund"), do: gettext("Fund")
  def label("government_bond"), do: gettext("Government bond")
  def label("bond"), do: gettext("Bond")
  def label("crypto"), do: gettext("Cryptocurrency")
  def label("commodity"), do: gettext("Commodity")
  def label("index"), do: gettext("Index")
  def label("warrant"), do: gettext("Warrant")
  def label("knock_out"), do: gettext("Knock-out product")
  def label("factor_certificate"), do: gettext("Factor certificate")
  def label("discount_certificate"), do: gettext("Discount certificate")
  def label("bonus_certificate"), do: gettext("Bonus certificate")
  def label("express_certificate"), do: gettext("Express certificate")
  def label("reverse_convertible"), do: gettext("Reverse convertible")
  def label("other"), do: gettext("Other")
  # Grouping nodes in the built-in asset-class tree (not valid security codes).
  def label("leverage_products"), do: gettext("Leverage products")
  def label("investment_products"), do: gettext("Investment products")
  def label(nil), do: ""
  def label(other), do: to_string(other)
end
