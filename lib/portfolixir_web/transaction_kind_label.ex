defmodule PortfolixirWeb.TransactionKindLabel do
  @moduledoc """
  The one localized label per transaction kind (#785; EXPERIENCE.md →
  Amendment 2026-09-12 → Voice and Tone: a raw enum value never reaches a
  user-facing string).

  Every element of `Portfolixir.Ledger.Transaction.kinds/0` has a clause and
  there is deliberately no fallback: an unknown kind fails loudly in
  `transaction_kind_label_test.exs`, which pins the coverage against the
  enum, instead of printing its slug on a page. Both transaction surfaces
  (the history and the security detail) read their labels from here, so the
  two cannot drift apart again.
  """
  use Gettext, backend: PortfolixirWeb.Gettext

  @spec label(String.t()) :: String.t()
  def label("buy"), do: gettext("Buy")
  def label("sell"), do: gettext("Sell")
  def label("dividend"), do: gettext("Dividend")
  def label("interest"), do: gettext("Interest")
  def label("deposit"), do: gettext("Deposit")
  def label("removal"), do: gettext("Removal")
  def label("fee"), do: gettext("Fee")
  def label("tax"), do: gettext("Tax")
  def label("tax_refund"), do: gettext("Tax refund")
  def label("cash_transfer"), do: gettext("Cash transfer")
  def label("inbound_delivery"), do: gettext("Inbound delivery")
  def label("outbound_delivery"), do: gettext("Outbound delivery")
  def label("security_transfer"), do: gettext("Security transfer")
  def label("balance_adjustment"), do: gettext("Balance snapshot")
  def label("split"), do: gettext("Split")
end
