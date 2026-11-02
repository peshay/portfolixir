defmodule Portfolixir.Imports.RefusedMatch do
  @moduledoc """
  The stored bookings that a refused row's remedy asks for (#1219; board
  ux-design-2026-11-01-sprint22/03 ③; ADR-0053's note of 2026-11-01).

  A row ADR-0053 A8 or A9 refuses carries a remedy, "book it by hand". Two
  paths left that remedy showing for a booking that already exists, one
  confirm away from booking it twice: the operator followed it after an
  earlier drop (a hand booking carries no import hash), or the row was
  imported before and its re-export drifted in a hashed field (a time of
  day, an added ISIN), so no hash finds it. A refused row is no entry of
  the apply's run, so the dry run's economic keys (A12) never reach it.

  Here the row's remedy booking is matched by its figures on the economic
  layer (`Portfolixir.Imports.DedupKey.of/1`) against every stored booking
  of the portfolio, imported or entered by hand:

    * the row's names resolve read-only, as the apply's prefill resolves
      them: a cash account or depot by its live name, then a former one
      (`Lifecycle.AccountNames.resolve/2`), a security by the matching
      ladder (`SecurityResolver.resolve/2`). A name that resolves to
      nothing, or to more than one record, matches nothing;
    * the key compares the portfolio, the kind, the date, the security and
      the accounts the kind books on, and the quantity. Its price, fees and
      taxes are left out, because the remedy itself changes how the row
      splits its cash among them (A9 books the net fee, or none);
    * the cash compares beside the key: what the stored booking moves on
      each cash account (`Ledger.Projection.effects/1`) equals the row's
      cash cell, the cash Portfolio Performance shows and every A8 and A9
      remedy books (debited, credited, or sent from one account to the
      other); a delivery or a security transfer moves none;
    * a booking that a row of the file holds by its content hash is that
      row's, never the refused row's.

  A5's rows are not matched: their remedy books a cash the file does not
  state (the row's own booking would credit 0 or less), so a match by the
  remaining figures could name another booking of the same day (#1219's
  "what would change the answer"); they keep their remedy.

  Read-only. Answers `%{row => [%Transaction{}]}`, each list ordered by id,
  for the refused rows of the preview not in `skip` (the rows whose
  content hash the history already holds, which say so by themselves).
  """

  import Ecto.Query

  alias Portfolixir.Imports.Applier
  alias Portfolixir.Imports.DedupKey
  alias Portfolixir.Imports.Entry
  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Imports.Preview
  alias Portfolixir.Imports.SecurityResolver
  alias Portfolixir.Ledger.Projection
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Lifecycle.AccountNames
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.SecuritiesAccount
  alias Portfolixir.Repo

  @matched_rules [:a8, :a9]

  # What the ledger books each kind on (`Ledger.Transaction`'s per-kind
  # required fields): the key compares these and nothing a hand booking
  # may leave out, such as a dividend's depot.
  @booked_on %{
    "buy" => [:security, :depot, :cash, :quantity],
    "sell" => [:security, :depot, :cash, :quantity],
    "dividend" => [:security, :cash],
    "interest" => [:cash],
    "deposit" => [:cash],
    "removal" => [:cash],
    "fee" => [:cash],
    "tax" => [:cash],
    "tax_refund" => [:cash],
    "cash_transfer" => [:cash, :counter_cash],
    "inbound_delivery" => [:security, :depot, :quantity],
    "outbound_delivery" => [:security, :depot, :quantity],
    "security_transfer" => [:security, :depot, :counter_depot, :quantity]
  }

  @credit_kinds ~w(sell dividend interest deposit tax_refund)

  @spec booked(Preview.t(), integer() | nil, MapSet.t()) :: %{
          pos_integer() => [Transaction.t()]
        }
  def booked(%Preview{}, nil, _skip), do: %{}

  def booked(%Preview{refused_credits: refused} = preview, portfolio_id, skip)
      when is_integer(portfolio_id) do
    case Enum.filter(refused, &(&1.rule in @matched_rules and not MapSet.member?(skip, &1.row))) do
      [] -> %{}
      rows -> match(rows, preview, portfolio_id)
    end
  end

  defp match(rows, preview, portfolio_id) do
    context = %{
      portfolio_id: portfolio_id,
      cash: AccountNames.index(CashAccount, portfolio_id),
      depots: AccountNames.index(SecuritiesAccount, portfolio_id),
      securities: SecurityResolver.ladder_index(),
      claimed: claimed_ids(preview, portfolio_id)
    }

    for %{row: row, entry: %Entry{} = entry} <- rows,
        {:ok, ids} <- [resolve(entry, context)],
        [_ | _] = bookings <- [bookings(entry, ids, context)],
        into: %{},
        do: {row, bookings}
  end

  # The bookings the file's own entries hold by their content hashes.
  defp claimed_ids(%Preview{entries: entries}, portfolio_id) do
    case entries |> Entry.flatten() |> Applier.row_hashes(portfolio_id) |> List.flatten() do
      [] ->
        MapSet.new()

      hashes ->
        from(t in Transaction, where: t.import_hash in ^hashes, select: t.id)
        |> Repo.all()
        |> MapSet.new()
    end
  end

  defp resolve(%Entry{kind: kind} = entry, context) do
    @booked_on
    |> Map.get(kind, [])
    |> Enum.reduce_while({:ok, %{}}, fn field, {:ok, ids} ->
      case resolve_field(field, entry, context) do
        {:ok, id} -> {:cont, {:ok, Map.put(ids, field, id)}}
        :none -> {:halt, :none}
      end
    end)
  end

  defp resolve_field(:quantity, %Entry{quantity: %Decimal{} = quantity}, _context),
    do: {:ok, quantity}

  defp resolve_field(:quantity, _entry, _context), do: :none

  defp resolve_field(:security, %Entry{security: %{}} = entry, context) do
    case SecurityResolver.resolve(SecurityResolver.effective_ref(entry), context.securities) do
      {:match, %{id: id}, _tier} -> {:ok, id}
      _create_or_conflict -> :none
    end
  end

  defp resolve_field(:security, _entry, _context), do: :none
  defp resolve_field(:cash, entry, context), do: name(context.cash, entry.pp_account_name)

  defp resolve_field(:counter_cash, entry, context),
    do: name(context.cash, entry.pp_counter_account_name)

  defp resolve_field(:depot, entry, context), do: name(context.depots, entry.pp_portfolio_name)

  defp resolve_field(:counter_depot, entry, context),
    do: name(context.depots, entry.pp_counter_portfolio_name)

  defp name(index, name) when is_binary(name) do
    case AccountNames.resolve(index, name) do
      {:ok, id, _tier} -> {:ok, id}
      _none_or_ambiguous -> :none
    end
  end

  defp name(_index, _name), do: :none

  defp bookings(%Entry{} = entry, ids, context) do
    key = DedupKey.of(projected(entry, ids, context.portfolio_id))
    legs = expected_legs(entry, ids)

    from(t in Transaction,
      where:
        t.portfolio_id == ^context.portfolio_id and t.type == ^entry.kind and
          t.date == ^entry.date,
      order_by: :id,
      preload: [
        :security,
        :cash_account,
        :counter_cash_account,
        :securities_account,
        :counter_securities_account
      ]
    )
    |> Repo.all()
    |> Enum.filter(fn %Transaction{} = transaction ->
      not MapSet.member?(context.claimed, transaction.id) and
        DedupKey.of(stored(transaction, entry.kind)) == key and
        same_legs?(cash_legs(transaction), legs)
    end)
  end

  # The key's fields: the kind's accounts and security, its quantity, and
  # nothing of how its cash splits into price, fees and taxes.
  defp projected(%Entry{} = entry, ids, portfolio_id) do
    %{
      portfolio_id: portfolio_id,
      type: entry.kind,
      date: entry.date,
      security_id: ids[:security],
      securities_account_id: ids[:depot],
      counter_securities_account_id: ids[:counter_depot],
      cash_account_id: ids[:cash],
      counter_cash_account_id: ids[:counter_cash],
      quantity: ids[:quantity]
    }
  end

  defp stored(%Transaction{} = transaction, kind) do
    fields = Map.get(@booked_on, kind, [])

    %{
      portfolio_id: transaction.portfolio_id,
      type: transaction.type,
      date: transaction.date,
      security_id: if(:security in fields, do: transaction.security_id),
      securities_account_id: if(:depot in fields, do: transaction.securities_account_id),
      counter_securities_account_id:
        if(:counter_depot in fields, do: transaction.counter_securities_account_id),
      cash_account_id: if(:cash in fields, do: transaction.cash_account_id),
      counter_cash_account_id:
        if(:counter_cash in fields, do: transaction.counter_cash_account_id),
      quantity: if(:quantity in fields, do: transaction.quantity)
    }
  end

  # What the remedy's booking moves on each cash account: the row's cash
  # cell, which holds any refund split off it (A1): a credit's own booking
  # plus the refund, a debit's less it.
  defp expected_legs(%Entry{gross_amount: nil}, _ids), do: []

  defp expected_legs(%Entry{kind: "cash_transfer"} = entry, ids) do
    cell = cash_cell(entry)
    [{ids.cash, Decimal.negate(cell)}, {ids.counter_cash, cell}]
  end

  defp expected_legs(%Entry{kind: kind} = entry, ids) do
    cell = cash_cell(entry)

    case PortfolioPerformance.direction(kind, nil) do
      :credit -> [{ids.cash, cell}]
      :debit -> [{ids.cash, Decimal.negate(cell)}]
      nil -> []
    end
  end

  @doc """
  A row's cash as the file states it (ADR-0053 A1): its own booking with any
  refund split off it folded back in, a credit's plus the refund, a debit's
  less it. The entry carries its refunds in `companion_entries`, as the
  parser gives them, before `Entry.flatten/1`.
  """
  @spec cash_cell(Entry.t()) :: Decimal.t()
  def cash_cell(%Entry{kind: kind, gross_amount: gross} = entry) do
    refund =
      entry.companion_entries
      |> Enum.map(& &1.gross_amount)
      |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

    if kind in @credit_kinds, do: Decimal.add(gross, refund), else: Decimal.sub(gross, refund)
  end

  defp cash_legs(%Transaction{} = transaction) do
    for {account_id, {:add, delta}} <- Projection.effects(transaction).cash,
        do: {account_id, delta}
  end

  defp same_legs?(stored, expected) do
    length(stored) == length(expected) and
      stored
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.zip(Enum.sort_by(expected, &elem(&1, 0)))
      |> Enum.all?(fn {{a, x}, {b, y}} -> a == b and Decimal.equal?(x, y) end)
  end
end
