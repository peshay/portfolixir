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

  Behavior:

  - Resolves securities through the full ADR-0029 §2 stable-identity
    ladder (`Portfolixir.Imports.SecurityResolver`): ISIN — current
    first, then the §3 former-ISIN aliases —, WKN, ticker+currency,
    name+currency, all in catalog normal form. Missing securities are
    created from the entry's `security` ref; the journaled create path
    rejects an ISIN recorded as a former ISIN (bidirectional guard).
  - **Fails closed** (§2): entries the ladder flags — an ambiguous tier,
    a stronger-identifier veto / cross-tier conflict, or a creation that
    would strand strategy configuration (config-at-risk) — are reported
    in `unresolved_entries` (mirroring `skipped_entries`) and neither
    auto-created nor auto-matched. They are resolvable only via explicit
    per-entry `security_mappings` (`:create` acknowledgment,
    `{:existing, id}` remap, or `{:existing, id, :record_isin_change}`
    which records the journaled §3 ISIN change in the same import
    transaction). No API imports route exists today; this contract lives
    here so any future route inherits it.
  - **Preview→apply revalidation** (§2): when `approved_resolutions` is
    given, every non-overridden entry's ladder outcome is recomputed
    inside the import transaction against a pristine index snapshot and
    the whole apply aborts with `{:error, {:resolution_diverged, key}}`
    when it differs from what was approved — previews live for hours,
    consent must not go stale.
  - **N:1 resolution** (§2): several file rows may resolve to one
    security (old + new ISIN of one paper); rows collapsing to an
    identical resolved dedup key *and* intraday time within one apply
    run are deduplicated and surfaced in `collapsed_duplicates`, never
    double-inserted. Two same-day bookings distinct only by time keep
    importing separately.
  - Resolves cash accounts and depots by name *within the chosen
    portfolio*. Missing ones are created.
  - Inserts one ledger row per entry, branching by kind.
  - Skips degenerate rows that can never form a valid transaction — a
    cash kind with a zero or missing gross_amount (e.g. a 0 EUR tax
    line) — recording each in `skipped_entries` with its row and a
    reason instead of aborting the whole import (#482). Genuine
    changeset/FK errors still roll the whole transaction back.
  - Reports created/skipped/error counts in the final result.

  Matching never mutates matched master data; the only in-transaction
  master-data write is the explicitly requested `:record_isin_change`.
  """

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Imports.Entry
  alias Portfolixir.Imports.Preview
  alias Portfolixir.Imports.SecurityResolver
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
              alias_matches: [],
              security_overrides: [],
              unresolved_entries: [],
              collapsed_duplicates: [],
              created_cash_accounts: 0,
              created_cash_account_ids: [],
              created_securities_accounts: 0,
              created_securities_account_ids: [],
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

  @typedoc """
  Explicit per-entry security decision (ADR-0029 §2), keyed by
  `Portfolixir.Imports.SecurityResolver.key/1`: acknowledge a creation,
  remap onto an existing security, or remap and record the entry's ISIN as
  a journaled §3 ISIN change in the same transaction.
  """
  @type security_mapping ::
          :create | {:existing, integer()} | {:existing, integer(), :record_isin_change}

  @typedoc "The preview's approved ladder baseline for non-overridden entries."
  @type approved_resolution :: {:matched, integer()} | :create

  @type apply_params :: %{
          required(:portfolio_id) => integer(),
          optional(:default_currency_code) => String.t(),
          optional(:security_mappings) => %{String.t() => security_mapping()},
          optional(:approved_resolutions) => %{String.t() => approved_resolution()}
        }

  @type mapped_apply_params :: %{
          optional(:portfolio) => portfolio_choice(),
          required(:cash_accounts) => %{String.t() => account_choice()},
          required(:depots) => %{String.t() => depot_mapping()},
          optional(:bucket_tag) => String.t() | nil,
          optional(:default_currency_code) => String.t(),
          optional(:security_mappings) => %{String.t() => security_mapping()},
          optional(:approved_resolutions) => %{String.t() => approved_resolution()}
        }

  @spec apply(Preview.t(), apply_params() | mapped_apply_params()) ::
          {:ok, Result.t()} | {:error, term()}
  # Mapping-driven path: the LiveView maps cash accounts and depots
  # explicitly and hands the resolver this struct. Without an explicit
  # `:portfolio` choice the import binds to the deterministic internal
  # default portfolio (ADR-0024) — the user never picks one. An optional
  # `:bucket_tag` names the tag-dimension bucket assigned to the accounts
  # this import CREATES (nil/blank skips tagging; existing-mapped accounts
  # keep their tags untouched).
  def apply(%Preview{entries: entries}, %{cash_accounts: _, depots: _} = params) do
    default_currency = Map.get(params, :default_currency_code, "EUR")
    bucket_tag = normalize_bucket_tag(Map.get(params, :bucket_tag))
    flat_entries = Entry.flatten(entries)
    cash_currencies = cash_currencies_by_pp_name(flat_entries)

    Repo.transaction(fn ->
      with {:ok, portfolio_id, result} <-
             resolve_portfolio(Map.get(params, :portfolio), %Result{}),
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
        state =
          base_state(portfolio_id, default_currency, params, result)
          |> Map.merge(%{cash_by_name: cash_by_pp_name, depot_by_name: depot_by_pp_name})

        with {:ok, final_state} <- reduce_entries(flat_entries, state),
             {:ok, final_result} <- apply_bucket_tag(bucket_tag, final_state.result) do
          final_result
        else
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
      state =
        base_state(portfolio_id, default_currency, params, %Result{})
        |> Map.merge(%{
          cash_by_name: load_cash_by_name(portfolio_id),
          depot_by_name: load_depots_by_name(portfolio_id)
        })

      case reduce_entries(flat_entries, state) do
        {:ok, final_state} -> final_state.result
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> enrich_after_commit()
  end

  # Shared per-run state. The security index is loaded once inside the import
  # transaction; `pristine_index` stays the untouched snapshot the §2
  # preview→apply revalidation recomputes against, while `live_index` absorbs
  # securities created (or ISIN-changed via an override) during this run so
  # later rows of the same file resolve consistently. `key_resolutions`
  # memoizes the decision per unique reference key — N:1 friendly and
  # guaranteed stable within one run.
  defp base_state(portfolio_id, default_currency, params, %Result{} = result) do
    index = SecurityResolver.load_index()

    %{
      portfolio_id: portfolio_id,
      default_currency: default_currency,
      pristine_index: index,
      live_index: index,
      security_mappings: Map.get(params, :security_mappings, %{}),
      approved_resolutions: Map.get(params, :approved_resolutions),
      key_resolutions: %{},
      seen_run_keys: MapSet.new(),
      result: result,
      existing_dedup_keys: load_existing_dedup_keys(portfolio_id)
    }
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

  # No explicit choice: bind to the deterministic internal default
  # portfolio (ADR-0024). Resolved under the import actor, so a
  # first-import "Default" shows source Import in the admin list.
  defp resolve_portfolio(nil, result) do
    %{id: id} = Portfolios.default_portfolio(Actor.import_session())
    {:ok, id, result}
  end

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
          res = %Result{
            res
            | created_cash_accounts: res.created_cash_accounts + 1,
              created_cash_account_ids: [id | res.created_cash_account_ids]
          }

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
              %Result{
                res
                | created_securities_accounts: res.created_securities_accounts + 1,
                  created_securities_account_ids: [id | res.created_securities_account_ids]
              }

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

  # --- bucket tag for newly created accounts (ADR-0024 story 5) ---

  defp normalize_bucket_tag(nil), do: nil

  defp normalize_bucket_tag(tag) when is_binary(tag) do
    case String.trim(tag) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  # Assigns the tag-dimension bucket to every depot/cash account this import
  # CREATED (journaled through the Buckets context, inside the same import
  # transaction). No tag, or no newly created account, is a no-op — in
  # particular no bucket is created for an import that only mapped existing
  # records, and accounts mapped to existing records keep their tags.
  defp apply_bucket_tag(nil, %Result{} = result), do: {:ok, result}

  defp apply_bucket_tag(
         _tag,
         %Result{created_cash_account_ids: [], created_securities_account_ids: []} = result
       ) do
    {:ok, result}
  end

  defp apply_bucket_tag(tag, %Result{} = result) do
    actor = Actor.import_session()

    with {:ok, bucket} <- Buckets.ensure_tag_bucket(actor, tag),
         :ok <- tag_created_depots(actor, bucket, result.created_securities_account_ids),
         :ok <- tag_created_cash(actor, bucket, result.created_cash_account_ids) do
      {:ok, result}
    else
      {:error, reason} -> {:error, {:bucket_tag_failed, reason}}
    end
  end

  defp tag_created_depots(actor, bucket, depot_ids) do
    each_ok(depot_ids, fn id ->
      add_bucket(
        Buckets.depot_default_bucket_ids(id),
        bucket.id,
        &Buckets.set_depot_default_buckets(actor, %SecuritiesAccount{id: id}, &1)
      )
    end)
  end

  defp tag_created_cash(actor, bucket, cash_ids) do
    each_ok(cash_ids, fn id ->
      add_bucket(
        Buckets.cash_account_bucket_ids(id),
        bucket.id,
        &Buckets.set_cash_account_buckets(actor, %CashAccount{id: id}, &1)
      )
    end)
  end

  # Adds the bucket to the account's current set (freshly created accounts
  # start empty; already-tagged is a no-op, so a retry can't double-assign).
  defp add_bucket(current_ids, bucket_id, set_fun) do
    if bucket_id in current_ids, do: :ok, else: set_fun.(current_ids ++ [bucket_id])
  end

  defp each_ok(ids, fun) do
    Enum.reduce_while(ids, :ok, fn id, :ok ->
      case fun.(id) do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp reduce_entries(entries, initial_state) do
    Enum.reduce_while(entries, {:ok, initial_state}, fn entry, {:ok, state} ->
      case process_entry(entry, state) do
        {:ok, state} -> {:cont, {:ok, state}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
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
    case resolve_security(entry, state) do
      # A surfaced-but-undecided security (§2 fail closed): the entry is
      # reported in `unresolved_entries` and creates nothing.
      {:skip, state} ->
        {:ok, state}

      {:ok, state, security_id} ->
        with {:ok, state, cash_id} <- resolve_cash(entry, state),
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

      {:error, _} = error ->
        error
    end
  end

  # --- security resolution (ADR-0029 §2 ladder) ---

  defp resolve_security(%Entry{security: nil}, state), do: {:ok, state, nil}

  defp resolve_security(%Entry{} = entry, state) do
    ref = SecurityResolver.effective_ref(entry)

    if SecurityResolver.blank_ref?(ref) do
      {:ok, state, nil}
    else
      resolve_security_ref(entry, ref, SecurityResolver.key(ref), state)
    end
  end

  # One decision per unique reference key, memoized for the run: repeated
  # rows reuse it (each still labeled/reported individually), so a key can
  # never resolve two ways within one apply.
  defp resolve_security_ref(entry, ref, key, state) do
    case Map.fetch(state.key_resolutions, key) do
      {:ok, {:security, id, tier}} ->
        {:ok, state |> track_resolved_security(id) |> maybe_record_alias(entry, ref, tier, id),
         id}

      {:ok, {:unresolved, reason}} ->
        {:skip, record_unresolved(state, entry, key, reason)}

      :error ->
        first_resolution(entry, ref, key, state)
    end
  end

  defp first_resolution(entry, ref, key, state) do
    case Map.fetch(state.security_mappings, key) do
      {:ok, mapping} ->
        apply_security_mapping(entry, ref, key, mapping, state)

      :error ->
        with :ok <- revalidate_against_approval(ref, key, state) do
          ladder_resolution(entry, ref, key, state)
        end
    end
  end

  # Preview→apply revalidation (§2): re-run the ladder against the pristine
  # (transaction-start) index and abort when the outcome differs from what
  # the preview approved. Overridden keys skip this — their decision IS the
  # approval — and a key the preview never showed is likewise a divergence.
  defp revalidate_against_approval(_ref, _key, %{approved_resolutions: nil}), do: :ok

  defp revalidate_against_approval(ref, key, %{approved_resolutions: approved} = state) do
    digest =
      case SecurityResolver.resolve(ref, state.pristine_index) do
        {:match, security, _tier} ->
          {:matched, security.id}

        :create ->
          # A plain create that has become config-at-risk since the preview is
          # a divergence from the approved `:create`, not a silent drop into
          # unresolved_entries: fold the risk into the digest so it aborts back
          # to the preview (ADR-0029 §2).
          case SecurityResolver.config_at_risk(ref, state.pristine_index) do
            [] -> :create
            _at_risk -> :create_at_risk
          end

        {:conflict, _conflict} ->
          :conflict
      end

    if Map.get(approved, key) == digest do
      :ok
    else
      {:error, {:resolution_diverged, key}}
    end
  end

  defp ladder_resolution(entry, ref, key, state) do
    case SecurityResolver.resolve(ref, state.live_index) do
      {:match, security, tier} ->
        state =
          state
          |> cache_resolution(key, {:security, security.id, tier})
          |> track_resolved_security(security.id)
          |> maybe_record_alias(entry, ref, tier, security.id)

        {:ok, state, security.id}

      {:conflict, conflict} ->
        mark_unresolved(entry, key, state, conflict_reason(conflict))

      :create ->
        case SecurityResolver.config_at_risk(ref, state.live_index) do
          [] -> create_security(entry, ref, key, state)
          at_risk -> mark_unresolved(entry, key, state, config_at_risk_reason(at_risk))
        end
    end
  end

  defp mark_unresolved(entry, key, state, reason) do
    state = cache_resolution(state, key, {:unresolved, reason})
    {:skip, record_unresolved(state, entry, key, reason)}
  end

  defp conflict_reason(%{type: :ambiguous, tier: tier, candidates: candidates}) do
    "ambiguous match: #{length(candidates)} existing securities share the #{tier_word(tier)}"
  end

  defp conflict_reason(%{type: :identifier_veto, candidates: [candidate]}) do
    "conflicts with \"#{candidate.name}\" (security ##{candidate.id}) on a " <>
      "stronger identifier — possibly an unrecorded ISIN change (ADR-0029 §3)"
  end

  defp conflict_reason(%{type: :cross_tier, candidates: candidates}) do
    names = Enum.map_join(candidates, ", ", &"\"#{&1.name}\" (##{&1.id})")
    "identifiers point at different existing securities: #{names}"
  end

  defp config_at_risk_reason(at_risk) do
    names = Enum.map_join(at_risk, ", ", &"\"#{&1.security.name}\" (##{&1.security.id})")

    "creating it would strand strategy configuration (category assignments " <>
      "or position targets) on: #{names} — requires an explicit decision"
  end

  defp tier_word(:wkn), do: "WKN"
  defp tier_word(:ticker), do: "ticker and currency"
  defp tier_word(:name), do: "name and currency"
  defp tier_word(other), do: to_string(other)

  # --- explicit security mappings (§2 overrides / API-shaped twin) ---

  defp apply_security_mapping(entry, ref, key, :create, state) do
    create_security(entry, ref, key, state)
  end

  defp apply_security_mapping(entry, ref, key, {:existing, id}, state) when is_integer(id) do
    apply_existing_mapping(entry, ref, key, id, false, state)
  end

  defp apply_security_mapping(entry, ref, key, {:existing, id, :record_isin_change}, state)
       when is_integer(id) do
    apply_existing_mapping(entry, ref, key, id, true, state)
  end

  defp apply_security_mapping(_entry, _ref, key, _other, _state) do
    {:error, {:invalid_security_mapping, key}}
  end

  defp apply_existing_mapping(_entry, ref, key, id, record_change?, state) do
    case Map.fetch(state.live_index.securities_by_id, id) do
      :error ->
        {:error, {:invalid_security_mapping, key}}

      {:ok, security} ->
        case maybe_record_isin_change(state, security, ref, key, record_change?) do
          {:ok, state, security, recorded?} ->
            state =
              state
              |> cache_resolution(key, {:security, security.id, :override})
              |> track_security_override(key, security.id, recorded?)
              |> track_resolved_security(security.id)

            {:ok, state, security.id}

          {:error, _} = error ->
            error
        end
    end
  end

  # Override durability (§2): a remap whose entry ISIN differs from the
  # matched security's current ISIN can record it as a §3 ISIN change in the
  # same journaled transaction, so the decision persists for future imports.
  # No-ops (no entry ISIN, equal ISINs, an ISIN-less target with no current
  # ISIN to alias, or the change already recorded) skip silently so a
  # re-apply after a divergence abort stays idempotent.
  defp maybe_record_isin_change(state, security, _ref, _key, false),
    do: {:ok, state, security, false}

  defp maybe_record_isin_change(state, security, %{isin: nil}, _key, true),
    do: {:ok, state, security, false}

  defp maybe_record_isin_change(state, %Security{isin: nil} = security, _ref, _key, true),
    do: {:ok, state, security, false}

  defp maybe_record_isin_change(state, %Security{} = security, %{isin: entry_isin}, key, true) do
    cond do
      security.isin == entry_isin ->
        {:ok, state, security, false}

      already_alias_of?(state.live_index, entry_isin, security.id) ->
        {:ok, state, security, false}

      true ->
        case Catalog.record_isin_change(Actor.import_session(), security, entry_isin) do
          {:ok, %{security: updated}} ->
            {:ok, update_index_after_isin_change(state, security, updated), updated, true}

          {:error, changeset} ->
            {:error, {:record_isin_change_failed, key, changeset}}
        end
    end
  end

  defp already_alias_of?(index, isin, security_id) do
    case Map.fetch(index.by_former_isin, isin) do
      {:ok, %Security{id: ^security_id}} -> true
      _other -> false
    end
  end

  defp update_index_after_isin_change(state, %Security{} = before, %Security{} = updated) do
    Map.update!(state, :live_index, fn index ->
      %{
        index
        | securities_by_id: Map.put(index.securities_by_id, updated.id, updated),
          by_isin: index.by_isin |> Map.delete(before.isin) |> Map.put(updated.isin, updated),
          by_former_isin:
            index.by_former_isin |> Map.delete(updated.isin) |> Map.put(before.isin, updated),
          by_wkn: replace_in_groups(index.by_wkn, updated),
          by_ticker_ccy: replace_in_groups(index.by_ticker_ccy, updated),
          by_name_ccy: replace_in_groups(index.by_name_ccy, updated),
          by_name: replace_in_groups(index.by_name, updated),
          by_ticker: replace_in_groups(index.by_ticker, updated)
      }
    end)
  end

  defp replace_in_groups(map, %Security{} = updated) do
    Map.new(map, fn {group_key, securities} ->
      {group_key, Enum.map(securities, &if(&1.id == updated.id, do: updated, else: &1))}
    end)
  end

  # Labels an alias-tier hit in the result ("matched via former ISIN") so the
  # imports view can surface which entries resolved through a recorded
  # ISIN change (ADR-0029 §3).
  defp maybe_record_alias(state, %Entry{} = entry, ref, :former_isin, security_id) do
    Map.update!(state, :result, fn %Result{} = r ->
      match = %{row: entry.source_row, former_isin: ref.isin, security_id: security_id}
      %Result{r | alias_matches: r.alias_matches ++ [match]}
    end)
  end

  defp maybe_record_alias(state, _entry, _ref, _tier, _security_id), do: state

  defp record_unresolved(state, %Entry{} = entry, key, reason) do
    Map.update!(state, :result, fn %Result{} = r ->
      unresolved = %{row: entry.source_row, key: key, reason: reason}
      %Result{r | unresolved_entries: r.unresolved_entries ++ [unresolved]}
    end)
  end

  defp track_security_override(state, key, security_id, recorded_isin_change?) do
    Map.update!(state, :result, fn %Result{} = r ->
      override = %{
        key: key,
        security_id: security_id,
        recorded_isin_change: recorded_isin_change?
      }

      %Result{r | security_overrides: r.security_overrides ++ [override]}
    end)
  end

  defp cache_resolution(state, key, resolution) do
    Map.update!(state, :key_resolutions, &Map.put(&1, key, resolution))
  end

  defp create_security(_entry, ref, key, state) do
    # Tag PP-imported securities so `Portfolixir.Catalog.QuoteSync`
    # routes them to the Yahoo adapter (uses bare ticker_symbol).
    # CSV-only entries lack a ticker — they'll still be tagged and the
    # user can fill in a ticker afterwards to enable sync.
    attrs = %{
      name: ref.name || "(unnamed)",
      isin: ref.isin,
      wkn: ref.wkn,
      ticker_symbol: ref.ticker,
      currency_code: ref.currency || state.default_currency,
      provider: "portfolio_performance",
      feed: "PORTFOLIO_PERFORMANCE"
    }

    case Catalog.create_security(Actor.import_session(), attrs) do
      {:ok, security} ->
        state =
          state
          |> Map.update!(:live_index, &add_security_to_index(&1, security))
          |> cache_resolution(key, {:security, security.id, :created})
          |> bump_result(:created_securities)
          |> track_created_security(security.id)
          |> track_resolved_security(security.id)

        {:ok, state, security.id}

      {:error, changeset} ->
        {:error, {:security_create_failed, changeset}}
    end
  end

  # A security created during the run enters the live index so later rows of
  # the same file resolve onto it instead of minting a second copy.
  defp add_security_to_index(index, %Security{} = security) do
    %{
      index
      | securities_by_id: Map.put(index.securities_by_id, security.id, security),
        by_isin: put_if(index.by_isin, security.isin, security),
        by_wkn: group_put_if(index.by_wkn, security.wkn, security),
        by_ticker_ccy:
          group_put_if(index.by_ticker_ccy, key_pair(security.ticker_symbol, security), security),
        by_name_ccy: group_put_if(index.by_name_ccy, key_pair(security.name, security), security),
        by_name: group_put_if(index.by_name, security.name, security),
        by_ticker: group_put_if(index.by_ticker, security.ticker_symbol, security)
    }
  end

  defp key_pair(nil, _security), do: nil
  defp key_pair(value, %Security{currency_code: ccy}), do: {value, ccy}

  defp put_if(map, nil, _security), do: map
  defp put_if(map, map_key, security), do: Map.put(map, map_key, security)

  defp group_put_if(map, nil, _security), do: map

  defp group_put_if(map, map_key, security),
    do: Map.update(map, map_key, [security], &(&1 ++ [security]))

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
          |> track_created_account(:created_cash_account_ids, cash.id)

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
          |> track_created_account(:created_securities_account_ids, depot.id)

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
          # The parsed per-share price (PP CSV `Kurs`) is persisted so a
          # priced inbound delivery enters the holdings cost fold with its
          # real cost (#585). The outbound price is data retention only —
          # the cost fold removes cost at the running average. A price-less
          # delivery keeps `price: nil` (zero cost, unchanged).
          %{
            security_id: ids.security_id,
            securities_account_id: ids.depot_id,
            quantity: entry.quantity,
            price: entry.price
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
    # N:1 within-run dedup (ADR-0029 §2): two file rows carrying different
    # identities of ONE paper (old + new ISIN) resolve to the same security
    # and therefore to an identical resolved dedup key while their content
    # hashes differ — they must collapse to one insert, surfaced in the
    # result. `entry.time` joins the run key so two legitimate same-day
    # bookings distinct only by their intraday time never collapse.
    run_key = {key, entry.time}

    cond do
      hash_already_imported?(attrs.import_hash) or MapSet.member?(state.existing_dedup_keys, key) ->
        {:ok, bump_result(state, :skipped_duplicates)}

      MapSet.member?(state.seen_run_keys, run_key) ->
        {:ok, state |> bump_result(:skipped_duplicates) |> record_collapsed(entry)}

      true ->
        insert_new_transaction(entry, attrs, run_key, state)
    end
  end

  defp record_collapsed(state, %Entry{} = entry) do
    Map.update!(state, :result, fn %Result{} = r ->
      collapsed = %{
        row: entry.source_row,
        reason: "collapsed: resolves to the same booking as an earlier row in this file"
      }

      %Result{r | collapsed_duplicates: r.collapsed_duplicates ++ [collapsed]}
    end)
  end

  defp insert_new_transaction(entry, attrs, run_key, state) do
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
        state =
          state
          |> bump_result(:created_transactions)
          |> Map.update!(:seen_run_keys, &MapSet.put(&1, run_key))

        {:ok, state}

      {:error, :transaction, %Ecto.Changeset{} = changeset, _changes} ->
        {:error, %{row: entry.source_row, reason: {:insert_failed, changeset}}}
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

  defp track_created_account(state, field, account_id) when is_atom(field) do
    Map.update!(state, :result, fn %Result{} = r ->
      Map.update!(r, field, &[account_id | &1])
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
