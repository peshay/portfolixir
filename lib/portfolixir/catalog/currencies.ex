defmodule Portfolixir.Catalog.Currencies do
  @moduledoc """
  Curated ISO 4217 currency list used in the Securities UI.

  Mirrors the set Portfolio Performance offers in its security wizard.
  Adding a currency is a code change here, not a user-managed entity, so
  the UI never offers a free-text currency field that creates unknowns.
  """

  use Gettext, backend: PortfolixirWeb.Gettext

  # ISO 4217 codes plus the GBX (pence) pseudo-currency PP and others use.
  @ordered ~w(
    EUR USD GBP CHF JPY AUD CAD NZD SEK NOK DKK PLN CZK HUF
    HKD SGD CNY INR BRL MXN ZAR TRY ILS KRW TWD GBX
  )

  def codes, do: @ordered

  @doc "Returns `[{display_label, code}, ...]` for use in <select> options."
  def options do
    Enum.map(@ordered, fn code -> {"#{code} – #{name(code)}", code} end)
  end

  @doc "Whether `code` is one of the supported currency codes."
  def supported?(code) when is_binary(code), do: code in @ordered
  def supported?(_), do: false

  @doc "Localized full name for a currency code."
  def name("EUR"), do: gettext("Euro")
  def name("USD"), do: gettext("US Dollar")
  def name("GBP"), do: gettext("British Pound")
  def name("CHF"), do: gettext("Swiss Franc")
  def name("JPY"), do: gettext("Japanese Yen")
  def name("AUD"), do: gettext("Australian Dollar")
  def name("CAD"), do: gettext("Canadian Dollar")
  def name("NZD"), do: gettext("New Zealand Dollar")
  def name("SEK"), do: gettext("Swedish Krona")
  def name("NOK"), do: gettext("Norwegian Krone")
  def name("DKK"), do: gettext("Danish Krone")
  def name("PLN"), do: gettext("Polish Złoty")
  def name("CZK"), do: gettext("Czech Koruna")
  def name("HUF"), do: gettext("Hungarian Forint")
  def name("HKD"), do: gettext("Hong Kong Dollar")
  def name("SGD"), do: gettext("Singapore Dollar")
  def name("CNY"), do: gettext("Chinese Yuan")
  def name("INR"), do: gettext("Indian Rupee")
  def name("BRL"), do: gettext("Brazilian Real")
  def name("MXN"), do: gettext("Mexican Peso")
  def name("ZAR"), do: gettext("South African Rand")
  def name("TRY"), do: gettext("Turkish Lira")
  def name("ILS"), do: gettext("Israeli Shekel")
  def name("KRW"), do: gettext("South Korean Won")
  def name("TWD"), do: gettext("Taiwan Dollar")
  def name("GBX"), do: gettext("British Pence (GBX)")
  def name(other), do: to_string(other)
end
