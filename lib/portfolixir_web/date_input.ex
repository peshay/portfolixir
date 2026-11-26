defmodule PortfolixirWeb.DateInput do
  @moduledoc """
  A date typed into a text field, in the page's language (the S32 closing
  act's UAT, finding 9: the own-period dialog asked for „2026-06-01“ on a
  German screen that writes 01.06.2026 everywhere else).

    * **Rendered in the page's locale.** A German page shows a stored day
      as `01.06.2026`, an English page as `2026-06-01`, the way each page
      writes a date (`PortfolixirWeb.Format.date/1`). Text the operator
      typed renders back as typed.
    * **Read strictly, handed on as ISO.** `to_iso/1` reads `TT.MM.JJJJ`
      (a day and a month of one or two digits) and the ISO `YYYY-MM-DD`
      on every page, so a pasted ISO date is taken too, and answers the ISO
      date the context and the API take. A day that does not exist
      (`31.02.2026`) or any other text is handed on as typed, so the
      changeset refuses it at its field, in its own words; nothing is
      guessed.

  The API and the stored record stay ISO; only the field changes.
  """

  @doc "The field's `pattern`: either form, so the browser lets both through."
  @spec pattern() :: String.t()
  def pattern, do: "[0-9]{1,2}\\.[0-9]{1,2}\\.[0-9]{4}|[0-9]{4}-[0-9]{2}-[0-9]{2}"

  @doc "A day as the field shows it on a page in `locale` (default: the current one)."
  @spec value(Date.t() | nil, String.t() | nil) :: String.t()
  def value(date, locale \\ nil)
  def value(nil, _locale), do: ""

  def value(%Date{} = date, locale) do
    if german?(locale) do
      pad(date.day) <> "." <> pad(date.month) <> "." <> Integer.to_string(date.year)
    else
      Date.to_iso8601(date)
    end
  end

  @doc "The placeholder that names the field's format on a page in `locale`."
  @spec placeholder(String.t() | nil) :: String.t()
  def placeholder(locale \\ nil),
    do: if(german?(locale), do: "TT.MM.JJJJ", else: "YYYY-MM-DD")

  @doc """
  The ISO date of what was typed: `TT.MM.JJJJ` or `YYYY-MM-DD`, a real
  day; anything else as typed, trimmed, for the changeset to refuse.
  """
  @spec to_iso(String.t() | nil) :: String.t() | nil
  def to_iso(nil), do: nil

  def to_iso(text) when is_binary(text) do
    text = String.trim(text)

    with [_all, day, month, year] <- Regex.run(~r/\A(\d{1,2})\.(\d{1,2})\.(\d{4})\z/, text),
         {:ok, date} <-
           Date.new(String.to_integer(year), String.to_integer(month), String.to_integer(day)) do
      Date.to_iso8601(date)
    else
      _not_german -> text
    end
  end

  defp german?(nil), do: german?(Gettext.get_locale(PortfolixirWeb.Gettext))
  defp german?(locale), do: String.starts_with?(locale, "de")

  defp pad(n), do: n |> Integer.to_string() |> String.pad_leading(2, "0")
end
