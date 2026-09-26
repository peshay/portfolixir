defmodule PortfolixirWeb.DecimalInput do
  @moduledoc """
  The one rule for a decimal text input (#869, board
  `ux-design-2026-09-24/05-numeric-inputs`; `DESIGN.md` → Numeric inputs).

  Every decimal text input (`inputmode="decimal"`) of the web layer renders its value
  through `value/2` and reads what the operator typed through `parse/2` (or
  `cast/3` at a form's boundary), so all of them show and accept a figure the
  same way:

    * **Rendered in the page's locale, never grouped.** A German page shows a
      decimal comma (`1664,40`), an English page a point (`1664.40`). Only the
      separator is swapped: the caller decides the digits (a settlement amount
      is rounded to two places, a rate to six, a stored price is shown as
      stored). No thousands separator is ever rendered into a field, because
      the field's value is read back — a grouped `1.664` would return as
      1.664. Text the operator typed renders back exactly as typed.
    * **Read strictly, never guessed.** The page's own separator is always
      the decimal separator. The other language's separator is read as one
      too — a German page accepts a typed `45.60`, an English page a pasted
      `45,60` — unless the figure has the shape of a thousands group
      (`1.664` on a German page, `1,664` on an English one): that figure reads
      two ways, and it is refused as ambiguous rather than stored a thousand
      times too small or too large. A figure with two separators
      (`1.664,40`) is refused the same way, and so is one grouped in threes
      with a space or an apostrophe (`1 664,40`, `1'664.40`), so the field
      names the thousands separator as the fix. Anything else that is not a
      plain decimal — an exponent, `NaN`, any other inner space, a trailing
      separator — is invalid.
    * **Bounded as every writer bounds it.** The figure the separator rule
      reads is parsed by `Portfolixir.Input.BoundedDecimal.parse/1`, the one
      finite-decimal parser the API, the contexts and the query parsers share
      (E25 S4), and a Decimal handed in is passed on only when it is finite.
      The changeset that stores it still rounds it to its column's scale and
      refuses a magnitude past its precision; this module only reads.

  Browser number inputs (`type="number"`) are not covered: their `value`
  must carry a point whatever the page's language, and the browser decides
  how they show it (the plan editor's weights, the benchmark rate, the tax
  year, the split ratio, and the securities filter popover's value field for
  a decimal or integer field, whose type attribute is computed — none of
  those fields is filterable today).
  """

  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Input.BoundedDecimal

  @max_length 40

  @plain ~r/\A[+-]?(?:[0-9]+(?:[.,][0-9]+)?|[.,][0-9]+)\z/
  @thousands_group ~r/\A[+-]?[1-9][0-9]{0,2}[.,][0-9]{3}\z/
  @grouped ~r/\A[+-]?[0-9]+(?:[.,][0-9]+){2,}\z/
  # Groups of three set off by a space, a no-break, narrow no-break or thin
  # space, or an apostrophe — as a bank page or a PDF prints a figure.
  @space_grouped ~r/\A[+-]?[0-9]{1,3}(?:[ \x{00A0}\x{202F}\x{2009}'\x{2019}][0-9]{3})+(?:[.,][0-9]+)?\z/u

  @type locale :: String.t() | nil
  @type reason :: :ambiguous | :invalid

  @doc """
  The `value` attribute of a decimal input: a Decimal in the page's locale,
  typed text as typed, nothing as the empty string.
  """
  @spec value(Decimal.t() | String.t() | integer() | nil, locale()) :: String.t()
  def value(value, locale \\ nil)

  def value(nil, _locale), do: ""

  def value(%Decimal{} = decimal, locale) do
    text = Decimal.to_string(decimal, :normal)

    case decimal_separator(locale) do
      "," -> String.replace(text, ".", ",")
      "." -> text
    end
  end

  def value(text, _locale) when is_binary(text), do: text
  def value(integer, _locale) when is_integer(integer), do: Integer.to_string(integer)

  @doc """
  Reads a figure typed on a page of `locale` (default: the page's gettext
  locale). A finite Decimal passes through unchanged; `NaN` or `Infinity` is
  invalid (E25 S4, F17).
  """
  @spec parse(term(), locale()) :: {:ok, Decimal.t()} | :blank | {:error, reason()}
  def parse(value, locale \\ nil)

  def parse(%Decimal{} = decimal, _locale) do
    if BoundedDecimal.finite?(decimal), do: {:ok, decimal}, else: {:error, :invalid}
  end

  def parse(nil, _locale), do: :blank

  def parse(text, locale) when is_binary(text) do
    trimmed = String.trim(text)

    cond do
      trimmed == "" -> :blank
      String.length(trimmed) > @max_length -> {:error, :invalid}
      Regex.match?(@plain, trimmed) -> read_plain(trimmed, decimal_separator(locale))
      Regex.match?(@grouped, trimmed) -> {:error, :ambiguous}
      Regex.match?(@space_grouped, trimmed) -> {:error, :ambiguous}
      true -> {:error, :invalid}
    end
  end

  def parse(_value, _locale), do: {:error, :invalid}

  # One separator at most. The page's own is the decimal separator; the other
  # one is too, unless the figure is shaped like a thousands group.
  defp read_plain(text, own) do
    foreign? = not String.contains?(text, own) and String.contains?(text, other(own))

    if foreign? and Regex.match?(@thousands_group, text) do
      {:error, :ambiguous}
    else
      # The shared finite-decimal parser (E25 S4): the separator rule decides
      # what the text means, the bounded parser what it is.
      text
      |> String.replace(",", ".")
      |> leading_zero()
      |> BoundedDecimal.parse()
      |> case do
        {:ok, decimal} -> {:ok, decimal}
        :error -> {:error, :invalid}
      end
    end
  end

  defp leading_zero("." <> rest), do: "0." <> rest
  defp leading_zero("-." <> rest), do: "-0." <> rest
  defp leading_zero("+." <> rest), do: "0." <> rest
  defp leading_zero(text), do: text

  @doc """
  The form boundary: every named field present in `params` is parsed. On
  success each becomes a Decimal (a blank field is left as it was, for the
  changeset to treat as absent); otherwise the refused fields are returned,
  each with its message in the page's language. Other keys are untouched.
  """
  @spec cast(map(), [String.t()], locale()) ::
          {:ok, map()} | {:error, %{String.t() => String.t()}}
  def cast(params, fields, locale \\ nil) when is_map(params) do
    {cast, errors} =
      Enum.reduce(fields, {params, %{}}, fn field, {acc, errors} ->
        case Map.fetch(acc, field) do
          {:ok, raw} -> cast_field(acc, errors, field, raw, locale)
          :error -> {acc, errors}
        end
      end)

    if errors == %{}, do: {:ok, cast}, else: {:error, errors}
  end

  defp cast_field(acc, errors, field, raw, locale) do
    case parse(raw, locale) do
      {:ok, decimal} -> {Map.put(acc, field, decimal), errors}
      :blank -> {acc, errors}
      {:error, reason} -> {acc, Map.put(errors, field, message(reason))}
    end
  end

  @doc "A refused figure's message, in the page's language (the errors domain)."
  @spec message(reason()) :: String.t()
  def message(:ambiguous),
    do: dgettext("errors", "is ambiguous: enter it without a thousands separator")

  def message(:invalid), do: dgettext("errors", "is invalid")

  defp decimal_separator(locale) do
    case locale || Gettext.get_locale(PortfolixirWeb.Gettext) do
      "de" -> ","
      _locale -> "."
    end
  end

  defp other(","), do: "."
  defp other("."), do: ","
end
