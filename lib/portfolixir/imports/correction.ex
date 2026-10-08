defmodule Portfolixir.Imports.Correction do
  @moduledoc """
  The correction of bookings an import stored under an older reading of
  their row (ADR-0053 §6 and its amendment's A6; risk-tier: money and import
  idempotency, ADR-0036).

  No stored row records the format it came from, so the wrong cash cannot be
  found from the database alone. It is found with the file: a re-dropped
  Portfolio Performance export (a PP CSV with a Gesamtpreis, a converter
  CSV, or a JSON v1 file) whose rows hit stored content hashes. The hash
  keeps reading what it read when the booking was made (§3, A3), so such a
  re-drop books nothing (ADR-0050 §2–§3), and the hit names the stored
  booking of each row exactly.

  **What is listed** (`detect/3`). A row whose content hash a stored
  transaction holds — the apply's own notion of a hash hit,
  `Portfolixir.Imports.Applier.row_hashes/2` — and whose stored cash
  (`gross_amount`) differs from the cash the row books today: a PP CSV
  row's Gesamtpreis (§1), a converter row's Betrag (§1), a JSON row's
  `amount`, each less a tax refund split off a credit and plus one split off
  a debit (§5, A1). The comparison is made at the column's scale, the value a
  write would store, so a listed booking is one the confirm can change.
  Each line carries the booking as stored, the changes the confirm writes,
  and its signed cash effect before and after (`Ledger.Projection`, the one
  reducer per kind), per cash account. A booking that has since become
  another kind is no longer the row's and is not listed, nor is a row whose
  split-off refund is no longer stored (deleted by hand since): its
  correction takes the refund out of its cash because the refund is booked
  beside it, so corrected alone it would leave the cash below the stored
  state.

  **What the confirm writes**, per listed booking, and nothing else:

    * the cash (`gross_amount`);
    * for a JSON purchase or sale, the price too: a JSON price is derived
      from the cash (A2), while a CSV row's price is Kurs from the file and
      is never touched (A6);
    * for a trade that stores ADR-0015 settlement legs, the settlement
      amount, the security amount and the rate, read off the new cash net
      of the stored fees and taxes and converted as the import converts
      them (`Applier.derived_settlement_legs/4`), or at the stored rate when
      no stored hub rate converts the amount any more, so the settlement
      guard holds in the same write.

  Never the import hash, the id, the fees or the taxes.

  **How it writes** (`apply/3`). Each booking is changed by the ledger's own
  update, `Portfolixir.Ledger.update_transaction/3`, the path the API's
  `PATCH /api/v1/transactions/:id` takes: the public changeset (which
  refuses an import hash), the settlement guard on the changed cash, the
  audit journal with the before-image re-read under the row's lock
  (ADR-0017), and the derived-value bump inside the writing transaction
  (`Journal.record/3` → `Derived.Invalidation`, ADR-0039). The whole
  confirm is one transaction that first takes the apply's account-identity
  lock for the portfolio (`Lifecycle.AccountNames.lock_identity/2`), then
  lists the bookings again under their row locks, so it corrects what is
  stored when it runs and nothing a concurrent writer changed in between;
  a refused write rolls every change back. A second run finds nothing to
  correct.

  The ordinary apply is untouched by this module: a hash hit still inserts
  nothing and changes nothing (ADR-0050 §3, K8). Like the import, the
  correction is an operator action with no API route and no MCP tool
  (ADR-0029); every corrected value is read through the existing reads.
  """

  import Ecto.Query

  alias Portfolixir.Actor
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Imports.Applier
  alias Portfolixir.Imports.Entry
  alias Portfolixir.Imports.Preview
  alias Portfolixir.Input.BoundedDecimal
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Projection
  alias Portfolixir.Ledger.SettlementGuard
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Lifecycle.AccountNames
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Repo

  defmodule Item do
    @moduledoc """
    One booking the correction lists: the file's `row`, the `transaction` as
    stored (its security and cash accounts preloaded), the `changes` the
    confirm writes, its signed cash effect on its own cash account as stored
    (`booked`) and as the file states it (`stated`), their `difference`, and
    the change of every cash account it moves (`accounts`, each
    `%{account: %CashAccount{}, delta: Decimal}`).
    """

    @type t :: %__MODULE__{
            row: term(),
            transaction: %Portfolixir.Ledger.Transaction{},
            changes: %{optional(atom()) => Decimal.t()},
            booked: Decimal.t(),
            stated: Decimal.t(),
            difference: Decimal.t(),
            accounts: [%{account: %Portfolixir.Portfolios.CashAccount{}, delta: Decimal.t()}]
          }

    defstruct [:row, :transaction, :changes, :booked, :stated, :difference, accounts: []]
  end

  @trade_kinds ~w(buy sell)

  # The scale every amount column stores (ADR-0016 §2): a value is compared
  # as the column would keep it.
  @scale Transaction.amount_columns() |> Keyword.fetch!(:gross_amount) |> elem(1)

  @doc """
  The bookings of `portfolio_id` the file `preview` corrects, in file order,
  one per stored booking; `[]` without a portfolio. Read-only. With
  `lock: true` the bookings are read under the row lock the ledger's update
  takes (`FOR NO KEY UPDATE`), for the confirm that writes them.
  """
  @spec detect(Preview.t(), integer() | nil, keyword()) :: [Item.t()]
  def detect(preview, portfolio_id, opts \\ [])

  def detect(%Preview{}, nil, _opts), do: []

  def detect(%Preview{entries: entries, format: format}, portfolio_id, opts)
      when is_integer(portfolio_id) do
    flat_entries = Entry.flatten(entries)
    hashes = Applier.row_hashes(flat_entries, portfolio_id)
    stored = stored_by_hash(List.flatten(hashes), Keyword.get(opts, :lock, false))

    flat_entries
    |> Enum.zip(hashes)
    |> drop_parents_missing_a_refund(stored)
    |> Enum.flat_map(fn {entry, row_hashes} ->
      case Enum.find_value(row_hashes, &Map.get(stored, &1)) do
        %Transaction{} = transaction -> List.wrap(item(entry, transaction, format))
        nil -> []
      end
    end)
    |> Enum.uniq_by(& &1.transaction.id)
  end

  @doc """
  Corrects every booking of `portfolio_id` that `detect/3` lists for
  `preview`, under `actor`, and answers the corrected items as they were
  listed (each `transaction` as stored before, its `changes` as written).
  One transaction: the apply's account-identity lock first, then the
  bookings listed again under their row locks, then one
  `Ledger.update_transaction/3` per booking, each journaled with its
  before-image. A refused write rolls them all back and answers
  `{:error, %{row: row, reason: reason}}`. Nothing listed corrects nothing:
  `{:ok, []}`.
  """
  @spec apply(Actor.t(), Preview.t(), integer()) ::
          {:ok, [Item.t()]} | {:error, %{row: term(), reason: term()}}
  def apply(%Actor{} = actor, %Preview{} = preview, portfolio_id) when is_integer(portfolio_id) do
    Repo.transaction(
      fn ->
        :ok = AccountNames.lock_identity(portfolio_id)

        preview
        |> detect(portfolio_id, lock: true)
        |> Enum.reduce_while([], fn %Item{} = item, corrected ->
          case Ledger.update_transaction(actor, item.transaction, item.changes) do
            {:ok, _transaction} -> {:cont, [item | corrected]}
            {:error, reason} -> {:halt, {:error, %{row: item.row, reason: reason}}}
          end
        end)
        |> case do
          {:error, refusal} -> Repo.rollback(refusal)
          corrected -> Enum.reverse(corrected)
        end
      end,
      timeout: Applier.transaction_timeout()
    )
  end

  # A1: a parent's cash today is its cash cell less (or plus) the refund
  # split off it, so its correction takes out the refund only because the
  # refund is booked beside it. A row whose split-off refund is not stored
  # (deleted by hand since) is left out, with its refunds: corrected alone,
  # it would leave the cash below the stored state by that refund. `stored`
  # holds every hash of the file, a refund's among them.
  defp drop_parents_missing_a_refund(rows, stored) do
    rows
    |> Enum.chunk_while(
      [],
      fn
        {%Entry{companion_index: nil}, _hashes} = parent, [] ->
          {:cont, [parent]}

        {%Entry{companion_index: nil}, _hashes} = parent, group ->
          {:cont, Enum.reverse(group), [parent]}

        companion, group ->
          {:cont, [companion | group]}
      end,
      fn
        [] -> {:cont, []}
        group -> {:cont, Enum.reverse(group), []}
      end
    )
    |> Enum.flat_map(fn [_parent | refunds] = group ->
      if Enum.all?(refunds, &stored?(&1, stored)), do: group, else: []
    end)
  end

  defp stored?({_entry, hashes}, stored), do: Enum.any?(hashes, &Map.has_key?(stored, &1))

  defp stored_by_hash([], _lock?), do: %{}

  defp stored_by_hash(hashes, lock?) do
    from(t in Transaction,
      where: t.import_hash in ^hashes,
      preload: [:security, :cash_account, :counter_cash_account]
    )
    |> then(fn query -> if lock?, do: lock(query, "FOR NO KEY UPDATE"), else: query end)
    |> Repo.all()
    |> Map.new(&{&1.import_hash, &1})
  end

  # A booking that has become another kind since is no longer the row's.
  defp item(%Entry{kind: kind} = entry, %Transaction{type: kind} = transaction, format) do
    case changes(entry, transaction, format) do
      changes when map_size(changes) == 0 -> nil
      changes -> build_item(entry, transaction, changes)
    end
  end

  defp item(_entry, _transaction, _format), do: nil

  # The cash decides whether a booking is listed (§6, A6); the price of a
  # JSON trade and a trade's settlement legs follow it in the same write.
  defp changes(%Entry{} = entry, %Transaction{} = transaction, format) do
    case changed(transaction.gross_amount, entry.gross_amount) do
      nil ->
        %{}

      %Decimal{} = cash ->
        %{gross_amount: cash}
        |> put_price(entry, transaction, format)
        |> put_settlement_legs(transaction, cash)
    end
  end

  # The file's value as the column would store it, when it differs from the
  # stored one; `nil` when the row states none or they agree.
  defp changed(_stored, nil), do: nil

  defp changed(stored, %Decimal{} = stated) do
    stated = BoundedDecimal.round_to_scale(stated, @scale)
    unless match?(%Decimal{}, stored) and Decimal.equal?(stored, stated), do: stated
  end

  # A2, A6: a JSON purchase's or sale's price is derived from its cash; a
  # CSV row's price is Kurs from the file and is never touched.
  defp put_price(changes, %Entry{kind: kind, price: price}, transaction, :json)
       when kind in @trade_kinds do
    case changed(transaction.price, price) do
      nil -> changes
      %Decimal{} = new_price -> Map.put(changes, :price, new_price)
    end
  end

  defp put_price(changes, _entry, _transaction, _format), do: changes

  # ADR-0015, ADR-0033: a trade that stores settlement legs has them read
  # off its cash, so they move with it; a trade without them keeps none.
  defp put_settlement_legs(
         changes,
         %Transaction{type: type, settlement_amount: %Decimal{}} = transaction,
         cash
       )
       when type in @trade_kinds do
    settlement = SettlementGuard.trade_amount(type, cash, transaction.fees, transaction.taxes)

    legs =
      case settlement_legs(transaction, settlement) do
        legs when map_size(legs) > 0 -> legs
        _none -> legs_at_stored_rate(settlement, transaction.settlement_fx_rate)
      end

    Map.merge(changes, Map.new(legs, fn {field, value} -> {field, to_scale(value)} end))
  end

  defp put_settlement_legs(changes, _transaction, _cash), do: changes

  defp settlement_legs(
         %Transaction{security: %Security{currency_code: currency}} = transaction,
         settlement
       )
       when is_binary(currency) do
    Applier.derived_settlement_legs(
      settlement,
      transaction.currency_code,
      currency,
      transaction.date
    )
  end

  defp settlement_legs(_transaction, _settlement), do: %{}

  # No stored hub rate converts the amount any more: the rate the trade
  # stores carries the new trade amount into the security's currency.
  defp legs_at_stored_rate(settlement, %Decimal{} = rate) do
    if Decimal.compare(rate, 0) == :gt,
      do: %{
        settlement_amount: settlement,
        security_amount: Decimal.div(settlement, rate),
        settlement_fx_rate: rate
      },
      else: %{settlement_amount: settlement}
  end

  defp legs_at_stored_rate(settlement, _no_rate), do: %{settlement_amount: settlement}

  defp to_scale(%Decimal{} = value), do: BoundedDecimal.round_to_scale(value, @scale)

  defp build_item(%Entry{} = entry, %Transaction{} = transaction, changes) do
    corrected = struct(transaction, changes)
    booked = own_cash(transaction)
    stated = own_cash(corrected)

    %Item{
      row: entry.source_row,
      transaction: transaction,
      changes: changes,
      booked: booked,
      stated: stated,
      difference: Decimal.sub(stated, booked),
      accounts: account_deltas(transaction, corrected)
    }
  end

  # The booking's signed cash effect on its own cash account.
  defp own_cash(%Transaction{cash_account_id: account_id} = transaction) do
    transaction
    |> cash_legs()
    |> legs_of(account_id)
  end

  # How the correction moves each cash account the booking touches; an
  # account it leaves as it was is not named.
  defp account_deltas(%Transaction{} = before, %Transaction{} = corrected) do
    legs_before = cash_legs(before)
    legs_after = cash_legs(corrected)

    [before.cash_account, before.counter_cash_account]
    |> Enum.filter(&match?(%CashAccount{}, &1))
    |> Enum.uniq_by(& &1.id)
    |> Enum.flat_map(fn %CashAccount{id: id} = account ->
      delta = Decimal.sub(legs_of(legs_after, id), legs_of(legs_before, id))
      if Decimal.equal?(delta, 0), do: [], else: [%{account: account, delta: delta}]
    end)
  end

  defp cash_legs(%Transaction{} = transaction) do
    for {account_id, {:add, delta}} <- Projection.effects(transaction).cash,
        do: {account_id, delta}
  end

  defp legs_of(legs, account_id) do
    for({^account_id, delta} <- legs, do: delta)
    |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
  end
end
