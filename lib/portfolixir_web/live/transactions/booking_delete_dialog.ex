defmodule PortfolixirWeb.Transactions.BookingDeleteDialog do
  @moduledoc """
  Deleting a booking from the screen (Sprint 18 U1, #912; pick H2 = A,
  board `ux-design-2026-10-02/02-booking-delete`; DESIGN.md, "Deleting a
  booking").

  One narrow destructive dialog, a native dialog element (`.modal
  .booking-delete-dialog`) on the `ModalDialog` hook, opened from a history
  row's "Delete…", from the notes-only drawer's help line, and — for a split
  — from "Record split" on the security. It names the booking the way the
  history's phone row does, says in one sentence what changes (built from
  `Portfolixir.Ledger.Projection.effects/1`, the one reducer per kind, read
  in reverse), says that everything derived is recomputed and that the
  journal keeps the booking while the screen cannot bring it back, and
  confirms once with a danger button that names the act. An imported booking
  says that its content hash goes with it, so a re-import of the same file
  books it again (plan D-6: that semantics does not change here).

  A split is deleted the way it was booked, as one fact: the dialog names
  its portfolios and its rows, and the confirm runs
  `Portfolixir.Ledger.Splits.delete_split/2`, every row in one journaled
  step. Every other kind runs `Portfolixir.Ledger.delete_transaction/2`. The
  writes are the API's and MCP's own (`DELETE /api/v1/transactions/:id`,
  `DELETE /api/v1/splits/:transaction_id`), run as the operator.

  The page that shows the dialog owns its state (`prepare/2` builds what it
  shows), handles `cancel_delete` and `confirm_delete`, and runs `delete/2`.
  The API refuses nothing but a booking that is gone, so that is the one
  refusal the page states ("That transaction no longer exists.").
  """
  use Phoenix.Component
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Positions
  alias Portfolixir.Ledger.Projection
  alias Portfolixir.Ledger.Splits
  alias Portfolixir.Ledger.Transaction
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.SecurityNames
  alias PortfolixirWeb.StoredText
  alias PortfolixirWeb.TransactionKindLabel
  alias PortfolixirWeb.TransactionManagementLive

  @zero Decimal.new("0")

  @doc """
  What the dialog shows for `transaction`, or `nil` when it is gone (a split
  whose rows were all deleted since). `context` names the page's cash
  accounts, depots, transactions and twin tags, each optional: the accounts
  name a transfer's counter side, the transactions find a later set balance
  on an affected cash account, and the tags (`SecurityNames.tags/1`) name a
  twin security with its ISIN, as the row's kebab does.
  """
  @spec prepare(%Transaction{}, map()) :: map() | nil
  def prepare(%Transaction{type: "split"} = row, context) do
    case Splits.event_rows(row) do
      [] -> nil
      rows -> split_view(row, rows, context)
    end
  end

  def prepare(%Transaction{} = transaction, context) do
    names = names(transaction, context)

    %{
      id: transaction.id,
      kind: :booking,
      title: gettext("Delete transaction"),
      subject: booking_subject(transaction, names),
      consequence: booking_consequence(transaction, names, context),
      journal:
        gettext(
          "The journal keeps the booking with all its values; the screen cannot bring it back."
        ),
      imported?: is_binary(transaction.import_hash),
      confirm: gettext("Delete transaction"),
      done: booking_done(transaction, names)
    }
  end

  @doc """
  Runs the delete `deleting` (what `prepare/2` built) confirmed, as `actor`:
  `{:ok, message}` for the page's result slot, `:gone` when the booking no
  longer exists, `{:error, message}` when the ledger refused.
  """
  @spec delete(Portfolixir.Actor.t(), map()) ::
          {:ok, String.t() | Phoenix.HTML.safe()} | :gone | {:error, String.t()}
  def delete(actor, %{id: id} = deleting) do
    case Ledger.get_transaction(id) do
      nil -> :gone
      %Transaction{type: "split"} = row -> delete_split(actor, row, deleting)
      %Transaction{} = transaction -> delete_booking(actor, transaction, deleting)
    end
  end

  defp delete_split(actor, row, deleting) do
    case Splits.delete_split(actor, row) do
      {:ok, rows} -> {:ok, split_done(deleting, length(rows))}
      {:error, :not_found} -> :gone
      {:error, _refused} -> {:error, gettext("The booking could not be deleted.")}
    end
  end

  defp delete_booking(actor, transaction, deleting) do
    case Ledger.delete_transaction(actor, transaction) do
      {:ok, _deleted} -> {:ok, deleting.done}
      {:error, :not_found} -> :gone
      {:error, _changeset} -> {:error, gettext("The booking could not be deleted.")}
    end
  end

  # -- the dialog ----------------------------------------------------------------

  attr(:deleting, :map, required: true)

  attr(:focus_fallback, :string,
    required: true,
    doc: "where the focus goes when the dialog closes and its opener is gone"
  )

  @doc "The dialog for what `prepare/2` built."
  def dialog(assigns) do
    ~H"""
    <dialog
      id="booking-delete-dialog"
      class="modal booking-delete-dialog"
      phx-hook="ModalDialog"
      data-close-event="cancel_delete"
      data-focus-fallback={@focus_fallback}
      aria-labelledby="booking-delete-dialog-title"
      aria-describedby="booking-delete-subject"
    >
      <header class="modal-head">
        <h2 id="booking-delete-dialog-title"><%= @deleting.title %></h2>
        <button
          type="button"
          class="icon-button"
          aria-label={gettext("Close")}
          phx-click="cancel_delete"
        >
          <AppShell.icon name={:x} />
        </button>
      </header>
      <div class="modal-body">
        <p id="booking-delete-subject" class="booking-delete__subject">
          <span class="phone-row__body">
            <span class="phone-row__name"><%= @deleting.subject.name %></span>
            <span :if={@deleting.subject.ids} class="phone-row__ids"><%= @deleting.subject.ids %></span>
          </span>
          <span class="phone-row__figures">
            <span class="phone-row__figure"><%= @deleting.subject.figure %></span>
            <span :if={@deleting.subject.figure2} class="phone-row__figure2">
              <%= @deleting.subject.figure2 %>
            </span>
          </span>
        </p>
        <AppShell.data_note
          :if={@deleting.imported?}
          severity={:attention}
          data-role="booking-delete-imported"
        >
          <%= gettext(
            "This booking came from an import. Its content hash goes with it: a re-import of the same file books it again."
          ) %>
        </AppShell.data_note>
        <p class="hint" data-role="booking-delete-consequence">
          <%= sentences(@deleting.consequence) %>
        </p>
        <p class="hint" data-role="booking-delete-journal"><%= @deleting.journal %></p>
      </div>
      <div class="modal-footer modal-footer--band">
        <button
          type="button"
          class="button-ghost"
          data-role="booking-delete-cancel"
          phx-click="cancel_delete"
          autofocus
        >
          <%= gettext("Cancel") %>
        </button>
        <span class="modal-footer__spacer"></span>
        <button
          type="button"
          id="booking-delete-confirm"
          class="button-danger"
          phx-click="confirm_delete"
          phx-value-id={@deleting.id}
        >
          <%= @deleting.confirm %>
        </button>
      </div>
    </dialog>
    """
  end

  # The sentences of one paragraph, each escaped unless it is markup already
  # (a stored name isolated in `<bdi>`), one space between them.
  defp sentences(list) do
    {:safe,
     list
     |> Enum.map(fn sentence -> sentence |> Phoenix.HTML.html_escape() |> elem(1) end)
     |> Enum.intersperse(" ")}
  end

  # -- a booking ------------------------------------------------------------------

  # The names a booking's sentences use: its security, its accounts and a
  # transfer's counter side, from the row's preloads and the page's lists.
  defp names(transaction, context) do
    cash_by_id = by_id(Map.get(context, :cash_accounts, []), transaction, :cash_account)

    depots_by_id =
      by_id(Map.get(context, :securities_accounts, []), transaction, :securities_account)

    security = security(transaction)

    %{
      security: security && security.name,
      security_label: security && twin_label(security, context),
      cash: Map.get(cash_by_id, transaction.cash_account_id),
      counter_cash: Map.get(cash_by_id, transaction.counter_cash_account_id),
      depot: Map.get(depots_by_id, transaction.securities_account_id),
      counter_depot: Map.get(depots_by_id, transaction.counter_securities_account_id),
      cash_by_id: cash_by_id,
      depots_by_id: depots_by_id,
      currencies:
        context
        |> Map.get(:cash_accounts, [])
        |> Map.new(&{&1.id, &1.currency_code})
        |> put_preloaded_currency(transaction)
    }
  end

  # The page's accounts by id, the row's own preloaded one included.
  defp by_id(accounts, transaction, assoc) do
    accounts
    |> Map.new(&{&1.id, &1.name})
    |> then(fn map ->
      case Map.get(transaction, assoc) do
        %{id: id, name: name} when is_binary(name) -> Map.put(map, id, name)
        _not_loaded -> map
      end
    end)
  end

  defp put_preloaded_currency(map, %{cash_account: %{id: id, currency_code: code}})
       when is_binary(code),
       do: Map.put_new(map, id, code)

  defp put_preloaded_currency(map, _transaction), do: map

  defp security(%{security: %{name: name} = security}) when is_binary(name), do: security
  defp security(%{security_id: nil}), do: nil
  defp security(%{security_id: id}), do: Catalog.get_security(id)

  # A twin security — a name another security of the page also carries — is
  # named with what tells it apart, its ISIN first, wherever the row's kebab
  # label names it so (UAT-13; the closing act, R4): in the box and the
  # result. The sentences keep the plain name; the box above them says
  # which twin.
  defp twin_label(security, context),
    do: SecurityNames.label(Map.get(context, :twin_tags, %{}), security)

  # The history's phone row, said back: date · kind over the subject and the
  # account it touched; the signed amount over its size (DESIGN.md rule ②).
  defp booking_subject(transaction, names) do
    # Each stored name in its own <bdi> (H8.8; the closing act, R7), the
    # app's separators outside them.
    account_line =
      case transaction.type do
        "cash_transfer" -> [names.cash, names.counter_cash]
        "security_transfer" -> [names.depot, names.counter_depot]
        _kind -> [names.depot || names.cash]
      end
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&bdi/1)
      |> Enum.intersperse(" → ")

    ids =
      [names.security_label && bdi(names.security_label), account_line]
      |> Enum.reject(&(&1 in [nil, []]))
      |> Enum.intersperse(" · ")

    %{
      name:
        Format.date(transaction.date) <> " · " <> TransactionKindLabel.label(transaction.type),
      ids: if(ids == [], do: nil, else: {:safe, ids}),
      figure: TransactionManagementLive.phone_amount(transaction),
      figure2: TransactionManagementLive.phone_size(transaction)
    }
  end

  # What changes, concretely: the booking's own legs read in reverse — a
  # cash leg bounded by the first balance set on its account from the
  # booking's day on — then from when such a set balance keeps the account
  # unchanged, then the general recompute sentence. A set balance has its
  # own sentence: it is a level, not a flow.
  defp booking_consequence(%Transaction{type: "balance_adjustment"} = anchor, names, _context) do
    [
      StoredText.isolate(
        gettext(
          "Afterwards %{account} carries no balance set on %{date}; its balance follows the bookings again.",
          account: StoredText.slot(:account),
          date: Format.date(anchor.date)
        ),
        account: names.cash || "—"
      ),
      recompute_sentence()
    ]
  end

  defp booking_consequence(transaction, names, context) do
    effects = Projection.effects(transaction)
    cash = cash_clauses(transaction, effects.cash, names, context)
    clauses = quantity_clauses(transaction, effects.quantities, names) ++ cash

    lead =
      case clauses do
        [] ->
          []

        [first | rest] ->
          pieces =
            [clause(first, :lead) | Enum.map(rest, &clause(&1, :follow))]
            |> Enum.map(fn {:safe, iodata} -> iodata end)
            |> Enum.intersperse(", ")

          [{:safe, [pieces, "."]}]
      end

    lead ++ unchanged_from(cash) ++ [recompute_sentence()]
  end

  defp recompute_sentence,
    do: gettext("Holdings, balances, returns and trades are recomputed without this booking.")

  # What each depot the booking moved holds less (or more) today without it:
  # the holdings' own fold over the security's bookings, with the row and
  # without it, so a later split's scale is in the figure (the closing act,
  # R1) — the leg alone is the quantity on the booking's day. A security
  # transfer moves the shares between its two depots: each leg names its
  # own.
  defp quantity_clauses(_transaction, [], _names), do: []

  defp quantity_clauses(transaction, legs, names) do
    history = Ledger.list_transactions(security_id: transaction.security_id)
    with_row = Positions.calculate(history)
    without_row = Positions.calculate(Enum.reject(history, &(&1.id == transaction.id)))

    Enum.flat_map(legs, fn {depot_id, security_id, _delta} ->
      key = {depot_id, security_id}
      delta = Decimal.sub(held(with_row, key), held(without_row, key))

      if Decimal.equal?(delta, @zero),
        do: [],
        else: [{:quantity, depot_name(depot_id, names), names.security || "—", delta}]
    end)
  end

  defp held(positions, key), do: Map.get(positions, key, @zero)

  defp depot_name(depot_id, names), do: Map.get(names.depots_by_id, depot_id) || "—"

  defp cash_clauses(transaction, legs, names, context) do
    anchors = first_anchors(transaction, context)

    for {account_id, {:add, %Decimal{} = delta}} <- legs,
        not is_nil(account_id),
        not Decimal.equal?(delta, @zero) do
      {:cash, cash_name(account_id, names), delta, Map.get(names.currencies, account_id),
       bound(Map.get(anchors, account_id), transaction.date)}
    end
  end

  # A set balance anchors its account from its date on (ADR-0009), so the
  # first one on or after the booking's day bounds what the delete changes
  # there (the closing act, R2): from the booking's day to the day before
  # it — or, set on the booking's own day, on no day at all, because a
  # snapshot applies last in its day.
  defp first_anchors(transaction, context) do
    context
    |> Map.get(:transactions, [])
    |> Enum.filter(fn other ->
      other.type == "balance_adjustment" and other.id != transaction.id and
        Date.compare(other.date, transaction.date) != :lt
    end)
    |> Enum.sort_by(& &1.date, Date)
    |> Enum.uniq_by(& &1.cash_account_id)
    |> Map.new(&{&1.cash_account_id, &1.date})
  end

  defp bound(nil, _date), do: :none

  defp bound(anchored, date) do
    if Date.compare(anchored, date) == :eq,
      do: {:same_day, anchored},
      else: {:until, Date.add(anchored, -1), anchored}
  end

  # From when a later set balance keeps an account the booking moved as
  # it was set: one sentence per bounded account.
  defp unchanged_from(cash_clauses) do
    for {:cash, account, _delta, _currency, {:until, _until, anchored}} <- cash_clauses do
      StoredText.isolate(
        gettext("From the balance set on %{date} on, the balance of %{account} stays unchanged.",
          account: StoredText.slot(:account),
          date: Format.date(anchored)
        ),
        account: account
      )
    end
  end

  defp cash_name(account_id, names), do: Map.get(names.cash_by_id, account_id) || "—"

  # The quantity a leg added is what the delete takes away, and the reverse.
  defp clause({:quantity, depot, security, delta}, position) do
    quantity = format_quantity(Decimal.abs(delta))
    fewer? = Decimal.compare(delta, @zero) == :gt

    text =
      case {position, fewer?} do
        {:lead, true} ->
          gettext("Afterwards %{depot} holds %{quantity} fewer units of %{security}",
            depot: StoredText.slot(:depot),
            quantity: quantity,
            security: StoredText.slot(:security)
          )

        {:lead, false} ->
          gettext("Afterwards %{depot} holds %{quantity} more units of %{security}",
            depot: StoredText.slot(:depot),
            quantity: quantity,
            security: StoredText.slot(:security)
          )

        {:follow, true} ->
          gettext("and %{depot} holds %{quantity} fewer units of %{security}",
            depot: StoredText.slot(:depot),
            quantity: quantity,
            security: StoredText.slot(:security)
          )

        {:follow, false} ->
          gettext("and %{depot} holds %{quantity} more units of %{security}",
            depot: StoredText.slot(:depot),
            quantity: quantity,
            security: StoredText.slot(:security)
          )
      end

    StoredText.isolate(text, depot: depot, security: security)
  end

  # Set on the booking's own day, the balance changes on no day: the clause
  # names no amount.
  defp clause({:cash, account, _delta, _currency, {:same_day, date}}, position) do
    text =
      case position do
        :lead ->
          gettext("Afterwards the balance of %{account} stays as set on %{date}",
            account: StoredText.slot(:account),
            date: Format.date(date)
          )

        :follow ->
          gettext("and the balance of %{account} stays as set on %{date}",
            account: StoredText.slot(:account),
            date: Format.date(date)
          )
      end

    StoredText.isolate(text, account: account)
  end

  defp clause({:cash, account, delta, currency, :none}, position) do
    amount = cash_amount(delta, currency)

    text =
      case {position, more?(delta)} do
        {:lead, true} ->
          gettext("Afterwards %{account} has %{amount} more",
            account: StoredText.slot(:account),
            amount: amount
          )

        {:lead, false} ->
          gettext("Afterwards %{account} has %{amount} less",
            account: StoredText.slot(:account),
            amount: amount
          )

        {:follow, true} ->
          gettext("and %{account} has %{amount} more",
            account: StoredText.slot(:account),
            amount: amount
          )

        {:follow, false} ->
          gettext("and %{account} has %{amount} less",
            account: StoredText.slot(:account),
            amount: amount
          )
      end

    StoredText.isolate(text, account: account)
  end

  defp clause({:cash, account, delta, currency, {:until, until, _anchored}}, position) do
    amount = cash_amount(delta, currency)
    until = Format.date(until)

    text =
      case {position, more?(delta)} do
        {:lead, true} ->
          gettext("Afterwards %{account} has %{amount} more until %{until}",
            account: StoredText.slot(:account),
            amount: amount,
            until: until
          )

        {:lead, false} ->
          gettext("Afterwards %{account} has %{amount} less until %{until}",
            account: StoredText.slot(:account),
            amount: amount,
            until: until
          )

        {:follow, true} ->
          gettext("and %{account} has %{amount} more until %{until}",
            account: StoredText.slot(:account),
            amount: amount,
            until: until
          )

        {:follow, false} ->
          gettext("and %{account} has %{amount} less until %{until}",
            account: StoredText.slot(:account),
            amount: amount,
            until: until
          )
      end

    StoredText.isolate(text, account: account)
  end

  defp cash_amount(delta, currency),
    do: Format.money(Decimal.abs(delta)) <> if(currency, do: " " <> currency, else: "")

  # The cash a leg took out is what the delete gives back, and the reverse.
  defp more?(delta), do: Decimal.compare(delta, @zero) == :lt

  defp booking_done(transaction, names) do
    kind = TransactionKindLabel.label(transaction.type)
    date = Format.date(transaction.date)

    case booking_subject(transaction, names).ids do
      nil ->
        gettext("Transaction deleted: %{kind} · %{date}.", kind: kind, date: date)

      _ids ->
        StoredText.isolate(
          gettext("Transaction deleted: %{kind} · %{subject} · %{date}.",
            kind: kind,
            subject: StoredText.slot(:subject),
            date: date
          ),
          subject: names.security_label || names.cash || names.depot
        )
    end
  end

  # -- a split ---------------------------------------------------------------------

  defp split_view(row, rows, context) do
    count = length(rows)
    security = security(row)
    name = security.name
    label = twin_label(security, context)
    ratio = "#{row.split_ratio_numerator}:#{row.split_ratio_denominator}"
    names = Enum.map(rows, &portfolio_name/1)

    %{
      id: row.id,
      kind: :split,
      title: gettext("Delete split"),
      subject: %{
        name: Format.date(row.date) <> " · " <> TransactionKindLabel.label("split"),
        ids: StoredText.bdi(label),
        figure: ratio,
        figure2: ngettext("%{count} row", "%{count} rows", count)
      },
      consequence: [
        portfolios_sentence(count, names),
        StoredText.isolate(
          gettext(
            "Afterwards the holdings of %{security} count without the split from %{date} on, and the chart computes its price series without it; stored quotes stay as they are.",
            security: StoredText.slot(:security),
            date: Format.date(row.date)
          ),
          security: name
        )
      ],
      journal: split_journal(count),
      imported?: false,
      confirm: split_confirm(count),
      security: label,
      ratio: ratio,
      date: row.date,
      done: nil
    }
  end

  defp portfolio_name(%{portfolio: %{name: name}}) when is_binary(name), do: name
  defp portfolio_name(_row), do: "—"

  defp portfolios_sentence(2, names) do
    StoredText.isolate(
      gettext("The split is booked in 2 portfolios, %{names}; both rows are deleted in one step.",
        names: StoredText.slot(:names)
      ),
      names: name_list(names)
    )
  end

  defp portfolios_sentence(count, names) do
    StoredText.isolate(
      ngettext(
        "The split is booked in %{count} portfolio, %{names}; its row is deleted.",
        "The split is booked in %{count} portfolios, %{names}; all %{count} rows are deleted in one step.",
        count,
        names: StoredText.slot(:names)
      ),
      names: name_list(names)
    )
  end

  # "A, B and C", each name isolated (the list is markup a slot takes).
  defp name_list([name]), do: name

  defp name_list(names) do
    {init, [last]} = Enum.split(names, -1)

    list =
      init
      |> Enum.map(fn name -> StoredText.bdi(name) |> elem(1) end)
      |> Enum.intersperse(", ")

    StoredText.isolate(
      gettext("%{list} and %{last}", list: StoredText.slot(:list), last: StoredText.slot(:last)),
      list: {:safe, list},
      last: last
    )
  end

  defp split_journal(2), do: gettext("The journal keeps both rows.")

  defp split_journal(count),
    do: ngettext("The journal keeps its row.", "The journal keeps all %{count} rows.", count)

  # One row reads "Delete split", without a count (board A4).
  defp split_confirm(1), do: gettext("Delete split")

  defp split_confirm(count),
    do: ngettext("Delete split (%{count} row)", "Delete split (%{count} rows)", count)

  defp split_done(deleting, count) do
    StoredText.isolate(
      ngettext(
        "Split deleted: %{security} · %{ratio} · %{date}, %{count} row.",
        "Split deleted: %{security} · %{ratio} · %{date}, %{count} rows.",
        count,
        security: StoredText.slot(:security),
        ratio: deleting.ratio,
        date: Format.date(deleting.date)
      ),
      security: deleting.security
    )
  end

  defp bdi(text), do: text |> StoredText.bdi() |> elem(1)

  defp format_quantity(%Decimal{} = quantity) do
    normalized = Decimal.normalize(quantity)
    places = normalized.exp |> Kernel.-() |> max(0) |> min(8)
    Format.decimal(normalized, places)
  end
end
