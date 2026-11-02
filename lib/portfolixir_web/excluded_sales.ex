defmodule PortfolixirWeb.ExcludedSales do
  @moduledoc """
  The counts that lead a clamped note naming sales left out of the totals
  for more than one reason (#1351 closing act, pick Q1; DESIGN.md ③): the
  realized facet's `realized-excluded` and the Overview card's
  `trades-card-excluded` give each reason a sentence of its own, so with
  two or more reasons the later counts fell below the clamp. Each reason's
  count, in the notes' own order, goes first instead.
  """

  use Gettext, backend: PortfolixirWeb.Gettext

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
