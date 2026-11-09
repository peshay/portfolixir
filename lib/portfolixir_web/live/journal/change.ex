defmodule PortfolixirWeb.Journal.Change do
  @moduledoc """
  What one audit-journal entry changed, as the Audit journal page shows it
  (Sprint 23 V3, idea U2; board `ux-design-2026-11-02-sprint23/03-journal`
  ③): one line per changed field over a fold of the stored values, reduced
  to the fields that changed.

  The page reads the **operation**, not the diff of the two images:

  - an update (or an upsert that replaced a row) lists the fields whose
    stored before and after differ;
  - a create (or an upsert that inserted) folds every stored value, its
    before „—“;
  - a delete reads „deleted, with every value“ and folds every value of the
    before-image, its after „—“, whatever the entry's after-image holds
    (a row delete's after repeats the deleted row; found while drawing 7).

  Field names are the stored keys, as `GET /api/v1/journal` answers them, so
  the operator and the agent name a field alike. A value is shown as stored:
  text as text, a list or a map as JSON, none as „—“. A line cuts a value at
  80 characters and the fold at 300; the API carries the whole image.

  **In the privacy mode** (Sprint 26 P1, I22; plan D-5;
  `PortfolixirWeb.PrivacyMode`) every value of a field that holds a figure
  in a currency or a quantity (`hidden_fields/0`: a price, a quantity,
  fees, taxes, an amount, a stored tax figure) is the hidden placeholder,
  a zero included, and so is such a field inside a list or a map (a quote
  write's `close`), which then reads as text with the bar in its place.
  Ids, dates, kinds, text and the ratios of `shown_fields/0` (a
  probability, a weight, an exchange rate, a tax rate) stay as stored. The
  fields are named, not guessed from the value, because a stored value is
  a string; a test fails on any stored decimal field in neither list.
  """

  alias Portfolixir.Journal.Entry
  alias PortfolixirWeb.PrivacyMode

  # Bookkeeping columns every update moves; the fold keeps them, the lines
  # say what the write was for.
  @timestamps ~w(inserted_at updated_at)

  @line_cut 80
  @fold_cut 300

  # The stored fields that hold a figure in a currency or a quantity: the
  # privacy mode hides their values (plan D-5: prices included).
  @hidden ~w(price quantity fees taxes gross_amount security_amount settlement_amount close
             face_value amount_granted saver_allowance_single saver_allowance_joint
             allowance_granted allowance_used capital_gains_tax_withheld church_tax_withheld
             loss_carryforward_prior_years loss_pot_equities loss_pot_other
             solidarity_surcharge_withheld taxable_income withholding_tax_credited
             withholding_tax_pot)

  # The stored decimal fields that are ratios, rates or weights: they stay
  # in the mode, as `Format.plain_*` keeps them on the other pages (an
  # exchange rate as on a ledger check, a coupon rate as on the bond strip).
  # S28 N1: a news label's `confidence` (ADR-0056 §7) is a fraction from 0
  # to 1, a model's certainty, like a prediction's probability.
  @shown ~w(probability benchmark_rate target_weight cash_target_weight lower threshold upper
            rate settlement_fx_rate coupon_rate capital_gains_tax_rate solidarity_surcharge_rate
            church_tax_rate church_tax_rates confidence)

  @typedoc "A stored value as the page shows it."
  @type value :: String.t() | PrivacyMode.Hidden.t() | Phoenix.HTML.safe()

  @doc "The stored fields whose values the privacy mode hides."
  @spec hidden_fields() :: [String.t()]
  def hidden_fields, do: @hidden

  @doc "The stored decimal fields that are ratios and stay in the privacy mode."
  @spec shown_fields() :: [String.t()]
  def shown_fields, do: @shown

  @doc "Whether `field` holds a ratio the page shows as stored in the privacy mode."
  @spec ratio?(String.t()) :: boolean()
  def ratio?(field), do: field in @shown

  @doc """
  `%{lines: lines, values: values}` for `entry`: `lines` is `[:deleted]` for
  a delete, else `{field, before, after}` per changed field without the
  timestamps; `values` is `{field, before, after}` per field the fold shows.
  A value is text, or in the privacy mode the hidden placeholder or markup
  that draws the hidden figures inside it as the bar.
  """
  @spec build(Entry.t()) :: %{lines: list(), values: [{String.t(), value(), value()}]}
  def build(%Entry{} = entry), do: build(entry, PrivacyMode.on?())

  defp build(%Entry{operation: :delete, before: before}, mask?) do
    %{lines: [:deleted], values: every_value(before, :before, mask?)}
  end

  defp build(%Entry{before: before, after: after_image}, mask?) when not is_map(before) do
    %{lines: [], values: every_value(after_image, :after, mask?)}
  end

  defp build(%Entry{before: before, after: after_image}, mask?) do
    after_image = if is_map(after_image), do: after_image, else: %{}

    changed =
      (Map.keys(before) ++ Map.keys(after_image))
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.filter(&(Map.get(before, &1) != Map.get(after_image, &1)))

    %{
      lines:
        for field <- changed, field not in @timestamps do
          {field, show(field, before[field], @line_cut, mask?),
           show(field, after_image[field], @line_cut, mask?)}
        end,
      values:
        for field <- changed do
          {field, show(field, before[field], @fold_cut, mask?),
           show(field, after_image[field], @fold_cut, mask?)}
        end
    }
  end

  defp every_value(image, side, mask?) when is_map(image) do
    for field <- image |> Map.keys() |> Enum.sort() do
      value = show(field, image[field], @fold_cut, mask?)
      if side == :before, do: {field, value, "—"}, else: {field, "—", value}
    end
  end

  defp every_value(_image, _side, _mask?), do: []

  defp show(_field, nil, _cut, _mask?), do: "—"
  defp show(field, _value, _cut, true) when field in @hidden, do: PrivacyMode.hidden()

  # A list or a map in the mode: its hidden fields' values replaced by the
  # stand-in text before it is written as JSON and cut, then each stand-in
  # drawn as the bar.
  defp show(_field, value, cut, true) when is_map(value) or is_list(value) do
    text = value |> masked() |> Jason.encode!() |> cut(cut)
    if String.contains?(text, PrivacyMode.text()), do: PrivacyMode.html(text), else: text
  end

  defp show(_field, value, cut, _mask?), do: show(value, cut)

  defp show(value, cut) when is_binary(value), do: cut(value, cut)

  defp show(value, cut) when is_number(value) or is_boolean(value),
    do: cut(to_string(value), cut)

  defp show(value, cut), do: cut(Jason.encode!(value), cut)

  defp masked(value) when is_list(value), do: Enum.map(value, &masked/1)

  defp masked(value) when is_map(value) do
    Map.new(value, fn
      {key, inner} when not is_nil(inner) and key in @hidden -> {key, PrivacyMode.text()}
      {key, inner} -> {key, masked(inner)}
    end)
  end

  defp masked(value), do: value

  defp cut(text, cut) do
    if String.length(text) > cut, do: String.slice(text, 0, cut - 1) <> "…", else: text
  end
end
