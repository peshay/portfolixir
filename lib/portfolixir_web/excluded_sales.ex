defmodule PortfolixirWeb.ExcludedSales do
  @moduledoc """
  The counts that lead a clamped note naming sales left out of the totals
  for more than one reason (#1351 closing act, pick Q1; DESIGN.md ③): the
  realized facet's `realized-excluded` and the Overview card's
  `trades-card-excluded` give each reason a sentence of its own, so with
  two or more reasons the later counts fell below the clamp. Each reason's
  count, in the notes' own order, goes first instead.

  On the realized facet (board `ux-design-2026-11-03-sprint23-i1`, Income)
  each reason then names its sales without a second count (`named/2`), what
  each reason means sits in the facet's ⓘ (`definitions/0`), and the rate
  backfill follows only a reason it can fix (`backfill_fixes?/1`). The
  Overview card keeps its sentences.
  """

  use Gettext, backend: PortfolixirWeb.Gettext

  alias PortfolixirWeb.StoredText

  @reasons [
    :no_rate,
    :missing_settlement_leg,
    :third_currency,
    :other_account_currency,
    :zero_amount
  ]

  @doc """
  Each reason of `by_reason` with a count above zero, as its count, joined
  by "; " (a reason's own label holds a comma in German), or `nil` when
  fewer than two reasons are present: one reason's sentence leads with its
  count already.
  """
  @spec counts(map()) :: String.t() | nil
  def counts(by_reason) do
    case for(
           reason <- @reasons,
           %{count: count} when count > 0 <- [Map.get(by_reason, reason)],
           do: label(reason, count)
         ) do
      [_, _ | _] = labels -> Enum.join(labels, "; ")
      _one_or_none -> nil
    end
  end

  @doc """
  Whether `by_reason` holds a reason the rate backfill can fix: a sale with
  no stored rate at its close date, or a buy with no figure in the sale's
  currency (board `ux-design-2026-11-03-sprint23-i1`, Income; #1359). The
  backfill's sentence and its button follow only such a reason; Sprint 22
  R5's three reasons alone offer no remedy (UX-DR25 clause 3).
  """
  @spec backfill_fixes?(map()) :: boolean()
  def backfill_fixes?(by_reason) do
    Enum.any?([:no_rate, :missing_settlement_leg], fn reason ->
      match?(%{count: count} when count > 0, Map.get(by_reason, reason))
    end)
  end

  @doc """
  A reason's sentence when two or more reasons share the note (board
  `ux-design-2026-11-03-sprint23-i1`, Income ⑧): the reason's name and its
  sales, „Dritte Währung: Saltmarsh Mining plc.“ The lead carries the
  count, and the facet's ⓘ says what the reason means (`definitions/0`).
  A last name that ends in a full stop ends the sentence
  (`StoredText.ending_on/3`).
  """
  @spec named(atom(), [String.t()]) :: String.t()
  def named(reason, securities) do
    reason = name(reason)

    StoredText.ending_on(
      Enum.join(securities, ", "),
      &gettext("%{reason}: %{securities}.", reason: reason, securities: &1),
      &gettext("%{reason}: %{securities}", reason: reason, securities: &1)
    )
  end

  defp name(:no_rate), do: gettext("No stored rate")
  defp name(:missing_settlement_leg), do: gettext("Buy without a figure in the sale's currency")
  defp name(:third_currency), do: gettext("Third currency")
  defp name(:other_account_currency), do: gettext("Buy paid in another currency")
  defp name(:zero_amount), do: gettext("Buy of amount zero")

  @doc """
  What each reason other than a missing rate means, one line each in the
  note's order, for the facet's ⓘ (board `ux-design-2026-11-03-sprint23-i1`,
  Income ①). A missing rate is defined by the facet's own text (⑥).
  """
  @spec definitions() :: [String.t()]
  def definitions do
    [
      gettext(
        "Buy without a figure in the sale's currency: a buy the sale closes has no figure in the sale's currency."
      ),
      gettext(
        "Third currency: the sale or a buy it closes is priced in a currency that is neither the security's nor its account's; no rate fixes it."
      ),
      gettext(
        "Buy paid in another currency: a buy the sale closes was paid in another currency than the sale's, which no stored figure bridges; no rate fixes it."
      ),
      gettext(
        "Buy of amount zero: a buy the sale closes has an amount of zero, which the rate backfill does not complete."
      )
    ]
  end

  defp label(:no_rate, count),
    do: ngettext("%{count} sale with no stored rate", "%{count} sales with no stored rate", count)

  defp label(:missing_settlement_leg, count),
    do:
      ngettext(
        "%{count} sale whose buy has no figure in its currency",
        "%{count} sales whose buys have no figure in their currency",
        count
      )

  defp label(:third_currency, count),
    do:
      ngettext(
        "%{count} sale priced in a third currency",
        "%{count} sales priced in a third currency",
        count
      )

  defp label(:other_account_currency, count),
    do:
      ngettext(
        "%{count} sale whose buy was paid in another currency",
        "%{count} sales whose buys were paid in another currency",
        count
      )

  defp label(:zero_amount, count),
    do:
      ngettext(
        "%{count} sale whose buy has an amount of zero",
        "%{count} sales whose buys have an amount of zero",
        count
      )
end
