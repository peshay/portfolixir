defmodule PortfolixirWeb.ValuationNotes do
  @moduledoc """
  The names a valuation leaves out of its totals, built by one rule for every
  screen that says so (#1081, D-3; board `ux-design-2026-10-04/01-overview-total`).

  Wealth's data-quality notes and the Overview's note under its total both
  name the rows a total leaves out — the held positions with no price, the
  ones with a price but no rate path, the cash accounts with no rate path —
  so the helpers that build those names live here rather than in either
  LiveView. Wealth's notes render byte-identical to before they moved.

  One difference is deliberate: a retired held position with no price. The
  Overview names it, because it is out of the total the note sits under;
  Wealth's no-price note leaves it out (PR #1102), because that note links to
  `?dq=missing_quote`, a list without retired securities, and its count must
  equal that list.

  UX-DR25: the count and the names both render, each row keeps its native
  figure and never a converted one, and a long list is shortened by one rule:
  six names, then "+N", the count taken before shortening so it stays true.

  Everything here formats at render time: the gettext calls and the locale
  separators need the LiveView process's locale, which an async task does not
  carry.
  """
  use Gettext, backend: PortfolixirWeb.Gettext

  alias PortfolixirWeb.Format

  # How many names a list shows before it ends in "+N" (#703).
  @names_shown 6

  @doc """
  Keeps the first six names and appends "+N" for the rest; a list of six or
  fewer is returned as it is.
  """
  def shorten_list(names) when length(names) <= @names_shown, do: names

  def shorten_list(names) do
    {shown, rest} = Enum.split(names, @names_shown)
    shown ++ ["+#{length(rest)}"]
  end

  @doc """
  A held position's name in an unvalued list (#406): a `:missing_fx`
  position carries its known native price with its currency (owner decision
  2026-07-31), "Name (12.40 USD)"; a `:no_price` position has nothing to show
  but its name.
  """
  def unvalued_entry_label(position, :missing_fx) do
    name = position.security_name || gettext("Unsorted")
    "#{name} (#{Format.decimal(position.latest_price, 2)} #{position.price_currency})"
  end

  def unvalued_entry_label(position, _reason),
    do: position.security_name || gettext("Unsorted")

  @doc """
  The cash balances a valuation leaves out of its totals: no rate path to the
  base currency and a non-zero balance. An empty account leaves nothing out
  of the total, as the performance walk counts it (#1055), so it is not
  named — the same rule the valuation's `unvalued_cash_count` counts by.
  """
  def unvalued_cash(nil), do: []

  def unvalued_cash(valuation) do
    Enum.filter(
      valuation.cash_balances,
      &(not &1.valued and not Decimal.equal?(&1.balance, 0))
    )
  end

  @doc """
  UX-DR25 clause 2 (#1055, board J2's before/after): the account with its
  native balance — "USD Settlement (1.850,00 USD)" — in the shape
  `unvalued_entry_label/2` prints a native price in. Nothing is converted:
  there is no rate to convert with.
  """
  def unvalued_cash_label(entry),
    do: "#{entry.name} (#{Format.native_amount(entry.balance)} #{entry.currency})"

  @doc """
  The groups of the Overview's note under its total (#1081, pick J1 A), in
  order: the cash accounts with no rate path to the base currency, the held
  positions with no price, the held positions with a price but no rate path.
  Each group is one localized phrase — its count, what it is, and its names
  shortened to six and "+N"; a group with no member is absent, so a
  valuation that leaves nothing out gives `[]` (UX-DR2: no all-clear).

  It reads only what the valuation already carries:
  `cash_balances[].valued` and `positions[].unvalued_reason`. A security
  held in several depots counts once; two securities that share a name count
  twice. A retired security is named too: it is out of the total.
  """
  def excluded_groups(valuation) do
    base = valuation.base_currency

    [
      cash_group(unvalued_cash(valuation), base),
      position_group(position_names(valuation, :no_price), :no_price, base),
      position_group(position_names(valuation, :missing_fx), :missing_fx, base)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp cash_group([], _base), do: nil

  defp cash_group(accounts, base) do
    ngettext(
      "%{count} cash account with no exchange rate to %{base} — %{names}",
      "%{count} cash accounts with no exchange rate to %{base} — %{names}",
      length(accounts),
      base: base,
      names: accounts |> Enum.map(&unvalued_cash_label/1) |> join_shortened()
    )
  end

  # One row per security, not per depot and not per label: the view
  # valuation carries one position per (depot, security).
  defp position_names(valuation, reason) do
    valuation.positions
    |> Enum.filter(&(&1.unvalued_reason == reason))
    |> Enum.uniq_by(& &1.security_id)
    |> Enum.map(&unvalued_entry_label(&1, reason))
  end

  defp position_group([], _reason, _base), do: nil

  defp position_group(names, :no_price, _base) do
    ngettext(
      "%{count} held position with no price — %{names}",
      "%{count} held positions with no price — %{names}",
      length(names),
      names: join_shortened(names)
    )
  end

  defp position_group(names, :missing_fx, base) do
    ngettext(
      "%{count} held position with no exchange rate to %{base} — %{names}",
      "%{count} held positions with no exchange rate to %{base} — %{names}",
      length(names),
      base: base,
      names: join_shortened(names)
    )
  end

  defp join_shortened(names), do: names |> shorten_list() |> Enum.join(", ")
end
