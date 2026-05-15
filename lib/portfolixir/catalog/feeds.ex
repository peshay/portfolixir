defmodule Portfolixir.Catalog.Feeds do
  @moduledoc """
  Known quote feed identifiers.

  Stored on `Security.feed` and `Security.latest_feed`. The UI must offer
  these as a closed dropdown — manually-entered feed strings would not be
  serviceable by any of our adapters.
  """

  use Gettext, backend: PortfolixirWeb.Gettext

  @ordered ~w(NONE MANUAL PORTFOLIO_PERFORMANCE COINGECKO)

  def codes, do: @ordered

  @doc "Returns `[{label, code}, ...]` for use in <select> options."
  def options do
    Enum.map(@ordered, fn code -> {label(code), code} end)
  end

  @doc "Whether `code` is one of the known feed identifiers (or nil)."
  def supported?(nil), do: true
  def supported?(""), do: true
  def supported?(code) when is_binary(code), do: code in @ordered
  def supported?(_), do: false

  @doc "Localized display label for a feed code."
  def label("NONE"), do: gettext("None")
  def label("MANUAL"), do: gettext("Manual")
  def label("PORTFOLIO_PERFORMANCE"), do: gettext("Portfolio Performance")
  def label("COINGECKO"), do: gettext("CoinGecko")
  def label(nil), do: ""
  def label(other), do: to_string(other)
end
