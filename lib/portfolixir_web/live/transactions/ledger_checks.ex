defmodule PortfolixirWeb.Transactions.LedgerChecks do
  @moduledoc """
  The human view of the ledger's read-only checks (Sprint 23 V1; board
  `ux-design-2026-11-02-sprint23/01` ①a, picks Q1 = A and Q2 = problem).

  Each check is one agent read over the JSON API and one finding on the
  Overview's data-quality line, whose link opens the transaction history
  filtered to exactly the read's rows (`/transactions?dq=<check>`):

    * `cash_mismatch` — `GET /api/v1/transactions/cash_mismatch`, the buys
      and sells whose stored cash misses their figures
      (`Portfolixir.Ledger.StatedCash.report/0`, #1371);
    * `rate_only` — `GET /api/v1/transactions/rate_only`, the cross-currency
      buys and sells with a settlement rate and neither amount
      (`Portfolixir.Ledger.SettlementGuard.rate_only_report/0`, #1290);
    * `incomplete_split` — `GET /api/v1/splits/incomplete`, the split
      events missing a portfolio that held the security
      (`Portfolixir.Ledger.Splits.incomplete_events_report/0`, #1292). Its
      rows are events; the history shows each event's booked rows
      (`transaction_ids`), and the note names what each one misses.

  The count, the rows and the figures come from the read's own domain
  function, never from a second query, so the Overview's count, the
  history's rows and the agent's read are one set. A `dq` value that names
  no check is ignored (a whitelist, never an atom made from input).
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Ledger.SettlementGuard
  alias Portfolixir.Ledger.Splits
  alias Portfolixir.Ledger.StatedCash
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Format

  @checks ["cash_mismatch", "rate_only", "incomplete_split"]

  @doc """
  The `dq` URL value, when it names a check; anything else (absent, unknown,
  not a string) is `nil` and filters nothing.
  """
  @spec parse(term()) :: String.t() | nil
  def parse(value) when value in @checks, do: value
  def parse(_value), do: nil

  @doc "The check's report, read from its domain function (the API's own)."
  @spec report(String.t()) :: map()
  def report("cash_mismatch"), do: StatedCash.report()
  def report("rate_only"), do: SettlementGuard.rate_only_report()
  def report("incomplete_split"), do: Splits.incomplete_events_report()

  @doc """
  The count the Overview names: the length of the read's `rows`, the number
  an agent reads from the API.
  """
  @spec count(String.t()) :: non_neg_integer()
  def count(check), do: check |> report() |> Map.fetch!(:rows) |> length()

  @doc """
  The history filter of a check: the report's count, the ids of the
  transactions it lists and, per id, the figure the check compares (the
  row's second line).
  """
  @spec filter(String.t() | nil) :: map() | nil
  def filter(nil), do: nil

  def filter(check) do
    %{rows: rows} = report(check)

    %{
      check: check,
      count: length(rows),
      rows: rows,
      ids: rows |> Enum.flat_map(&row_ids(check, &1)) |> MapSet.new(),
      figures: rows |> Enum.flat_map(&figure(check, &1)) |> Map.new()
    }
  end

  defp row_ids("incomplete_split", %{transaction_ids: ids}), do: ids
  defp row_ids(_check, %{id: id}), do: [id]

  # The figure the check compares, as the row's second line.
  defp figure("cash_mismatch", %{id: id, derived_cash: derived}),
    do: [{id, {:derived, derived}}]

  # The settlement amount the row's own rate gives, in the account's
  # currency: the figure the booking drawer's „Abrechnungsbetrag“ takes
  # (before fees and taxes, `SettlementForm`), so typing it there books the
  # read's expected_cash — the guard's relation inverted (closing act, S1).
  defp figure("rate_only", %{id: id} = row) do
    settlement =
      SettlementGuard.trade_amount(row.type, row.expected_cash, row.fees, row.taxes)

    [{id, {:own_rate, row.settlement_fx_rate, settlement, row.cash_account_currency_code}}]
  end

  # A split row carries no amount; the note names what its event misses.
  defp figure("incomplete_split", _event), do: []

  @doc "The text of a row's second line."
  @spec figure_text(tuple()) :: String.t()
  def figure_text({:derived, amount}),
    do: gettext("from its figures: %{amount}", amount: Format.money(amount))

  def figure_text({:own_rate, rate, amount, currency}),
    do:
      gettext("settlement amount at its own rate %{rate}: %{amount}",
        rate: Format.exact(rate),
        amount: Format.money(amount) <> " " <> currency
      )

  @doc """
  Whether `transaction` stands in the filter (every transaction without
  one).
  """
  @spec member?(map() | nil, map()) :: boolean()
  def member?(nil, _transaction), do: true
  def member?(%{ids: ids}, %{id: id}), do: MapSet.member?(ids, id)

  attr(:filter, :map, required: true)

  @doc """
  The clamped note above the filtered rows: the read's note and remedy in
  the operator's words, its count first (UX-DR25), and „Alle Buchungen
  zeigen“ in its actions. At problem severity while the check lists a row;
  a check that lists none (repaired since the link was followed) says so
  in a note.
  """
  def filter_note(%{filter: %{count: 0}} = assigns) do
    ~H"""
    <AppShell.data_note severity={:note} id="transaction-dq-note" data-role="dq-filter-note" clamp>
      <%= gettext("Filtered by a data-quality check that lists no booking now.") %>
      <:actions>
        <.link patch="/transactions"><%= gettext("Show all bookings") %></.link>
      </:actions>
    </AppShell.data_note>
    """
  end

  def filter_note(assigns) do
    ~H"""
    <AppShell.data_note
      severity={:problem}
      id="transaction-dq-note"
      data-role="dq-filter-note"
      clamp
    >
      <%= note_text(@filter) %>
      <:actions>
        <%= if href = record_split_href(@filter) do %>
          <.link navigate={href}><%= gettext("Record split") %></.link>
          <span aria-hidden="true"> · </span>
        <% end %>
        <.link patch="/transactions"><%= gettext("Show all bookings") %></.link>
      </:actions>
    </AppShell.data_note>
    """
  end

  defp note_text(%{check: "cash_mismatch", count: count}) do
    ngettext(
      "Filtered: %{count} buy or sell whose cash misses its quantity × price, fees and taxes",
      "Filtered: %{count} buys or sells whose cash misses their quantity × price, fees and taxes",
      count
    ) <>
      " — " <>
      gettext(
        "so the cash balance and the cost read different amounts. State the cash in the booking form (Edit): the amount settled, or the one the figures give. Nothing is changed automatically."
      )
  end

  defp note_text(%{check: "incomplete_split", count: count, rows: events}) do
    details =
      for event <- events, missing <- event.missing_portfolios do
        gettext(
          "%{security} · %{ratio} · %{date}: “%{portfolio}”, which held %{quantity} shares before, is missing.",
          security: event.security_name,
          ratio: "#{event.ratio_numerator}:#{event.ratio_denominator}",
          date: Format.date(event.date),
          portfolio: missing.portfolio_name || "##{missing.portfolio_id}",
          quantity: Format.exact(missing.quantity_before)
        )
      end

    lead =
      ngettext(
        "Filtered: %{count} split missing a portfolio",
        "Filtered: %{count} splits each missing a portfolio",
        count
      )

    remedy =
      gettext(
        "There the FIFO lots are split and the holding is not. Record the split again with the same date and ratio (“Record split” on the security): it adds only the missing rows. If the split is wrong, delete the whole split. Nothing is changed automatically."
      )

    Enum.join([lead <> " —" | details] ++ [remedy], " ")
  end

  defp note_text(%{check: "rate_only", count: count}) do
    ngettext(
      "Filtered: %{count} cross-currency buy or sell with a rate and no cash amount",
      "Filtered: %{count} cross-currency buys or sells with a rate and no cash amount",
      count
    ) <>
      " — " <>
      gettext(
        "the ledger books quantity × price with fees and taxes, in the security's currency, as the account's cash, and never applies the rate. Enter the settlement amount in the booking form (Edit): the amount before fees and taxes, from which the form books the cash; backfilling rates does not change these bookings. Nothing is changed automatically."
      )
  end

  # "Record split" lives on the security; it is offered when the events
  # name one security, so the link says where it goes.
  defp record_split_href(%{check: "incomplete_split", rows: events}) do
    case events |> Enum.map(& &1.security_id) |> Enum.uniq() do
      [security_id] -> "/securities/#{security_id}"
      _none_or_several -> nil
    end
  end

  defp record_split_href(_filter), do: nil
end
