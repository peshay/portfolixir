defmodule Portfolixir.Imports.Applier do
  @moduledoc """
  Turns a parsed `Portfolixir.Imports.Preview` into committed ledger
  rows.

  All work happens inside a single `Repo.transaction/1`. If any entry
  hits a real error (invalid changeset, FK violation, …) the whole
  transaction rolls back and nothing is created.

  Idempotency: each entry receives a deterministic SHA-256
  `import_hash` derived from its stable identity (kind, date, security
  ISIN-or-name, quantity, gross amount, PP account names, target
  portfolio id). The `transactions.import_hash` unique partial index
  rejects re-inserts; the applier counts those as `skipped_duplicates`
  and continues.

  Scope of this story (#5):

  - Resolves securities by ISIN (preferred) or by (name, currency).
    Missing securities are created from the entry's `security` ref.
  - Resolves cash accounts and depots by name *within the chosen
    portfolio*. Missing ones are created.
  - Inserts one ledger row per entry, branching by kind.
  - Skips degenerate rows that can never form a valid transaction — a
    cash kind with a zero or missing gross_amount (e.g. a 0 EUR tax
    line) — recording each in `skipped_entries` with its row and a
    reason instead of aborting the whole import (#482). Genuine
    changeset/FK errors still roll the whole transaction back.
  - Reports created/skipped/error counts in the final result.

  Out of scope (follow-ups): user-driven security match overrides
  (Story 4 UI), per-entry depot/cash override per pp-account-pair.
  """

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Imports.Entry
  alias Portfolixir.Imports.Preview
  alias Portfolixir.Journal
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.SecuritiesAccount
  alias Portfolixir.Repo

  import Ecto.Query

  defmodule Result do
    @moduledoc false
    defstruct created_securities: 0,
              created_security_ids: [],
              resolved_security_ids: [],
              created_cash_accounts: 0,
              created_securities_accounts: 0,
              created_transactions: 0,
              skipped_duplicates: 0,
              skipped_entries: []

    @type t :: %__MODULE__{}
  end

  @type portfolio_choice ::
          {:existing, integer()}
          | {:create, %{name: String.t(), base_currency_code: String.t()}}

  @type account_choice ::
          {:existing, integer()} | {:create, String.t()}

  @type depot_mapping :: %{
          required(:target) => account_choice(),
          required(:cash) => String.t() | account_choice()
        }

  @type apply_params :: %{
          required(:portfolio_id) => integer(),
          optional(:default_currency_code) => String.t()
        }

  @type mapped_apply_params :: %{
          required(:portfolio) => portfolio_choice(),
          required(:cash_accounts) => %{String.t() => account_choice()},
          required(:depots) => %{String.t() => depot_mapping()},
          optional(:default_currency_code) => String.t()
        }

  @spec apply(Preview.t(), apply_params() | mapped_apply_params()) ::
          {:ok, Result.t()} | {:error, term()}
  # New mapping-driven path: the LiveView picks/creates portfolio, cash
  # accounts and depots explicitly and hands the resolver this struct.
  def apply(%Preview{entries: entries}, %{portfolio: _, cash_accounts: _, depots: _} = params) do
    default_currency = Map.get(params, :default_currency_code, "EUR")
    flat_entries = Entry.flatten(entries)
    cash_currencies = cash_currencies_by_pp_name(flat_entries)

    Repo.transaction(fn ->
      with {:ok, portfolio_id, result} <- resolve_portfolio(params.portfolio, %Result{}),
           {:ok, cash_by_pp_name, result} <-
             resolve_mapped_cash(
               params.cash_accounts,
               portfolio_id,
               cash_currencies,
               default_currency,
               result
             ),
           {:ok, depot_by_pp_name, result} <-
             resolve_mapped_depots(params.depots, portfolio_id, cash_by_pp_name, result) do
        state = %{
          portfolio_id: portfolio_id,
          default_currency: default_currency,
          securities_by_isin: load_securities_by_isin(),
          securities_by_name: load_securities_by_name(),
          cash_by_name: cash_by_pp_name,
          depot_by_name: depot_by_pp_name,
          result: result,
          existing_dedup_keys: load_existing_dedup_keys(portfolio_id)
        }

        case reduce_entries(flat_entries, state) do
          {:ok, final_state} -> final_state.result
          {:error, reason} -> Repo.rollback(reason)
        end
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> enrich_after_commit()
  end

  # Original auto-resolve path: kept for the JSON-API entry point and
  # the existing applier_test.exs suite. Creates missing securities,
  # cash accounts and depots inside the chosen portfolio with the PP
  # names verbatim. Depots without an explicit cash account fall back
  # to the first cash account in the portfolio (matching counter_depot
  # behaviour before mapping was introduced).
  def apply(%Preview{entries: entries}, %{portfolio_id: portfolio_id} = params)
      when is_integer(portfolio_id) do
    default_currency = Map.get(params, :default_currency_code, "EUR")
    flat_entries = Entry.flatten(entries)

    Repo.transaction(fn ->
      state = %{
        portfolio_id: portfolio_id,
        default_currency: default_currency,
        securities_by_isin: load_securities_by_isin(),
        securities_by_name: load_securities_by_name(),
        cash_by_name: load_cash_by_name(portfolio_id),
        depot_by_name: load_depots_by_name(portfolio_id),
        result: %Result{},
        existing_dedup_keys: load_existing_dedup_keys(portfolio_id)
      }

      case reduce_entries(flat_entries, state) do
        {:ok, final_state} -> final_state.result
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> enrich_after_commit()
  end

  defp enrich_after_commit({:ok, %Result{} = result}) do
    created_ids = Enum.reverse(result.created_security_ids)
    resolved_ids = result.resolved_security_ids |> Enum.reverse() |> Enum.uniq()

    Catalog.enrich_security_ids_async(created_ids)
    Catalog.enqueue_missing_security_logos_async()

    {:ok,
     %Result{result | created_security_ids: created_ids, resolved_security_ids: resolved_ids}}
  end

  defp enrich_after_commit(other), do: other

  # --- mapping resolvers (new path) ---

  defp resolve_portfolio({:existing, id}, result) when is_integer(id) do
    {:ok, id, result}
  end

  defp resolve_portfolio({:create, %{name: name, base_currency_code: ccy}}, result) do
    case Portfolios.create_portfolio(Actor.import_session(), %{
           name: name,
           base_currency_code: ccy
         }) do
      {:ok, %{id: id}} -> {:ok, id, result}
      {:error, changeset} -> {:error, {:portfolio_create_failed, changeset}}
    end
  end

  defp resolve_portfolio(other, _result), do: {:error, {:invalid_portfolio_choice, other}}

  # A newly-created cash account takes the currency of the bookings assigned to
  # that PP account (Portfolio Performance accounts are single-currency), so a
  # USD account is not created as the default EUR and then rejected by the
  # transaction currency-consistency check. Falls back to the default when no
  # booking reveals a currency. Mirrors the auto-resolve path's `create_cash/3`.
  defp cash_currencies_by_pp_name(flat_entries) do
    Enum.reduce(flat_entries, %{}, fn entry, acc ->
      acc
      |> put_account_currency(entry.pp_account_name, entry.currency_code)
      |> put_account_currency(entry.pp_counter_account_name, entry.currency_code)
    end)
  end

  defp put_account_currency(acc, name, currency)
       when is_binary(name) and is_binary(currency) do
    Map.put_new(acc, name, currency)
  end

  defp put_account_currency(acc, _name, _currency), do: acc

  defp resolve_mapped_cash(
         mapping,
         portfolio_id,
         cash_currencies,
         default_currency,
         %Result{} = result
       ) do
    Enum.reduce_while(mapping, {:ok, %{}, result}, fn {pp_name, choice},
                                                      {:ok, acc, %Result{} = res} ->
      ccy = Map.get(cash_currencies, pp_name, default_currency)

      case resolve_cash_choice(pp_name, choice, portfolio_id, ccy) do
        {:ok, id, ^choice} ->
          {:cont, {:ok, Map.put(acc, pp_name, id), res}}

        {:ok, id, :created} ->
          res = %Result{res | created_cash_accounts: res.created_cash_accounts + 1}
          {:cont, {:ok, Map.put(acc, pp_name, id), res}}

        {:error, _} = err ->
          {:halt, err}
      end
    end)
  end

  defp resolve_cash_choice(_pp_name, {:existing, id}, _portfolio_id, _ccy) when is_integer(id) do
    {:ok, id, {:existing, id}}
  end

  defp resolve_cash_choice(_pp_name, {:create, name}, portfolio_id, ccy) when is_binary(name) do
    case Portfolios.create_cash_account(Actor.import_session(), %{
           portfolio_id: portfolio_id,
           name: name,
           currency_code: ccy
         }) do
      {:ok, %{id: id}} -> {:ok, id, :created}
      {:error, changeset} -> {:error, {:cash_create_failed, name, changeset}}
    end
  end

  defp resolve_cash_choice(pp_name, other, _portfolio_id, _ccy) do
    {:error, {:invalid_cash_choice, pp_name, other}}
  end

  defp resolve_mapped_depots(mapping, portfolio_id, cash_by_pp_name, %Result{} = result) do
    Enum.reduce_while(mapping, {:ok, %{}, result}, fn {pp_name, depot_spec},
                                                      {:ok, acc, %Result{} = res} ->
      with {:ok, cash_id} <- resolve_depot_cash_ref(depot_spec.cash, cash_by_pp_name),
           {:ok, id, mode} <-
             resolve_depot_choice(pp_name, depot_spec.target, portfolio_id, cash_id) do
        res =
          case mode do
            :created ->
              %Result{res | created_securities_accounts: res.created_securities_accounts + 1}

            _ ->
              res
          end

        entry = %{id: id, cash_account_id: cash_id}
        {:cont, {:ok, Map.put(acc, pp_name, entry), res}}
      else
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp resolve_depot_cash_ref(cash_ref, cash_by_pp_name) when is_binary(cash_ref) do
    case Map.fetch(cash_by_pp_name, cash_ref) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, {:unresolved_depot_cash_ref, cash_ref}}
    end
  end

  defp resolve_depot_cash_ref({:existing, id}, _cash_by_pp_name) when is_integer(id),
    do: {:ok, id}

  defp resolve_depot_cash_ref(other, _cash_by_pp_name) do
    {:error, {:invalid_depot_cash_ref, other}}
  end

  defp resolve_depot_choice(_pp_name, {:existing, id}, _portfolio_id, _cash_id)
       when is_integer(id) do
    {:ok, id, :existing}
  end

  defp resolve_depot_choice(_pp_name, {:create, name}, portfolio_id, cash_id)
       when is_binary(name) and is_integer(cash_id) do
    case Portfolios.create_securities_account(Actor.import_session(), %{
           portfolio_id: portfolio_id,
           cash_account_id: cash_id,
           name: name
         }) do
      {:ok, %{id: id}} -> {:ok, id, :created}
      {:error, changeset} -> {:error, {:depot_create_failed, name, changeset}}
    end
  end

  defp resolve_depot_choice(pp_name, other, _portfolio_id, _cash_id) do
    {:error, {:invalid_depot_choice, pp_name, other}}
  end

  defp reduce_entries(entries, initial_state) do
    Enum.reduce_while(entries, {:ok, initial_state}, fn entry, {:ok, state} ->
      case process_entry(entry, state) do
        {:ok, state} -> {:cont, {:ok, state}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp load_securities_by_isin do
    Repo.all(from(s in Security, where: not is_nil(s.isin), select: {s.isin, s.id}))
    |> Map.new()
  end

  defp load_securities_by_name do
    Repo.all(from(s in Security, select: {{s.name, s.currency_code}, s.id})) |> Map.new()
  end

  defp load_cash_by_name(portfolio_id) do
    Repo.all(
      from(c in CashAccount,
        where: c.portfolio_id == ^portfolio_id,
        select: {c.name, c.id}
      )
    )
    |> Map.new()
  end

  defp load_depots_by_name(portfolio_id) do
    Repo.all(
      from(d in SecuritiesAccount,
        where: d.portfolio_id == ^portfolio_id,
        select: {d.name, %{id: d.id, cash_account_id: d.cash_account_id}}
      )
    )
    |> Map.new()
  end

  # Kinds that move shares but settle no cash, so they legitimately carry no
  # gross_amount. Everything else (except balance_adjustment, whose amount is an
  # absolute balance) needs a positive gross_amount.
  @cashless_kinds ~w(inbound_delivery outbound_delivery security_transfer)

  defp process_entry(%Entry{} = entry, state) do
    if skip_unimportable?(entry) do
      # A degenerate row (e.g. a 0 EUR tax line) can't become a valid
      # transaction, but it must not abort the whole atomic import (#482).
      # Skip it and report it; genuine changeset failures still roll back.
      reason = "skipped: zero or missing gross_amount for #{entry.kind}"
      {:ok, record_skip(state, entry, reason)}
    else
      do_process_entry(entry, state)
    end
  end

  defp skip_unimportable?(%Entry{kind: kind, gross_amount: amount}) do
    kind not in @cashless_kinds and kind != "balance_adjustment" and
      (is_nil(amount) or Decimal.compare(amount, Decimal.new(0)) != :gt)
  end

  defp record_skip(state, %Entry{} = entry, reason) when is_binary(reason) do
    Map.update!(state, :result, fn %Result{} = r ->
      %Result{
        r
        | skipped_entries: r.skipped_entries ++ [%{row: entry.source_row, reason: reason}]
      }
    end)
  end

  defp do_process_entry(%Entry{} = entry, state) do
    with {:ok, state, security_id} <- resolve_security(entry, state),
         {:ok, state, cash_id} <- resolve_cash(entry, state),
         {:ok, state, counter_cash_id} <- resolve_counter_cash(entry, state),
         {:ok, state, depot_id} <- resolve_depot(entry, state, cash_id),
         {:ok, state, counter_depot_id} <- resolve_counter_depot(entry, state),
         attrs <-
           build_transaction_attrs(entry, state, %{
             security_id: security_id,
             cash_id: cash_id,
             counter_cash_id: counter_cash_id,
             depot_id: depot_id,
             counter_depot_id: counter_depot_id
           }) do
      insert_transaction(entry, attrs, state)
    end
  end

  # --- security resolution ---

  defp resolve_security(%Entry{security: nil}, state), do: {:ok, state, nil}

  defp resolve_security(%Entry{security: %{isin: isin}} = entry, state)
       when is_binary(isin) and isin != "" do
    case Map.fetch(state.securities_by_isin, isin) do
      {:ok, id} -> {:ok, track_resolved_security(state, id), id}
      :error -> create_security(entry, state)
    end
  end

  defp resolve_security(%Entry{security: %{name: name, currency: currency}} = entry, state)
       when is_binary(name) do
    key = {name, currency || state.default_currency}

    case Map.fetch(state.securities_by_name, key) do
      {:ok, id} -> {:ok, track_resolved_security(state, id), id}
      :error -> create_security(entry, state)
    end
  end

  defp resolve_security(_entry, state), do: {:ok, state, nil}

  defp create_security(%Entry{security: ref} = _entry, state) do
    # Tag PP-imported securities so `Portfolixir.Catalog.QuoteSync`
    # routes them to the Yahoo adapter (uses bare ticker_symbol).
    # CSV-only entries lack a ticker — they'll still be tagged and the
    # user can fill in a ticker afterwards to enable sync.
    attrs = %{
      name: ref.name || "(unnamed)",
      isin: ref[:isin],
      wkn: ref[:wkn],
      ticker_symbol: ref[:ticker],
      currency_code: ref[:currency] || state.default_currency,
      provider: "portfolio_performance",
      feed: "PORTFOLIO_PERFORMANCE"
    }

    case Catalog.create_security(Actor.import_session(), attrs) do
      {:ok, security} ->
        state =
          state
          |> Map.update!(:securities_by_isin, fn map ->
            if security.isin, do: Map.put(map, security.isin, security.id), else: map
          end)
          |> Map.update!(:securities_by_name, fn map ->
            Map.put(map, {security.name, security.currency_code}, security.id)
          end)
          |> bump_result(:created_securities)
          |> track_created_security(security.id)
          |> track_resolved_security(security.id)

        {:ok, state, security.id}

      {:error, changeset} ->
        {:error, {:security_create_failed, changeset}}
    end
  end

  # --- cash account resolution ---

  defp resolve_cash(%Entry{pp_account_name: nil}, state), do: {:ok, state, nil}

  defp resolve_cash(%Entry{pp_account_name: name} = entry, state) do
    case Map.fetch(state.cash_by_name, name) do
      {:ok, id} -> {:ok, state, id}
      :error -> create_cash(name, entry, state)
    end
  end

  defp resolve_counter_cash(%Entry{pp_counter_account_name: nil}, state),
    do: {:ok, state, nil}

  defp resolve_counter_cash(%Entry{pp_counter_account_name: name} = entry, state) do
    case Map.fetch(state.cash_by_name, name) do
      {:ok, id} -> {:ok, state, id}
      :error -> create_cash(name, entry, state)
    end
  end

  defp create_cash(name, entry, state) do
    attrs = %{
      portfolio_id: state.portfolio_id,
      name: name,
      currency_code: entry.currency_code || state.default_currency
    }

    case Portfolios.create_cash_account(Actor.import_session(), attrs) do
      {:ok, cash} ->
        state =
          state
          |> Map.update!(:cash_by_name, &Map.put(&1, cash.name, cash.id))
          |> bump_result(:created_cash_accounts)

        {:ok, state, cash.id}

      {:error, changeset} ->
        {:error, {:cash_create_failed, changeset}}
    end
  end

  # --- depot resolution ---

  defp resolve_depot(%Entry{pp_portfolio_name: nil}, state, _cash_id), do: {:ok, state, nil}

  defp resolve_depot(%Entry{pp_portfolio_name: name}, state, cash_id) do
    case Map.fetch(state.depot_by_name, name) do
      {:ok, %{id: id}} -> {:ok, state, id}
      :error -> create_depot(name, cash_id, state)
    end
  end

  defp resolve_counter_depot(%Entry{pp_counter_portfolio_name: nil}, state),
    do: {:ok, state, nil}

  defp resolve_counter_depot(%Entry{pp_counter_portfolio_name: name}, state) do
    case Map.fetch(state.depot_by_name, name) do
      {:ok, %{id: id}} ->
        {:ok, state, id}

      :error ->
        # A counter depot for a SECURITY_TRANSFER may not have its own
        # cash account in the source export — fall back to the same
        # portfolio's first cash account. The user can re-wire after
        # import.
        case List.first(Map.values(state.cash_by_name)) do
          nil -> {:error, {:counter_depot_needs_cash, name}}
          cash_id -> create_depot(name, cash_id, state)
        end
    end
  end

  defp create_depot(name, nil, _state), do: {:error, {:depot_needs_cash, name}}

  defp create_depot(name, cash_id, state) do
    attrs = %{
      portfolio_id: state.portfolio_id,
      cash_account_id: cash_id,
      name: name
    }

    case Portfolios.create_securities_account(Actor.import_session(), attrs) do
      {:ok, depot} ->
        state =
          state
          |> Map.update!(:depot_by_name, fn map ->
            Map.put(map, depot.name, %{id: depot.id, cash_account_id: cash_id})
          end)
          |> bump_result(:created_securities_accounts)

        {:ok, state, depot.id}

      {:error, changeset} ->
        {:error, {:depot_create_failed, changeset}}
    end
  end

  # --- transaction attrs by kind ---

  defp build_transaction_attrs(%Entry{} = entry, state, ids) do
    base = %{
      portfolio_id: state.portfolio_id,
      type: entry.kind,
      date: entry.date,
      currency_code: entry.currency_code || state.default_currency,
      notes: entry.note,
      gross_amount: entry.gross_amount,
      fees: entry.fees || Decimal.new(0),
      taxes: entry.taxes || Decimal.new(0),
      import_hash: compute_hash(entry, state.portfolio_id)
    }

    extras =
      case entry.kind do
        kind when kind in ["buy", "sell"] ->
          %{
            security_id: ids.security_id,
            securities_account_id: ids.depot_id,
            cash_account_id: ids.cash_id,
            quantity: entry.quantity,
            price: entry.price
          }

        "dividend" ->
          %{
            security_id: ids.security_id,
            securities_account_id: ids.depot_id,
            cash_account_id: ids.cash_id,
            quantity: entry.quantity
          }

        kind when kind in ["interest", "deposit", "removal"] ->
          %{cash_account_id: ids.cash_id}

        kind when kind in ["fee", "tax", "tax_refund"] ->
          %{
            cash_account_id: ids.cash_id,
            security_id: ids.security_id,
            securities_account_id: ids.depot_id
          }

        "cash_transfer" ->
          %{
            cash_account_id: ids.cash_id,
            counter_cash_account_id: ids.counter_cash_id
          }

        kind when kind in ["inbound_delivery", "outbound_delivery"] ->
          %{
            security_id: ids.security_id,
            securities_account_id: ids.depot_id,
            quantity: entry.quantity
          }

        "security_transfer" ->
          %{
            security_id: ids.security_id,
            securities_account_id: ids.depot_id,
            counter_securities_account_id: ids.counter_depot_id,
            quantity: entry.quantity
          }
      end

    Map.merge(base, extras)
  end

  defp insert_transaction(entry, attrs, state) do
    key = dedup_key(attrs)

    # Two-layer idempotency (#533): the stored content `import_hash` skips exact
    # re-inserts (and exact within-file duplicates — `hash_already_imported?`
    # sees uncommitted inserts in this transaction). On top of that, a stable,
    # formatting-tolerant key over the *resolved* DB identity (portfolio,
    # security/account ids, normalized decimals) skips a re-import whose only
    # difference is PP-export drift (decimal precision, or a security rename when
    # matched by ISIN). The key set is a PRE-import snapshot and is deliberately
    # NOT extended during the import: `time` is not persisted on a transaction, so
    # two legitimate same-day/same-amount bookings (distinct only by time) must
    # not collapse — within-file de-duplication is the hash's job, not this key's.
    if hash_already_imported?(attrs.import_hash) or MapSet.member?(state.existing_dedup_keys, key) do
      {:ok, bump_result(state, :skipped_duplicates)}
    else
      changeset =
        %Transaction{}
        |> Transaction.changeset(attrs)
        |> Transaction.validate_cash_account_currency(cash_currencies_for(attrs))

      # The transactions table is journal-armed (ADR-0017): each imported booking
      # is journaled under an import actor in the same (nested) transaction as the
      # insert, mirroring how the applier already journals created securities.
      Multi.new()
      |> Multi.insert(:transaction, changeset)
      |> Journal.record(Actor.import_session(),
        resource_type: "transaction",
        operation: :create,
        source: :transaction
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{transaction: %Transaction{}}} ->
          {:ok, bump_result(state, :created_transactions)}

        {:error, :transaction, %Ecto.Changeset{} = changeset, _changes} ->
          {:error, %{row: entry.source_row, reason: {:insert_failed, changeset}}}
      end
    end
  end

  # The currency consistency rule (issue #343) is enforced on every insert
  # path; the applier inserts changesets directly rather than going through
  # `Ledger.create_transaction/1`, so it loads the linked cash account
  # currencies and runs the same pure validator. An auto-created cash
  # account is created with the entry's currency, so only an existing
  # account with a different currency can trip this.
  defp cash_currencies_for(attrs) do
    [attrs[:cash_account_id], attrs[:counter_cash_account_id]]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> case do
      [] ->
        %{}

      ids ->
        Repo.all(from(c in CashAccount, where: c.id in ^ids, select: {c.id, c.currency_code}))
        |> Map.new()
    end
  end

  defp hash_already_imported?(hash) when is_binary(hash) do
    Repo.exists?(from(t in Transaction, where: t.import_hash == ^hash))
  end

  # The portfolio's existing bookings as a set of stable dedup keys (#533). Loaded
  # once per import so a re-import can skip a booking that already exists even when
  # the exact content `import_hash` drifted (PP-export formatting/precision).
  defp load_existing_dedup_keys(portfolio_id) do
    from(t in Transaction, where: t.portfolio_id == ^portfolio_id)
    |> Repo.all()
    |> Enum.map(&dedup_key/1)
    |> MapSet.new()
  end

  # A formatting-tolerant identity over the *resolved* DB fields: same portfolio,
  # security/account ids, kind, date, and Decimal-normalized amounts. Computed
  # identically from import `attrs` and from a stored `%Transaction{}`, so equal
  # economic bookings collapse to the same key regardless of how PP serialized
  # the numbers. `Map.get/2` tolerates the kind-specific attrs that omit fields.
  defp dedup_key(record) do
    {
      Map.get(record, :portfolio_id),
      Map.get(record, :type),
      Map.get(record, :date),
      Map.get(record, :security_id),
      Map.get(record, :securities_account_id),
      Map.get(record, :counter_securities_account_id),
      Map.get(record, :cash_account_id),
      Map.get(record, :counter_cash_account_id),
      Map.get(record, :currency_code),
      # Round to each column's stored NUMERIC scale (quantity 12, money 6) BEFORE
      # normalizing, so a full-precision incoming entry collapses onto the value
      # Postgres actually persisted — otherwise a price/quantity with more places
      # than the column holds would round on storage and never match its re-import.
      norm_decimal(Map.get(record, :quantity), 12),
      norm_decimal(Map.get(record, :price), 6),
      norm_decimal(Map.get(record, :gross_amount), 6),
      norm_decimal(Map.get(record, :fees), 6),
      norm_decimal(Map.get(record, :taxes), 6)
    }
  end

  defp norm_decimal(nil, _scale), do: nil

  defp norm_decimal(%Decimal{} = d, scale) do
    d |> Decimal.round(scale) |> Decimal.normalize() |> Decimal.to_string(:normal)
  end

  # Increment one counter field on the Result struct inside `state`.
  # Pattern-matching `%Result{} = r` here keeps dialyzer happy.
  defp bump_result(state, field) when is_atom(field) do
    Map.update!(state, :result, fn %Result{} = r ->
      Map.update!(r, field, &(&1 + 1))
    end)
  end

  defp track_created_security(state, security_id) do
    Map.update!(state, :result, fn %Result{} = r ->
      %Result{r | created_security_ids: [security_id | r.created_security_ids]}
    end)
  end

  defp track_resolved_security(state, security_id) when is_integer(security_id) do
    Map.update!(state, :result, fn %Result{} = r ->
      %Result{r | resolved_security_ids: [security_id | r.resolved_security_ids]}
    end)
  end

  # SHA-256 over the stable identity fields. Same import file applied
  # twice yields the same hash, so the unique partial index on
  # `transactions.import_hash` rejects the second insert.
  #
  # The fields below must be specific enough that two genuinely
  # distinct PP rows never collapse to the same hash. In particular
  # `time`, `price`, `fees` and `taxes` are part of the input because
  # the same security can legitimately be bought twice on the same
  # day with the same quantity and gross amount but different
  # intraday timestamps or fee structures (e.g. two trades minutes
  # apart at slightly different prices).
  defp compute_hash(%Entry{} = entry, portfolio_id) do
    parts = [
      entry.kind,
      date_str(entry.date),
      time_str(entry.time),
      security_key(entry.security),
      decimal_str(entry.quantity),
      decimal_str(entry.price),
      decimal_str(entry.gross_amount),
      decimal_str(entry.fees),
      decimal_str(entry.taxes),
      entry.pp_portfolio_name || "",
      entry.pp_account_name || "",
      entry.pp_counter_portfolio_name || "",
      entry.pp_counter_account_name || "",
      Integer.to_string(portfolio_id)
    ]

    parts
    |> Enum.join("|")
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp date_str(nil), do: ""
  defp date_str(%Date{} = d), do: Date.to_iso8601(d)

  defp time_str(nil), do: ""
  defp time_str(%Time{} = t), do: Time.to_iso8601(t)

  defp decimal_str(nil), do: ""
  defp decimal_str(%Decimal{} = d), do: Decimal.to_string(d, :normal)

  defp security_key(nil), do: ""
  defp security_key(%{isin: isin}) when is_binary(isin) and isin != "", do: "isin:" <> isin
  defp security_key(%{name: name}) when is_binary(name), do: "name:" <> name
  defp security_key(_), do: ""
end
