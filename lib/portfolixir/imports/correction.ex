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
  alias Portfolixir.Imports
  alias Portfolixir.Imports.Applier
  alias Portfolixir.Imports.DedupKey
  alias Portfolixir.Imports.Entry
  alias Portfolixir.Imports.Preview
  alias Portfolixir.Input.BoundedDecimal
  alias Portfolixir.Journal.Entry, as: JournalEntry
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Projection
  alias Portfolixir.Ledger.SettlementGuard
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Lifecycle.AccountNames
  alias Portfolixir.Lifecycle.RetiredImportHash
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

    defstruct [
      :row,
      :transaction,
      :changes,
      :booked,
      :stated,
      :difference,
      :edited_on,
      :matches,
      :claimed_by,
      :refusal,
      accounts: [],
      state: :confirm,
      match: :hash
    ]
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

  def detect(%Preview{entries: entries, format: format} = preview, portfolio_id, opts)
      when is_integer(portfolio_id) do
    flat_entries = Entry.flatten(entries)
    hashes = Applier.row_hashes(flat_entries, portfolio_id)
    stored = stored_by_hash(List.flatten(hashes), Keyword.get(opts, :lock, false))

    lock? = Keyword.get(opts, :lock, false)

    hash_items =
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

    keys =
      Keyword.get_lazy(opts, :keys, fn ->
        if Keyword.get(opts, :dry_run, true),
          do: Applier.economic_keys(preview, portfolio_id),
          else: :error
      end)

    figure_items =
      figure_items(flat_entries, hashes, stored, keys, %{
        portfolio_id: portfolio_id,
        format: format,
        lock?: lock?
      })

    (hash_items ++ refused_items(preview, portfolio_id, lock?))
    |> Enum.uniq_by(& &1.transaction.id)
    |> Kernel.++(figure_items)
    |> mark_edited()
    |> Enum.sort_by(&row_order/1)
  end

  # A11 (#1194): the figures of a row whose journal (ADR-0017) records an
  # edit since its import. A booking counts as edited when an update by an
  # actor other than the importer (`import_session`) and the correction
  # (`Imports.correction_actor/0`) changed one of its figures: the cash,
  # the price, the quantity, the fees or the taxes. A merge's re-pointing,
  # the settlement legs a backfill writes under a system actor, and a note
  # change none of them. Such a booking is named, with the date of its last
  # edit, and the confirm leaves it as the operator made it. It wins over a
  # refusal: a refused booking the operator put right by hand reads as
  # edited (board 07, found while drawing 4).
  @figure_fields ~w(gross_amount price quantity fees taxes)

  defp mark_edited([]), do: []

  defp mark_edited(items) do
    ids = Enum.map(items, &to_string(&1.transaction.id))

    edited_on =
      from(e in JournalEntry,
        where:
          e.resource_type == "transaction" and e.resource_id in ^ids and
            e.operation == :update and is_nil(e.scenario_id)
      )
      |> Repo.all()
      |> Enum.filter(&hand_edit?/1)
      |> Enum.group_by(& &1.resource_id, &DateTime.to_date(&1.inserted_at))
      |> Map.new(fn {id, dates} -> {id, Enum.max(dates, Date)} end)

    Enum.map(items, fn %Item{} = item ->
      case Map.get(edited_on, to_string(item.transaction.id)) do
        %Date{} = date when item.state in [:confirm, :refused] ->
          %{item | state: :edited, edited_on: date}

        _not_edited ->
          item
      end
    end)
  end

  defp hand_edit?(%JournalEntry{actor_type: :import_session}), do: false

  defp hand_edit?(%JournalEntry{actor_type: type, actor_label: label} = entry) do
    {correction_type, correction_label} = Actor.to_columns(Imports.correction_actor())

    not (Atom.to_string(type) == correction_type and label == correction_label) and
      Enum.any?(@figure_fields, &figure_changed?(entry.before, entry.after, &1))
  end

  defp figure_changed?(before, after_, field) when is_map(before) and is_map(after_),
    do: not same_figure?(Map.get(before, field), Map.get(after_, field))

  defp figure_changed?(_before, _after, _field), do: false

  defp same_figure?(same, same), do: true

  defp same_figure?(a, b) when is_binary(a) and is_binary(b),
    do: Decimal.equal?(Decimal.new(a), Decimal.new(b))

  defp same_figure?(_a, _b), do: false

  # A12 (#1205): a row no stored content hash holds, which the economic
  # layer matches under A4's old reading — a drifted re-export (a time of
  # day moved, an ISIN added, an account renamed) of a row booked before
  # A1. The keys are the ones the apply's dry run reaches for the row, its
  # accounts and security resolved under the preview's prefill
  # (`Applier.economic_keys/2`); a row the booked reading's key matches is
  # booked as the file reads it, and is not listed. The line carries a
  # confirm only when exactly one stored booking of the portfolio holds the
  # old key and no other row of the file claims it: a row with a hash hit
  # claims the booking it hits, and a row without one every booking either
  # of its keys matches. Otherwise it is listed without one, with the count
  # of the twins or the row that claims the booking: the economic key cannot
  # tell two genuine twins apart, and correcting the wrong one is worse than
  # correcting none. A row whose split-off refund is not stored beside it,
  # by its hash or its economic key, is not listed (A6's rule).
  defp figure_items(_flat, _hashes, _stored, :error, _context), do: []

  defp figure_items(flat_entries, hashes, stored, {:ok, keys}, context) do
    hits =
      Enum.zip_with(flat_entries, hashes, fn entry, row_hashes ->
        {entry, Enum.find_value(row_hashes, &Map.get(stored, &1))}
      end)

    rows =
      for {%Entry{companion_index: nil} = entry, nil} <- hits,
          %{} = row_keys <- [Map.get(keys, {entry.source_row, nil})],
          do: {entry, row_keys}

    if rows == [] do
      []
    else
      by_key = context |> portfolio_bookings() |> Enum.group_by(&DedupKey.of/1)

      claims =
        Enum.map(hits, fn
          {entry, %Transaction{id: id}} ->
            {entry.source_row, MapSet.new([id])}

          {entry, nil} ->
            row_keys = Map.get(keys, {entry.source_row, entry.companion_index}, %{})

            {entry.source_row,
             [row_keys[:booked], row_keys[:old]]
             |> Enum.flat_map(&Map.get(by_key, &1, []))
             |> MapSet.new(& &1.id)}
        end)

      hash_claimed = for {_entry, %Transaction{id: id}} <- hits, into: MapSet.new(), do: id

      context = Map.merge(context, %{by_key: by_key, claims: claims, hits: hits, keys: keys})

      Enum.flat_map(rows, fn {entry, row_keys} ->
        booked =
          by_key
          |> Map.get(row_keys.booked, [])
          |> Enum.reject(&MapSet.member?(hash_claimed, &1.id))

        if booked == [] and row_keys.old,
          do:
            figure_line(entry, Enum.sort_by(Map.get(by_key, row_keys.old, []), & &1.id), context),
          else: []
      end)
    end
  end

  defp figure_line(_entry, [], _context), do: []

  defp figure_line(entry, [%Transaction{} = transaction], context) do
    claimant = claimant(entry, transaction, context.claims)

    case item(entry, transaction, context.format) do
      nil ->
        []

      %Item{} = line when not is_nil(claimant) ->
        [%{line | match: :figures, state: :claimed, claimed_by: claimant}]

      %Item{} = line ->
        if refunds_beside?(entry, context), do: [%{line | match: :figures}], else: []
    end
  end

  defp figure_line(entry, [transaction | _] = twins, context) do
    case item(entry, transaction, context.format) do
      nil -> []
      %Item{} = line -> [%{line | match: :figures, state: :twin, matches: length(twins)}]
    end
  end

  # The first other row of the file that claims the booking, or `nil`.
  defp claimant(%Entry{source_row: row}, %Transaction{id: id}, claims) do
    Enum.find_value(claims, fn {claiming_row, ids} ->
      if claiming_row != row and MapSet.member?(ids, id), do: claiming_row
    end)
  end

  # Every refund split off the row is stored: by its own hash, or by its
  # economic key as the apply finds it.
  defp refunds_beside?(%Entry{source_row: row}, context) do
    context.hits
    |> Enum.filter(fn {entry, _hit} -> entry.source_row == row and entry.companion_index end)
    |> Enum.all?(fn
      {_entry, %Transaction{}} ->
        true

      {entry, nil} ->
        case Map.get(context.keys, {row, entry.companion_index}) do
          %{booked: key} -> Map.has_key?(context.by_key, key)
          nil -> false
        end
    end)
  end

  defp portfolio_bookings(%{portfolio_id: portfolio_id, lock?: lock?}) do
    from(t in Transaction,
      where: t.portfolio_id == ^portfolio_id,
      preload: [:security, :cash_account, :counter_cash_account]
    )
    |> then(fn query -> if lock?, do: lock(query, "FOR NO KEY UPDATE"), else: query end)
    |> Repo.all()
  end

  # File order: a row's number, a refused row among the others.
  defp row_order(%Item{row: row}) when is_integer(row), do: {0, row}
  defp row_order(%Item{row: row}), do: {1, to_string(row)}

  @doc """
  The lines of `items` the confirm writes: those in the state `:confirm`.
  Every other line is listed and stays as it is (ADR-0053 A10–A12).
  """
  @spec confirmable([Item.t()]) :: [Item.t()]
  def confirmable(items), do: Enum.filter(items, &(&1.state == :confirm))

  # A10 (#1193): a row the preview refuses (A5's credit that nets to
  # nothing, and A8's refund beside a delivery or a transfer, kept in
  # `refused_credits` with their would-be entries) whose would-be booking a
  # live transaction holds by its content hash. It is listed, not
  # correctable here: per cash account the row moves, the booking and the
  # refund stored beside it (found by the refund's hash with its row),
  # against the row's cash cell, which in Portfolio Performance is all the
  # row moves. The correction never deletes a booking, and no cash it
  # could write makes such a booking right, so the line carries no confirm.
  # A hash a merge retired has no live booking to list.
  defp refused_items(%Preview{refused_credits: refused}, portfolio_id, lock?) do
    Enum.flat_map(refused, fn %{row: row, entry: %Entry{} = entry} ->
      flat = Entry.flatten([entry])
      [parent_hashes | refund_hashes] = Applier.row_hashes(flat, portfolio_id)
      stored = stored_by_hash(List.flatten([parent_hashes | refund_hashes]), lock?)

      case Enum.find_value(parent_hashes, &Map.get(stored, &1)) do
        %Transaction{} = transaction ->
          refunds =
            Enum.flat_map(refund_hashes, &List.wrap(Enum.find_value(&1, fn h -> stored[h] end)))

          [refused_item(row, entry, transaction, refunds)]

        nil ->
          []
      end
    end)
  end

  @credit_kinds ~w(sell dividend interest deposit tax_refund)

  defp refused_item(row, %Entry{} = entry, %Transaction{} = transaction, refunds) do
    refund = entry.companion_entries |> Enum.map(& &1.gross_amount) |> sum()
    cell = cash_cell(entry, refund)

    stored_legs = Enum.flat_map([transaction | refunds], &cash_legs/1)

    stated_legs =
      if cell, do: cash_legs(%{transaction | gross_amount: cell}), else: []

    accounts =
      [
        transaction.cash_account,
        transaction.counter_cash_account | Enum.map(refunds, & &1.cash_account)
      ]
      |> Enum.filter(&match?(%CashAccount{}, &1))
      |> Enum.uniq_by(& &1.id)
      |> Enum.map(fn %CashAccount{id: id} = account ->
        booked = legs_of(stored_legs, id)
        stated = legs_of(stated_legs, id)
        %{account: account, booked: booked, stated: stated, delta: Decimal.sub(stated, booked)}
      end)

    own = Enum.find(accounts, &(&1.account.id == transaction.cash_account_id)) || hd(accounts)

    %Item{
      row: row,
      transaction: transaction,
      changes: %{},
      booked: own.booked,
      stated: own.stated,
      difference: own.delta,
      accounts: accounts,
      state: :refused,
      refusal: %{
        kind: transaction.type,
        refund: refund,
        rest: entry.gross_amount,
        fees: entry.fees || Decimal.new(0),
        # The cash a by-hand booking of the row takes, its fees booked as a
        # fee of their own and the refund already beside it: the cash cell
        # plus the fees less the refund, plus the positive taxes.
        gross: by_hand_gross(entry, cell, refund)
      }
    }
  end

  # The row's cash cell: its own booking's cash and the refunds split off
  # it together (A1), a credit's less, a debit's plus; `nil` for a row that
  # moves no cash (a delivery).
  defp cash_cell(%Entry{gross_amount: nil}, _refund), do: nil

  defp cash_cell(%Entry{kind: kind, gross_amount: gross}, refund) when kind in @credit_kinds,
    do: Decimal.add(gross, refund)

  defp cash_cell(%Entry{gross_amount: gross}, refund), do: Decimal.sub(gross, refund)

  defp by_hand_gross(%Entry{kind: "sell"} = entry, %Decimal{} = cell, refund) do
    cell
    |> Decimal.add(entry.fees || Decimal.new(0))
    |> Decimal.add(entry.taxes || Decimal.new(0))
    |> Decimal.sub(refund)
  end

  defp by_hand_gross(_entry, cell, _refund), do: cell

  defp sum(values),
    do: Enum.reduce(values, Decimal.new(0), &Decimal.add(&1 || Decimal.new(0), &2))

  @doc """
  The credit rows of `preview` that ADR-0053 A5 refuses (their own booking
  would credit 0 or less) and whose would-be booking the stored history of
  `portfolio_id` already holds, by its content hash, as `%{row =>
  message}`, each with the message the preview shows for it instead of the
  refusal's remedy (#1118). Such a row was imported under an older reading.
  The history holds a hash as the apply's first check reads it (ADR-0050
  §3; the amendment of 2026-10-07, point 1): a live transaction holds it,
  or it is retired because a merge removed its row. It is not listed by
  `detect/3`: its cash would be 0 or less, which no write can store, and
  how it is corrected is #1193. Read-only; `%{}` without a portfolio.
  """
  @spec stored_refusals(Preview.t(), integer() | nil) :: %{pos_integer() => String.t()}
  def stored_refusals(%Preview{}, nil), do: %{}
  def stored_refusals(%Preview{refused_credits: []}, _portfolio_id), do: %{}

  def stored_refusals(%Preview{refused_credits: refused}, portfolio_id)
      when is_integer(portfolio_id) do
    hashes =
      refused
      |> Enum.map(&%{&1.entry | companion_entries: []})
      |> Applier.row_hashes(portfolio_id)

    flat = List.flatten(hashes)
    stored = stored_by_hash(flat, false)
    retired = retired_hashes(flat)

    refused
    |> Enum.zip(hashes)
    |> Enum.filter(fn {_refused, row_hashes} ->
      Enum.any?(row_hashes, &(Map.has_key?(stored, &1) or MapSet.member?(retired, &1)))
    end)
    |> Map.new(fn {%{row: row, message: message}, _row_hashes} -> {row, message} end)
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
    # A12: the dry run that resolves each row's economic keys rolls back, so
    # it runs before the confirm's transaction; the rows are judged again
    # against the bookings under the confirm's locks.
    keys = Applier.economic_keys(preview, portfolio_id)

    Repo.transaction(
      fn ->
        :ok = AccountNames.lock_identity(portfolio_id)

        preview
        |> detect(portfolio_id, lock: true, keys: keys)
        |> confirmable()
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

  defp retired_hashes(hashes) do
    from(r in RetiredImportHash, where: r.import_hash in ^hashes, select: r.import_hash)
    |> Repo.all()
    |> MapSet.new()
  end

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

  # A booking is listed when its cash differs (§6, A6), and a JSON
  # purchase or sale also when its price differs, each compared at its
  # column's scale (A11, #1194): a JSON price is derived from the cash, so a
  # trade whose cash agrees while its price does not is listed on its price,
  # and the confirm writes the price alone. A trade's settlement legs follow
  # a changed cash in the same write.
  defp changes(%Entry{} = entry, %Transaction{} = transaction, format) do
    price_changes = put_price(%{}, entry, transaction, format)

    case changed(transaction.gross_amount, entry.gross_amount) do
      nil ->
        price_changes

      %Decimal{} = cash ->
        price_changes
        |> Map.put(:gross_amount, cash)
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
