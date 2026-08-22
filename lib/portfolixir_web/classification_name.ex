defmodule PortfolixirWeb.ClassificationName do
  @moduledoc """
  Display names for classification trees (issue #729).

  The built-in trees are seeded with stable English names (`asset_class` →
  "Asset class", `currency` → "Currency"). They are app-generated system
  data, not user-entered names, so the display localizes **at render time,
  keyed on the stored `key`** — the seed stays idempotent, and the stored
  name remains the stable identifier the API and MCP keep serving (same fix
  shape as #701). A user's own tree renders its stored name in every locale.
  """
  use Gettext, backend: PortfolixirWeb.Gettext

  def display(%{key: "asset_class"}), do: gettext("Asset class")
  def display(%{key: "currency"}), do: gettext("Currency")
  def display(%{name: name}), do: name
end
