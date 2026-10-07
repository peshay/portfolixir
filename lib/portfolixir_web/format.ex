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
    |> percent_as_displayed()
    |> Decimal.to_string(:normal)
    |> localize(locale || current_locale())
  end

  def percent(_value, _locale), do: "—"

  @doc """
  Formats a Decimal with locale separators and **without rounding**: every
  stored digit is kept. For a surface that is the human read of an API
  payload, where rounding would make the page and the payload disagree while
  a missing thousands separator only makes the page harder to read.
  """
  def exact(value, locale \\ nil)

  def exact(%Decimal{} = value, locale) do
    value
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
    |> localize(locale || current_locale())
  end

  def exact(_value, _locale), do: "—"

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
  Formats a native amount — a balance no rate converts — with at least two
  decimal places and every further digit it carries, applying locale
  separators: `2000` → `"2.000,00"` (de), `0.004` → `"0,004"`. Trailing
  zeros of a stored scale add nothing. Non-numbers render as an em dash.
  """
  def native_amount(value, locale \\ nil)

  def native_amount(%Decimal{} = value, locale) do
    %Decimal{exp: exp} = Decimal.normalize(value)
    decimal(value, max(2, -exp), locale)
  end

  def native_amount(_value, _locale), do: "—"

  @doc """
  Formats a Decimal with the given number of decimal places, prepending a `+`
  sign for positive values. Applies locale separators. Non-numbers render as
  an em dash.

  The sign is the one the displayed figure has (`displayed_sign/2`): a value
  that rounds to zero reads without a sign from either side, `-0.004` at two
  places as `0,00`, never `-0,00`.
  """
  def signed_decimal(value, places, locale \\ nil)

  def signed_decimal(%Decimal{} = value, places, locale) do
    value
    |> Decimal.round(places)
    |> signed_text(locale || current_locale())
  end

  def signed_decimal(_value, _places, _locale), do: "—"

  @doc """
  Formats a Decimal fraction as a signed percentage with one decimal, e.g.
  `0.2707` → `+27,1` (de) / `+27.1` (en), `-0.051` → `-5,1`. The percent sign
  is left to the caller, as with `percent/2`.

  The sign is the one the displayed figure has (`displayed_percent_sign/1`),
  as its gain/loss colour is: a positive value carries an explicit `+`, a
  negative one its `-`, and a value that rounds to `0,0` from either side
  none — never `+0,0` or `-0,0` (the trades surfaces' form, issues 1089 and
  1060). Non-numbers render as an em dash.
  """
  def signed_percent(value, locale \\ nil)

  def signed_percent(%Decimal{} = value, locale) do
    value
    |> percent_as_displayed()
    |> signed_text(locale || current_locale())
  end

  def signed_percent(_value, _locale), do: "—"

  @doc """
  The sign a Decimal shows once rounded to `places` decimals, the precision
  it is displayed at: `:positive`, `:negative` or `:zero`; `nil` for a
  non-number.

  A signed figure takes its sign and its gain/loss colour from here, so the
  two agree with the digits on the screen: a value that rounds to zero is
  directionless — no sign, no gain or loss colour — even when the stored
  value is a fraction of a cent above or below it.
  """
  def displayed_sign(%Decimal{} = value, places), do: value |> Decimal.round(places) |> sign()
  def displayed_sign(_value, _places), do: nil

  @doc """
  The sign a Decimal fraction shows as a one-decimal percent (`percent/2`,
  `signed_percent/2`): `:positive`, `:negative` or `:zero`; `nil` for a
  non-number. See `displayed_sign/2`.
  """
  def displayed_percent_sign(%Decimal{} = value), do: value |> percent_as_displayed() |> sign()
  def displayed_percent_sign(_value), do: nil

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

  @doc """
  Formats the month of a date under the locale, the month form of `date/2`:
  German reads `10.2026`, every other locale the ISO month `2026-10`. For a
  date known only to its month (a calendar fact's month timing, a per-month
  table row). Non-dates render as an em dash.
  """
  def month(value, locale \\ nil)

  def month(%Date{} = value, locale) do
    month = value.month |> Integer.to_string() |> String.pad_leading(2, "0")
    year = value.year |> Integer.to_string() |> String.pad_leading(4, "0")

    case locale || current_locale() do
      "de" -> month <> "." <> year
      _locale -> year <> "-" <> month
    end
  end

  def month(_value, _locale), do: "—"

  @doc """
  Formats an instant to the minute, in UTC, with its date under the locale:
  `04.10.2026 00:09 UTC` (de), `2026-10-04 00:09 UTC` elsewhere. For a
  compute instant a basis line names. Non-instants render as an em dash.
  """
  def utc_instant(value, locale \\ nil)

  def utc_instant(%DateTime{} = value, locale) do
    utc = DateTime.shift_zone!(value, "Etc/UTC")
    date(DateTime.to_date(utc), locale) <> " " <> Calendar.strftime(utc, "%H:%M") <> " UTC"
  end

  def utc_instant(_value, _locale), do: "—"

  defp current_locale, do: Gettext.get_locale(PortfolixirWeb.Gettext)

  # A fraction as the one-decimal percent it is displayed as.
  defp percent_as_displayed(value), do: value |> Decimal.mult(100) |> Decimal.round(1)

  defp sign(rounded) do
    case Decimal.compare(rounded, 0) do
      :gt -> :positive
      :lt -> :negative
      :eq -> :zero
    end
  end

  # An already rounded figure with the sign it shows: "+" for a gain, "-" for
  # a loss, none for a zero — including the negative zero a small loss rounds
  # to, which `Decimal.to_string/2` would print as "-0.00".
  defp signed_text(rounded, locale) do
    digits = rounded |> Decimal.abs() |> Decimal.to_string(:normal) |> localize(locale)

    case sign(rounded) do
      :positive -> "+" <> digits
      :negative -> "-" <> digits
      :zero -> digits
    end
  end

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
