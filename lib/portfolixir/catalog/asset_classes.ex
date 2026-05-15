defmodule Portfolixir.Catalog.AssetClasses do
  @moduledoc """
  Curated list of asset classes Portfolixir supports.

  These are the only values the UI offers — and the only values
  `Security` accepts in its `asset_class` field. New classes are added
  here, not by users.
  """

  use Gettext, backend: PortfolixirWeb.Gettext

  @ordered ~w(equity etf fund bond crypto commodity index other)

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
  def label("bond"), do: gettext("Bond")
  def label("crypto"), do: gettext("Cryptocurrency")
  def label("commodity"), do: gettext("Commodity")
  def label("index"), do: gettext("Index")
  def label("other"), do: gettext("Other")
  def label(nil), do: ""
  def label(other), do: to_string(other)
end
