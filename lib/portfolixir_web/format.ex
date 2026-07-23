defmodule PortfolixirWeb.Format do
  @moduledoc """
  Locale-aware number formatting for the web layer.

  German shows `1.234.567,89` (dot as thousands separator, comma for cents);
  English shows `1,234,567.89`. Money is always rendered with exactly two
  decimal places, percentages with one. The locale defaults to the current
  gettext locale, so LiveViews mounted through `PortfolixirWeb.LiveLocale`
  format numbers in the user's chosen language automatically.

  Formatting is a display concern — values stay full-precision `Decimal`
  everywhere else (ADR-0003); rounding happens only here.
  """

  @doc """
  Formats a Decimal as a money amount with two decimals, e.g. `1.234,50` (de)
  or `1,234.50` (en). Non-numbers render as an em dash.
  """
  def money(value, locale \\ nil)

  def money(%Decimal{} = value, locale) do
    value
    |> Decimal.round(2)
    |> Decimal.to_string(:normal)
    |> localize(locale || current_locale())
  end

  def money(_value, _locale), do: "—"

  @doc """
  Formats a Decimal fraction as a percentage with one decimal, e.g. `0.185`
  → `18,5` (de) / `18.5` (en). The percent sign is left to the caller.
  """
  def percent(value, locale \\ nil)

  def percent(%Decimal{} = value, locale) do
    value
    |> Decimal.mult(100)
    |> Decimal.round(1)
    |> Decimal.to_string(:normal)
    |> localize(locale || current_locale())
  end

  def percent(_value, _locale), do: "—"

  @doc """
  Formats a Decimal with the given number of decimal places, applying locale
  separators. E.g. `Decimal.new("1234.5")` with `places: 2` → `"1.234,50"` (de)
  or `"1,234.50"` (en). Non-numbers render as an em dash.
  """
  def decimal(value, places, locale \\ nil)

  def decimal(%Decimal{} = value, places, locale) do
    value
    |> Decimal.round(places)
    |> Decimal.to_string(:normal)
    |> localize(locale || current_locale())
  end

  def decimal(_value, _places, _locale), do: "—"

  @doc """
  Formats a Decimal with the given number of decimal places, prepending a `+`
  sign for positive values. Applies locale separators. Non-numbers render as
  an em dash.
  """
  def signed_decimal(value, places, locale \\ nil)

  def signed_decimal(%Decimal{} = value, places, locale) do
    eff_locale = locale || current_locale()
    rounded = Decimal.round(value, places)

    formatted =
      rounded
      |> Decimal.to_string(:normal)
      |> localize(eff_locale)

    case Decimal.compare(rounded, 0) do
      :gt -> "+" <> formatted
      _ -> formatted
    end
  end

  def signed_decimal(_value, _places, _locale), do: "—"

  @doc """
  Formats a date under the locale: German reads `22.07.2026`, every other
  locale keeps the unambiguous ISO form `2026-07-22`. Non-dates render as an
  em dash.
  """
  def date(value, locale \\ nil)

  def date(%Date{} = value, locale) do
    case locale || current_locale() do
      "de" -> Calendar.strftime(value, "%d.%m.%Y")
      _locale -> Date.to_iso8601(value)
    end
  end

  def date(_value, _locale), do: "—"

  defp current_locale, do: Gettext.get_locale(PortfolixirWeb.Gettext)

  defp localize(plain, locale) do
    {group, decimal} = separators(locale)
    {sign, digits} = split_sign(plain)

    {int_part, frac_part} =
      case String.split(digits, ".", parts: 2) do
        [int, frac] -> {int, frac}
        [int] -> {int, nil}
      end

    grouped = group_thousands(int_part, group)

    case frac_part do
      nil -> sign <> grouped
      frac -> sign <> grouped <> decimal <> frac
    end
  end

  defp separators("de"), do: {".", ","}
  defp separators(_locale), do: {",", "."}

  defp split_sign("-" <> rest), do: {"-", rest}
  defp split_sign(digits), do: {"", digits}

  defp group_thousands(int_part, separator) do
    int_part
    |> String.to_charlist()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.map_join(separator, &List.to_string/1)
    |> String.reverse()
  end
end
