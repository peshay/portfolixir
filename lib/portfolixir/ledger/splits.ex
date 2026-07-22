defmodule Portfolixir.Ledger.Splits do
  @moduledoc """
  The dedicated split booking flow (ADR-0028 §1, issue #589).

  To the operator a split is a security-level fact — "security X split R on
  date D" — but it is stored as one `split` transaction per portfolio holding
  a non-zero position at the effective date. `preview_split/1` shows that
  fan-out (quantity before/after the split and the resulting current position
  per portfolio, plus warnings) without writing anything; `book_split/2`
  inserts the whole row group atomically in one `Ecto.Multi`, each row
  journaled individually (ADR-0017) through the same
  `Ledger.create_transaction/2` path as every other ledger write.

  **Group identity is the natural key `(security_id, date, normalized
  ratio)`** — deliberately no grouping column and no migration (migrations
  are immutable and additive-only): the ratio pair is normalized to lowest
  terms at write time, so the rows of one fan-out are exactly the `split`
  rows sharing that key, and deleting the group means deleting those rows.

  Validation is deterministic and shell-friendly: a future effective date is
  rejected (`{:error, :future_effective_date}`), a security nobody holds at
  the effective date is rejected (`{:error, :no_position}`), and a retried
  booking hitting the partial unique index (one split per portfolio,
  security and day) returns `{:error, {:existing_split, transaction}}`
  naming the already-booked event. The preview additionally warns with
  `:effective_date_before_history` when the effective date predates the
  security's earliest transaction — an imported history may already carry
  post-split quantities, because Portfolio Performance's own split wizard
  rewrites history destructively (ADR-0028, Prior art).

  The PP round-trip marker mapping of ADR-0028 §1 is dropped (FR-29 rescope,
  see the ADR's dated 2026-07-22 note): no marker or export code exists here.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Positions
  alias Portfolixir.Ledger.Projection
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo

  @zero Decimal.new("0")

  @split_unique_index "transactions_one_split_per_portfolio_security_day_index"

  @doc """
  Previews the per-portfolio fan-out of a split without writing anything.

  `attrs` carries `security_id`, `date` (a `%Date{}` or ISO string) and the
  ratio as `ratio_numerator`/`ratio_denominator` (positive integers, string
  or atom keys). Returns `{:ok, preview}` with the normalized ratio, the
  warnings and one row per portfolio holding a non-zero position at the
  effective date or currently — each with `quantity_before` (entering the
  effective date), `quantity_after` (scaled, quantized once at volume scale
  6 like the fold, ADR-0028 §3) and the `current_position` the booking would
  result in. Errors: `:security_not_found`, `:invalid_date`,
  `:future_effective_date`, `:invalid_ratio`, `:identity_ratio`,
  `:no_position`.
  """
  def preview_split(attrs) when is_map(attrs) do
    with {:ok, params} <- validate(attrs) do
      build_preview(params)
    end
  end

  @doc """
  Books a split on behalf of `actor`: one `split` transaction per portfolio
  holding a non-zero position at the effective date, inserted atomically in
  one `Ecto.Multi` with one journal entry per row (ADR-0017). Validation
  matches `preview_split/1`; portfolios positioned only after the effective
  date get no row (there is nothing to scale), and no positioned portfolio
  at all returns `{:error, :no_position}`. A same-day conflict returns
  `{:error, {:existing_split, transaction}}` naming the existing event.

  Returns `{:ok, transactions}` sorted by portfolio id.
  """
  def book_split(%Actor{} = actor, attrs) when is_map(attrs) do
    with {:ok, params} <- validate(attrs),
         {:ok, positions} <- positioned_portfolios(params) do
      insert_rows(actor, params, positions)
    end
  end

  ## Validation

  defp validate(attrs) do
    with {:ok, security} <- fetch_security(attrs),
         {:ok, date} <- fetch_date(attrs),
         {:ok, ratio} <- fetch_ratio(attrs) do
      {:ok, %{security: security, date: date, ratio: ratio}}
    end
  end

  defp fetch_security(attrs) do
    case attrs |> get_attr(:security_id) |> Catalog.get_security() do
      %Security{} = security -> {:ok, security}
      nil -> {:error, :security_not_found}
    end
  end

  defp fetch_date(attrs) do
    with {:ok, date} <- parse_date(get_attr(attrs, :date)) do
      if Date.compare(date, Date.utc_today()) == :gt do
        {:error, :future_effective_date}
      else
        {:ok, date}
      end
    end
  end

  defp parse_date(%Date{} = date), do: {:ok, date}

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      _invalid -> {:error, :invalid_date}
    end
  end

  defp parse_date(_other), do: {:error, :invalid_date}

  # Normalized to lowest terms at write time (ADR-0028 §1): identity and
  # equality always use the canonical pair, and a pair that reduces to 1:1
  # scales nothing and is rejected as meaningless.
  defp fetch_ratio(attrs) do
    numerator = attrs |> get_attr(:ratio_numerator) |> parse_positive_integer()
    denominator = attrs |> get_attr(:ratio_denominator) |> parse_positive_integer()

    case {numerator, denominator} do
      {p, q} when is_integer(p) and is_integer(q) -> normalize_ratio(p, q)
      _invalid -> {:error, :invalid_ratio}
    end
  end

  defp normalize_ratio(numerator, denominator) do
    gcd = Integer.gcd(numerator, denominator)

    case {div(numerator, gcd), div(denominator, gcd)} do
      {1, 1} -> {:error, :identity_ratio}
      pair -> {:ok, pair}
    end
  end

  defp parse_positive_integer(value) when is_integer(value) and value > 0, do: value

  defp parse_positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _invalid -> nil
    end
  end

  defp parse_positive_integer(_other), do: nil

  ## Preview

  defp build_preview(%{security: security, date: date, ratio: {p, q}} = params) do
    transactions = Ledger.list_transactions_for_security(security.id)
    accounts = Projection.account_portfolios(transactions)
    before_by_account = positions_before(transactions, date)
    before = sum_by_portfolio(before_by_account, accounts)
    scaled = before_by_account |> scale_positions(params) |> sum_by_portfolio(accounts)
    current = simulate_current(transactions, params, positioned_ids(before), accounts)

    case preview_rows(transactions, before, scaled, current) do
      [] ->
        {:error, :no_position}

      rows ->
        {:ok,
         %{
           security_id: security.id,
           date: date,
           ratio_numerator: p,
           ratio_denominator: q,
           warnings: warnings(transactions, date),
           portfolios: rows
         }}
    end
  end

  # The split applies first within its day (start-of-day, ADR-0028 §3), so
  # the position it scales — and the one shown as "before" — derives from
  # the transactions dated strictly before the effective date.
  defp positions_before(transactions, date) do
    transactions
    |> Enum.filter(&(Date.compare(&1.date, date) == :lt))
    |> Positions.calculate()
  end

  defp scale_positions(by_account, %{ratio: ratio}) do
    Map.new(by_account, fn {key, quantity} ->
      {key, Projection.scale_quantity(quantity, ratio)}
    end)
  end

  defp sum_by_portfolio(by_account, accounts) do
    Enum.reduce(by_account, %{}, fn {{account_id, _security_id}, quantity}, acc ->
      case Map.get(accounts, account_id) do
        nil -> acc
        portfolio_id -> Map.update(acc, portfolio_id, quantity, &Decimal.add(&1, quantity))
      end
    end)
  end

  defp positioned_ids(by_portfolio) do
    for {portfolio_id, quantity} <- by_portfolio,
        not Decimal.equal?(quantity, @zero),
        do: portfolio_id
  end

  # The resulting current position replays the real transactions plus one
  # synthetic split row per portfolio the booking would create, so nested
  # cases (later trades, further splits) fold exactly like the ledger will
  # after booking.
  defp simulate_current(transactions, params, booked_portfolio_ids, accounts) do
    synthetic = Enum.map(booked_portfolio_ids, &synthetic_split(params, &1))

    (transactions ++ synthetic)
    |> Positions.calculate()
    |> sum_by_portfolio(accounts)
  end

  defp synthetic_split(%{security: security, date: date, ratio: {p, q}}, portfolio_id) do
    %{
      type: "split",
      date: date,
      portfolio_id: portfolio_id,
      security_id: security.id,
      split_ratio_numerator: p,
      split_ratio_denominator: q
    }
  end

  # One row per portfolio positioned at the effective date (the bookable
  # set) or currently — the latter so a preview against an already-adjusted
  # history (before 0 → after 0, current unchanged) stays visible next to
  # the before-history warning instead of erroring opaquely.
  defp preview_rows(transactions, before, scaled, current) do
    names = portfolio_names(transactions)

    (positioned_ids(before) ++ positioned_ids(current))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(fn portfolio_id ->
      %{
        portfolio_id: portfolio_id,
        portfolio_name: Map.get(names, portfolio_id),
        quantity_before: Map.get(before, portfolio_id, @zero),
        quantity_after: Map.get(scaled, portfolio_id, @zero),
        current_position: Map.get(current, portfolio_id, @zero)
      }
    end)
  end

  defp portfolio_names(transactions) do
    for %{portfolio: %{id: id, name: name}} <- transactions, into: %{}, do: {id, name}
  end

  defp warnings(transactions, date) do
    case transactions do
      [earliest | _rest] when earliest.date != nil ->
        if Date.compare(date, earliest.date) == :lt,
          do: [:effective_date_before_history],
          else: []

      _empty ->
        []
    end
  end

  ## Booking

  defp positioned_portfolios(%{security: security, date: date}) do
    transactions = Ledger.list_transactions_for_security(security.id)
    accounts = Projection.account_portfolios(transactions)

    transactions
    |> positions_before(date)
    |> sum_by_portfolio(accounts)
    |> positioned_ids()
    |> Enum.sort()
    |> case do
      [] -> {:error, :no_position}
      portfolio_ids -> {:ok, portfolio_ids}
    end
  end

  # One Multi, one insert-plus-journal per positioned portfolio: each step
  # runs the regular `Ledger.create_transaction/2` (validation + journal in a
  # nested transaction), so a failure on any row rolls the whole group back.
  defp insert_rows(actor, params, portfolio_ids) do
    portfolio_ids
    |> Enum.reduce(Multi.new(), fn portfolio_id, multi ->
      Multi.run(multi, {:split, portfolio_id}, fn _repo, _changes ->
        Ledger.create_transaction(actor, row_attrs(params, portfolio_id))
      end)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, changes} ->
        {:ok, Enum.map(portfolio_ids, &Map.fetch!(changes, {:split, &1}))}

      {:error, {:split, portfolio_id}, %Ecto.Changeset{} = changeset, _changes} ->
        conflict_or_changeset_error(params, portfolio_id, changeset)
    end
  end

  defp row_attrs(%{security: security, date: date, ratio: {p, q}}, portfolio_id) do
    %{
      type: "split",
      portfolio_id: portfolio_id,
      security_id: security.id,
      date: date,
      # A split has no cash leg; the row's currency is the security's own.
      currency_code: security.currency_code,
      split_ratio_numerator: p,
      split_ratio_denominator: q
    }
  end

  # A violation of the partial unique index (one split per portfolio,
  # security and day — write idempotency for retried timeouts, ADR-0028 §1)
  # is answered by naming the existing event; any other changeset error
  # surfaces unchanged.
  defp conflict_or_changeset_error(params, portfolio_id, changeset) do
    with true <- split_conflict?(changeset),
         %Transaction{} = existing <- existing_split(params, portfolio_id) do
      {:error, {:existing_split, existing}}
    else
      _not_a_conflict -> {:error, changeset}
    end
  end

  defp split_conflict?(changeset) do
    Enum.any?(changeset.errors, fn
      {:date, {_message, opts}} -> opts[:constraint_name] == @split_unique_index
      _other -> false
    end)
  end

  defp existing_split(%{security: security, date: date}, portfolio_id) do
    Repo.one(
      from(t in Transaction,
        where:
          t.type == "split" and t.portfolio_id == ^portfolio_id and
            t.security_id == ^security.id and t.date == ^date,
        preload: [:portfolio]
      )
    )
  end

  defp get_attr(attrs, field) do
    case Map.get(attrs, field) do
      nil -> Map.get(attrs, Atom.to_string(field))
      value -> value
    end
  end
end
