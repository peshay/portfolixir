defmodule PortfolixirWeb.ValuationNotes do
  @moduledoc """
  The names a valuation leaves out of its totals, built by one rule (#1081,
  D-3; board `ux-design-2026-10-04/01-overview-total`).

  Wealth's data-quality notes name the rows its totals leave out — the held
  positions with no price, the ones with a price but no rate path, the cash
  accounts with no rate path. The helpers that build those names live here
  rather than in the Wealth LiveView, so another screen that names the same
  rows uses the same rule. Wealth's notes render byte-identical to before
  they moved.

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
  named.
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
end
