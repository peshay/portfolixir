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
  portfolio id) by `Portfolixir.Imports.ImportHash`, injective since E25 S5
  (F36) with every stored hash still valid. The `transactions.import_hash`
  unique partial index rejects re-inserts; the applier counts those as
  `skipped_duplicates` and continues.

  The re-import contract (ADR-0050 §2–§6) fixes the order of the checks:

  - **Hash first** (§3). The content hash covers only file-side fields
    plus the portfolio, so it is computed before anything resolves. A row
    whose hash a transaction holds (layer `:hash`) or a merge retired
    (layer `:retired`, `retired_import_hashes`) is reported in
    `duplicate_entries` and triggers no security, cash or depot
    resolution, no creation and no insert.
  - **Preview decisions run from the mapping at apply start** (§3): every
    `{:existing, id}` security mapping of a key the file carries is
    executed before the first row — its `:record_isin_change` recorded —
    so it takes effect even when every row of its key is a hash hit.
    A `:create` mapping stays lazy: it creates on the first row that
    reaches it.
  - **Accounts are created lazily** (§4): a `create`-mapped or unmatched
    cash account or depot is materialized on the first row actually
    inserted, never up front. A choice whose rows are all skipped creates
    nothing, and the bucket tag touches exactly the accounts created.
  - **Accounts resolve by name, then by former name** (§4): a file name the
    mapping does not name resolves through
    `Portfolixir.Lifecycle.AccountNames.resolve/2`, the function the
    preview's prefill uses — the exact live name of the kind in the
    portfolio, then a former name. An ambiguous tier is refused when a row
    that passed the hash check needs the name (`{:ambiguous_account_name,
    kind, name, ids}`), never guessed.
  - **The account-identity lock first** (§4): both apply paths take the
    portfolio's `AccountNames.lock_identity/2` right after the portfolio is
    known, before any row is read for update or inserted, so an import keeps
    the lock order of every other writer of account names (the advisory lock,
    then row locks) and a concurrent rename waits instead of deadlocking.
  - **The mapping is revalidated and remembered at apply start** (§4, §10):
    an `{:existing, id}` account that has gone since the preview aborts with
    `{:resolution_diverged, %{kind, name, id, merged_into}}` (the survivor
    when a merge record names one); then every `{:existing, id}` choice whose
    file name differs from the account's is remembered as a former name of
    it (`remember`, on by default per name), reported in `remembered_names`.
  - **Internal transfers are void** (§5): a `cash_transfer` or
    `security_transfer` whose two legs resolve to one account is skipped
    unconditionally and reported in `internal_transfers`, never an abort.
  - **The in-run collapse key is scoped by the file's account names**
    (§6): `{dedup_key, time, pp_portfolio_name, pp_account_name,
    pp_counter_portfolio_name, pp_counter_account_name}`.

  `already_imported` counts the skipped duplicates per layer (`:hash`,
  `:retired`, `:economics`); `reimport_counts/2` is the same count before
  the apply, per file account and depot name, for the preview.

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
  - Resolves cash accounts and depots by name, then by former name,
    *within the chosen portfolio*. Missing ones are created with their first
    inserted row, through the name guard.
  - Inserts one ledger row per entry, branching by kind.
  - Skips degenerate rows that can never form a valid transaction — a
    cash kind with a zero or missing gross_amount (e.g. a 0 EUR tax
    line), or a kind no export carries (a balance anchor or a split,
    ADR-0050 §1) — recording each in `skipped_entries` with its row and a
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
  alias Portfolixir.Fx
  alias Portfolixir.Imports.Entry
  alias Portfolixir.Imports.ImportHash
  alias Portfolixir.Imports.Preview
  alias Portfolixir.Imports.SecurityResolver
  alias Portfolixir.Journal
  alias Portfolixir.Ledger.SettlementGuard
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Lifecycle
  alias Portfolixir.Lifecycle.AccountNames
  alias Portfolixir.Lifecycle.RetiredImportHash
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
              skipped_entries: [],
              duplicate_entries: [],
              # ADR-0050 §3: the skipped duplicates counted per layer.
              already_imported: %{hash: 0, retired: 0, economics: 0},
              # ADR-0050 §5: transfers whose two legs resolve to one account.
              internal_transfers: [],
              # ADR-0050 §4: what remembering each remapped file name did —
              # :appended, {:moved, from_id} or {:not_offered, live_on_id}.
              remembered_names: []

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

  @typedoc """
  The per-name "remember" of the mapping (ADR-0050 §4), **on by default**: a
  file name absent here, or `true`, is remembered as a former name of the
  `{:existing, id}` account it is mapped onto; `false` keeps the remap to this
  import.
  """
  @type remember :: %{
          optional(:cash_accounts) => %{String.t() => boolean()},
          optional(:depots) => %{String.t() => boolean()}
        }

  @type mapped_apply_params :: %{
          optional(:portfolio) => portfolio_choice(),
          required(:cash_accounts) => %{String.t() => account_choice()},
          required(:depots) => %{String.t() => depot_mapping()},
          optional(:remember) => remember(),
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
           :ok <- AccountNames.lock_identity(portfolio_id),
           {:ok, cash_plan} <-
             plan_mapped_cash(params.cash_accounts, cash_currencies, default_currency),
           {:ok, depot_plan} <- plan_mapped_depots(params.depots, params.cash_accounts),
           :ok <- revalidate_mapped_accounts(params, portfolio_id),
           state =
             portfolio_id
             |> base_state(default_currency, params, result)
             |> Map.merge(cash_plan)
             |> Map.merge(depot_plan),
           {:ok, state} <- remember_mapped_names(state, params),
           state = resolve_unmapped_names(state, flat_entries),
           {:ok, state} <- execute_security_mappings(flat_entries, state),
           {:ok, final_state} <- reduce_entries(flat_entries, state),
           {:ok, final_result} <- apply_bucket_tag(bucket_tag, final_state.result) do
        final_result
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> enrich_after_commit()
  end

  # Original auto-resolve path: kept for the JSON-API entry point and
  # the existing applier_test.exs suite. Resolves every file name by live
  # name, then former name (ADR-0050 §4), and creates missing securities,
  # cash accounts and depots inside the chosen portfolio with the PP
  # names verbatim, each with its first inserted row. Depots without an
  # explicit cash account fall back to the first cash account in the
  # portfolio (matching counter_depot behaviour before mapping was
  # introduced).
  def apply(%Preview{entries: entries}, %{portfolio_id: portfolio_id} = params)
      when is_integer(portfolio_id) do
    default_currency = Map.get(params, :default_currency_code, "EUR")
    flat_entries = Entry.flatten(entries)

    Repo.transaction(fn ->
      :ok = AccountNames.lock_identity(portfolio_id)

      state =
        base_state(portfolio_id, default_currency, params, %Result{})
        |> Map.merge(%{
          cash_by_name: %{},
          pending_cash: %{},
          depot_by_name: %{},
          pending_depots: %{}
        })
        |> resolve_unmapped_names(flat_entries)

      with {:ok, state} <- execute_security_mappings(flat_entries, state),
           {:ok, final_state} <- reduce_entries(flat_entries, state) do
        final_state.result
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> enrich_after_commit()
  end

  @doc """
  The already-imported counts of a parsed preview, before any apply (ADR-0050
  §3): every row classified by the first check the applier would run on it —
  `:unimportable` (a cash kind without a positive amount, or a kind no export
  carries), `:hash` (a
  transaction holds its content hash), `:retired` (a merge retired it) or
  `:new` — in `total`, and again per file cash-account name (`cash_accounts`)
  and per file depot name (`depots`), where a row counts under every name it
  carries on either leg. Read-only; the hash names `portfolio_id`, and without
  one every importable row is new.

  A tax refund split off a row counts by its own hashes, as the apply judges
  it, and `:unimportable` with a row that is (E25 S5, F37). A row repeating
  an earlier row of the same file exactly (the same content hash) counts
  `:hash`: the apply skips it on that layer once the first copy is booked,
  or on whatever later layer skipped the first. A row counted
  `:new` may still be skipped at apply by a later layer (an equal economic
  booking, an internal transfer, an in-run collapse or an undecided
  security); an account whose rows are all `:hash`, `:retired` or
  `:unimportable` is never created.
  """
  @spec reimport_counts(Preview.t(), integer() | nil) :: %{
          total: layer_counts(),
          cash_accounts: %{String.t() => layer_counts()},
          depots: %{String.t() => layer_counts()}
        }
  def reimport_counts(%Preview{entries: entries}, portfolio_id) do
    flat_entries = Entry.flatten(entries)
    layers = row_layers(flat_entries, portfolio_id)
    empty = %{hash: 0, retired: 0, unimportable: 0, new: 0}

    initial = {%{total: empty, cash_accounts: %{}, depots: %{}}, MapSet.new(), nil}

    # A companion counts by its own hashes, as the apply judges it; one whose
    # row is unimportable is skipped with it (E25 S5, F37).
    {counts, _seen, _parent_layer} =
      flat_entries
      |> Enum.zip(layers)
      |> Enum.reduce(initial, fn
        {%Entry{companion_index: nil} = entry, layer_key}, {acc, seen, _parent_layer} ->
          {layer, seen} = in_file_repeat(layer_key, seen)
          {count_row(acc, entry, layer, empty), seen, layer}

        {entry, _layer_key}, {acc, seen, parent_layer}
        when parent_layer in [nil, :unimportable] ->
          {count_row(acc, entry, :unimportable, empty), seen, parent_layer}

        {entry, layer_key}, {acc, seen, parent_layer} ->
          {layer, seen} = in_file_repeat(layer_key, seen)
          {count_row(acc, entry, layer, empty), seen, parent_layer}
      end)

    counts
  end

  defp count_row(acc, entry, layer, empty) do
    bump = &Map.update!(&1, layer, fn n -> n + 1 end)

    %{
      total: bump.(acc.total),
      cash_accounts:
        count_names(
          acc.cash_accounts,
          [entry.pp_account_name, entry.pp_counter_account_name],
          empty,
          bump
        ),
      depots:
        count_names(
          acc.depots,
          [entry.pp_portfolio_name, entry.pp_counter_portfolio_name],
          empty,
          bump
        )
    }
  end

  # A new row whose content hash an earlier row of the file already carries
  # is held by the time the apply reaches it.
  defp in_file_repeat({:new, key}, seen) do
    if MapSet.member?(seen, key), do: {:hash, seen}, else: {:new, MapSet.put(seen, key)}
  end

  defp in_file_repeat({layer, _key}, seen), do: {layer, seen}

  @typedoc "Rows per first-check layer, as `reimport_counts/2` counts them."
  @type layer_counts :: %{
          hash: non_neg_integer(),
          retired: non_neg_integer(),
          unimportable: non_neg_integer(),
          new: non_neg_integer()
        }

  defp count_names(acc, names, empty, bump) do
    names
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.reduce(acc, fn name, acc -> Map.update(acc, name, bump.(empty), bump) end)
  end

  # One query per layer over the whole file, instead of one per row. A row
  # whose fields carry the hash's separator also consults the hash the
  # Sprint 15 formula gave it (E25 S5, F36), and a companion its own hashes
  # (F37), as the apply does. Answers `{layer, key}` per row, in file order:
  # the key finds a repeat inside the file, and stands in for the hash with
  # no portfolio yet (no real portfolio has id 0).
  defp row_layers(flat_entries, portfolio_id) do
    identities = row_identities(flat_entries, portfolio_id || 0)

    lookups =
      if is_integer(portfolio_id),
        do: Enum.flat_map(identities, fn {_key, hashes} -> hashes end),
        else: []

    held = held_hashes(Transaction, lookups)
    retired = held_hashes(RetiredImportHash, lookups)

    Enum.zip_with(flat_entries, identities, fn entry, {key, hashes} ->
      layer =
        cond do
          unimportable(entry) != nil -> :unimportable
          Enum.any?(hashes, &MapSet.member?(held, &1)) -> :hash
          Enum.any?(hashes, &MapSet.member?(retired, &1)) -> :retired
          true -> :new
        end

      {layer, key}
    end)
  end

  # Each row's content hash and every stored hash that identifies it; a
  # companion is hashed with the row before it.
  defp row_identities(flat_entries, portfolio_id) do
    {identities, _parent_hash} =
      Enum.map_reduce(flat_entries, nil, fn
        %Entry{companion_index: nil} = entry, _parent_hash ->
          hash = ImportHash.compute(entry, portfolio_id)
          hashes = Enum.reject([hash, ImportHash.legacy(entry, portfolio_id)], &is_nil/1)
          {{hash, hashes}, hash}

        %Entry{companion_index: index} = entry, parent_hash ->
          hash = ImportHash.companion(parent_hash, index, entry, portfolio_id)
          {{hash, companion_hashes(hash, entry, portfolio_id)}, parent_hash}
      end)

    identities
  end

  defp held_hashes(_schema, []), do: MapSet.new()

  defp held_hashes(schema, hashes) do
    from(row in schema, where: row.import_hash in ^hashes, select: row.import_hash)
    |> Repo.all()
    |> MapSet.new()
  end

  # Shared per-run state. The security index is loaded once inside the import
  # transaction; `pristine_index` stays the untouched snapshot the §2
  # preview→apply revalidation recomputes against, while `live_index` absorbs
  # securities created (or ISIN-changed via an override) during this run so
  # later rows of the same file resolve consistently. `key_resolutions`
  # memoizes the decision per unique reference key — N:1 friendly and
  # guaranteed stable within one run.
  #
  # Accounts (ADR-0050 §4): `cash_by_name` and `depot_by_name` map a file name
  # to an account id that exists — mapped onto an existing record, found by
  # name, or materialized earlier in this run. `pending_cash` and
  # `pending_depots` hold the `create` choices not yet materialized; a file
  # name in neither is unmatched and is created by name, lazily too.
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
      # ADR-0050 §4: `{:cash | :depot, file_name}` => the ids of an ambiguous
      # tier, refused when a row needs the name.
      ambiguous_names: %{},
      result: result,
      existing_dedup_keys: load_existing_dedup_keys(portfolio_id)
    }
  end

  # The recorders prepend (E25 S5, F40): appending copied every list once per
  # row, quadratic inside the import transaction on a large re-import. Each
  # list is reversed once here, into the file's row order.
  @recorded_lists [
    :skipped_entries,
    :duplicate_entries,
    :collapsed_duplicates,
    :unresolved_entries,
    :internal_transfers,
    :alias_matches,
    :security_overrides,
    :remembered_names
  ]

  defp enrich_after_commit({:ok, %Result{} = result}) do
    created_ids = Enum.reverse(result.created_security_ids)
    resolved_ids = result.resolved_security_ids |> Enum.reverse() |> Enum.uniq()

    Catalog.enrich_security_ids_async(created_ids)
    Catalog.enqueue_missing_security_logos_async()

    result =
      Enum.reduce(@recorded_lists, result, fn field, acc ->
        Map.update!(acc, field, &Enum.reverse/1)
      end)

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

  # The mapping is validated up front and nothing is created (ADR-0050 §4): an
  # `{:existing, id}` choice binds the file name to that account, a
  # `{:create, name}` choice is held pending until a row that names it is
  # inserted.
  defp plan_mapped_cash(mapping, cash_currencies, default_currency) do
    Enum.reduce_while(mapping, {:ok, %{cash_by_name: %{}, pending_cash: %{}}}, fn
      {pp_name, {:existing, id}}, {:ok, plan} when is_integer(id) ->
        {:cont, {:ok, put_in(plan, [:cash_by_name, pp_name], id)}}

      {pp_name, {:create, name}}, {:ok, plan} when is_binary(name) ->
        currency = Map.get(cash_currencies, pp_name, default_currency)
        pending = %{name: name, currency_code: currency}
        {:cont, {:ok, put_in(plan, [:pending_cash, pp_name], pending)}}

      {pp_name, other}, _acc ->
        {:halt, {:error, {:invalid_cash_choice, pp_name, other}}}
    end)
  end

  defp plan_mapped_depots(mapping, cash_mapping) do
    Enum.reduce_while(mapping, {:ok, %{depot_by_name: %{}, pending_depots: %{}}}, fn
      {pp_name, depot_spec}, {:ok, plan} ->
        with {:ok, cash_ref} <- depot_cash_ref(depot_spec.cash, cash_mapping),
             {:ok, plan} <- plan_depot_choice(plan, pp_name, depot_spec.target, cash_ref) do
          {:cont, {:ok, plan}}
        else
          {:error, _} = err -> {:halt, err}
        end
    end)
  end

  defp depot_cash_ref(cash_ref, cash_mapping) when is_binary(cash_ref) do
    if Map.has_key?(cash_mapping, cash_ref),
      do: {:ok, {:pp, cash_ref}},
      else: {:error, {:unresolved_depot_cash_ref, cash_ref}}
  end

  defp depot_cash_ref({:existing, id}, _cash_mapping) when is_integer(id),
    do: {:ok, {:existing, id}}

  defp depot_cash_ref(other, _cash_mapping), do: {:error, {:invalid_depot_cash_ref, other}}

  defp plan_depot_choice(plan, pp_name, {:existing, id}, _cash_ref)
       when is_integer(id) do
    {:ok, put_in(plan, [:depot_by_name, pp_name], id)}
  end

  defp plan_depot_choice(plan, pp_name, {:create, name}, cash_ref) when is_binary(name) do
    {:ok, put_in(plan, [:pending_depots, pp_name], %{name: name, cash: cash_ref})}
  end

  defp plan_depot_choice(_plan, pp_name, other, _cash_ref) do
    {:error, {:invalid_depot_choice, pp_name, other}}
  end

  # --- the mapping at apply start (ADR-0050 §4, §10) ---

  # Stale-mapping revalidation (§10): every account the mapping names by id
  # must still exist in the import's portfolio. One that has gone aborts the
  # apply before anything is written, naming the survivor at the live end of
  # its merge chain when a merge record says so; one in another portfolio is
  # an invalid choice, as it always was.
  defp revalidate_mapped_accounts(params, portfolio_id) do
    cash =
      for {pp_name, {:existing, id}} <- params.cash_accounts,
          do: {:cash_account, CashAccount, pp_name, id}

    depots =
      for {pp_name, %{target: target, cash: cash}} <- params.depots,
          {kind, schema, id} <- mapped_depot_ids(target, cash),
          do: {kind, schema, pp_name, id}

    (cash ++ depots)
    |> Enum.sort()
    |> Enum.find_value(:ok, fn {kind, schema, pp_name, id} ->
      case Repo.one(from(a in schema, where: a.id == ^id, select: a.portfolio_id)) do
        ^portfolio_id ->
          nil

        nil ->
          diverged = %{
            kind: kind,
            name: pp_name,
            id: id,
            merged_into: Lifecycle.merged_into(kind, id)
          }

          {:error, {:resolution_diverged, diverged}}

        _another_portfolio ->
          {:error, {:invalid_account_choice, kind, pp_name, {:existing, id}}}
      end
    end)
  end

  defp mapped_depot_ids(target, cash) do
    Enum.flat_map(
      [{:securities_account, SecuritiesAccount, target}, {:cash_account, CashAccount, cash}],
      fn
        {kind, schema, {:existing, id}} when is_integer(id) -> [{kind, schema, id}]
        _create_or_file_name -> []
      end
    )
  end

  # The remembered remap (§4), run from the mapping at apply start so it takes
  # effect when every row of the name is a hash hit: each `{:existing, id}`
  # choice is remembered unless its per-name "remember" is false.
  # `AccountNames.remember/4` decides what that means — nothing for the
  # account's own names, an append, a move from another account's former
  # names, or nothing for another account's live name — and every outcome but
  # the first is reported.
  defp remember_mapped_names(state, params) do
    remember = Map.get(params, :remember, %{})

    cash =
      for {pp_name, {:existing, id}} <- params.cash_accounts,
          remember?(remember, :cash_accounts, pp_name),
          do: {:cash_account, CashAccount, pp_name, id}

    depots =
      for {pp_name, %{target: {:existing, id}}} <- params.depots,
          remember?(remember, :depots, pp_name),
          do: {:securities_account, SecuritiesAccount, pp_name, id}

    (cash ++ depots)
    |> Enum.sort()
    |> Enum.reduce_while({:ok, state}, fn {kind, schema, pp_name, id}, {:ok, state} ->
      case AccountNames.remember(Actor.import_session(), schema, id, pp_name) do
        {:ok, outcome} when outcome in [:same_name, :already] ->
          {:cont, {:ok, state}}

        {:ok, outcome} ->
          {:cont, {:ok, record_remembered(state, kind, pp_name, id, outcome)}}

        {:error, reason} ->
          {:halt, {:error, {:remember_failed, kind, pp_name, reason}}}
      end
    end)
  end

  defp remember?(remember, group, pp_name) do
    remember |> Map.get(group, %{}) |> Map.get(pp_name, true) != false
  end

  defp record_remembered(state, kind, pp_name, account_id, outcome) do
    remembered = %{kind: kind, name: pp_name, account_id: account_id, outcome: outcome}

    Map.update!(state, :result, fn %Result{} = r ->
      %Result{r | remembered_names: [remembered | r.remembered_names]}
    end)
  end

  # Account resolution (§4): every file name the mapping does not name
  # resolves through the function the preview's prefill uses — the exact live
  # name of the kind in the portfolio, then a former name. A name found by
  # neither stays unmatched and is created lazily, through the name guard; an
  # ambiguous tier is held, and refused when a row needs the name.
  defp resolve_unmapped_names(state, flat_entries) do
    state
    |> resolve_names(
      :cash,
      file_names(flat_entries, [:pp_account_name, :pp_counter_account_name]),
      AccountNames.index(CashAccount, state.portfolio_id),
      {:cash_by_name, :pending_cash}
    )
    |> resolve_names(
      :depot,
      file_names(flat_entries, [:pp_portfolio_name, :pp_counter_portfolio_name]),
      AccountNames.index(SecuritiesAccount, state.portfolio_id),
      {:depot_by_name, :pending_depots}
    )
  end

  defp file_names(flat_entries, fields) do
    flat_entries
    |> Enum.flat_map(fn entry -> Enum.map(fields, &Map.fetch!(entry, &1)) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp resolve_names(state, kind, names, index, {by_name, pending}) do
    Enum.reduce(names, state, fn pp_name, state ->
      if Map.has_key?(state[by_name], pp_name) or Map.has_key?(state[pending], pp_name) do
        state
      else
        case AccountNames.resolve(index, pp_name) do
          {:ok, id, _tier} -> put_in(state, [by_name, pp_name], id)
          :none -> state
          {:ambiguous, _tier, ids} -> put_in(state, [:ambiguous_names, {kind, pp_name}], ids)
        end
      end
    end)
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
    initial_state = Map.merge(initial_state, %{parent: nil, outcome: nil})

    Enum.reduce_while(entries, {:ok, initial_state}, fn entry, {:ok, state} ->
      case process_row(entry, state) do
        {:ok, state} -> {:cont, {:ok, state}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  # A row of the file is processed on its own and remembered as the parent of
  # the companions `Entry.flatten/1` placed right after it; a companion (a tax
  # refund split off that row) is judged after its parent (E25 S5, F37). The recorders
  # and the insert leave the row's outcome in `state.outcome`.
  defp process_row(%Entry{companion_index: nil} = entry, state) do
    with {:ok, state} <- process_entry(entry, %{state | outcome: nil}) do
      parent = %{
        row: entry.source_row,
        hash: ImportHash.compute(entry, state.portfolio_id),
        outcome: state.outcome
      }

      {:ok, %{state | parent: parent}}
    end
  end

  defp process_row(%Entry{companion_index: index} = entry, state),
    do: process_companion(entry, index, state)

  # E25 S5 (F37, and its review round): a companion is hashed with its parent
  # — the parent's hash and its position fold into its own — so two equal
  # refunds split off two different rows hash apart. Once its parent was
  # imported or found already booked, the companion is judged by its own
  # identity, never by its parent's outcome: the parent's hash and economic
  # key leave the split-off refund out, so they cannot say whether the refund
  # is booked. It is skipped when a transaction or a merge holds its hash or
  # the hash an import before this change gave it (a refund stored as a row
  # of its own), or when a booking stored before the run has its economic
  # key; it collapses onto an earlier companion of the file only when its
  # parent collapsed onto that companion's parent; otherwise it books. A
  # companion of a row that is not imported (unimportable, an internal
  # transfer, an undecided security) is skipped with it.
  defp process_companion(entry, index, %{parent: %{outcome: outcome, hash: parent_hash}} = state)
       when outcome in [:inserted, :collapsed] or
              (is_tuple(outcome) and elem(outcome, 0) == :duplicate) do
    case unimportable(entry) do
      reason when is_binary(reason) ->
        {:ok, record_skip(state, entry, reason)}

      nil ->
        import_hash = ImportHash.companion(parent_hash, index, entry, state.portfolio_id)

        case hash_layer(companion_hashes(import_hash, entry, state.portfolio_id)) do
          nil -> insert_companion(entry, import_hash, outcome == :collapsed, state)
          layer -> {:ok, record_duplicate(state, entry, layer)}
        end
    end
  end

  defp process_companion(
         entry,
         _index,
         %{parent: %{outcome: {:unresolved, key, reason}}} = state
       ),
       do: {:ok, record_unresolved(state, entry, key, reason)}

  defp process_companion(entry, _index, state) do
    parent_row = state.parent && state.parent.row

    {:ok,
     record_skip(
       state,
       entry,
       "skipped: the row it was split from (row #{parent_row}) was not imported"
     )}
  end

  # Every hash that identifies a stored companion: its own, and the one the
  # Sprint 15 formula gave it as a row of its own (a standalone refund row
  # with the same fields holds that one too — the closed direction, as for
  # F36's legacy hash).
  defp companion_hashes(import_hash, %Entry{} = entry, portfolio_id) do
    Enum.reject(
      [
        import_hash,
        ImportHash.compute(entry, portfolio_id),
        ImportHash.legacy(entry, portfolio_id)
      ],
      &is_nil/1
    )
  end

  # A companion no stored hash holds: its accounts and security are its
  # parent's, resolved as any row's are. It is checked against the bookings
  # stored before the run (the economic key), and against the file's earlier
  # rows only when its parent collapsed: two equal refunds of two different
  # rows would share the in-run key, and must both book.
  defp insert_companion(%Entry{} = entry, import_hash, collapse?, state) do
    refs = account_refs(entry, state)

    case ambiguous_ref(refs) do
      nil ->
        case resolve_security(entry, state) do
          {:skip, state} ->
            {:ok, state}

          {:ok, state, security_id} ->
            attrs =
              build_transaction_attrs(
                entry,
                state,
                Map.put(refs, :security_id, security_id),
                import_hash
              )

            insert_transaction(entry, attrs, state, collapse?)

          {:error, _} = error ->
            error
        end

      ambiguous ->
        {:error, ambiguous_account_error(ambiguous, state)}
    end
  end

  # Kinds that move shares but settle no cash, so they legitimately carry no
  # gross_amount. Every other importable kind needs a positive gross_amount.
  @cashless_kinds ~w(inbound_delivery outbound_delivery security_transfer)

  # The kinds a Portfolio Performance export carries — the parsers map to no
  # other. A balance anchor or a split is never imported (ADR-0050 §1): an
  # entry of any other kind is a reported skip, never a row and never a crash.
  @importable_kinds ~w(buy sell dividend interest deposit removal fee tax tax_refund
                       cash_transfer inbound_delivery outbound_delivery security_transfer)

  # The order of the checks is the re-import contract (ADR-0050 §2, §3): an
  # unimportable row first, then the content hash — held by a transaction or
  # retired by a merge — before anything resolves or is created.
  defp process_entry(%Entry{} = entry, state) do
    case unimportable(entry) do
      # A degenerate row (e.g. a 0 EUR tax line) can't become a valid
      # transaction, but it must not abort the whole atomic import (#482).
      # Skip it and report it; genuine changeset failures still roll back.
      reason when is_binary(reason) ->
        {:ok, record_skip(state, entry, reason)}

      nil ->
        import_hash = ImportHash.compute(entry, state.portfolio_id)
        legacy_hash = ImportHash.legacy(entry, state.portfolio_id)

        case hash_layer(Enum.reject([import_hash, legacy_hash], &is_nil/1)) do
          nil -> do_process_entry(entry, import_hash, state)
          layer -> {:ok, record_duplicate(state, entry, layer)}
        end
    end
  end

  # Why an entry can never become a transaction, or nil.
  defp unimportable(%Entry{kind: kind}) when kind not in @importable_kinds,
    do: "skipped: #{kind} is never imported"

  defp unimportable(%Entry{kind: kind, gross_amount: amount}) do
    if kind not in @cashless_kinds and
         (is_nil(amount) or Decimal.compare(amount, Decimal.new(0)) != :gt),
       do: "skipped: zero or missing gross_amount for #{kind}"
  end

  # `:hash` when a transaction holds the hash (an exact re-insert, or an exact
  # duplicate earlier in this file: the query sees this transaction's own
  # inserts), `:retired` when a merge removed the row that held it (§3).
  #
  # A row whose fields carry the hash's separator is also looked up by the
  # hash the Sprint 15 formula gave it (E25 S5, F36): a row stored before the
  # hash became injective keeps being recognised, so nothing books twice.
  defp hash_layer(hashes) do
    cond do
      Repo.exists?(from(t in Transaction, where: t.import_hash in ^hashes)) -> :hash
      Repo.exists?(from(r in RetiredImportHash, where: r.import_hash in ^hashes)) -> :retired
      true -> nil
    end
  end

  defp record_skip(state, %Entry{} = entry, reason) when is_binary(reason) do
    state
    |> Map.put(:outcome, :skipped)
    |> Map.update!(:result, fn %Result{} = r ->
      %Result{
        r
        | skipped_entries: [%{row: entry.source_row, reason: reason} | r.skipped_entries]
      }
    end)
  end

  # Past the hash: the accounts resolve first, without creating anything, so
  # an internal transfer (§5) is recognised before its security could be
  # created; then the security; then the economic and in-run layers decide;
  # only a row that inserts materializes the accounts it names (§4).
  defp do_process_entry(%Entry{} = entry, import_hash, state) do
    refs = account_refs(entry, state)

    cond do
      internal_transfer?(entry, refs) ->
        {:ok, record_internal_transfer(state, entry)}

      ambiguous = ambiguous_ref(refs) ->
        {:error, ambiguous_account_error(ambiguous, state)}

      true ->
        resolve_and_insert(entry, import_hash, refs, state)
    end
  end

  defp resolve_and_insert(entry, import_hash, refs, state) do
    case resolve_security(entry, state) do
      # A surfaced-but-undecided security (§2 fail closed): the entry is
      # reported in `unresolved_entries` and creates nothing.
      {:skip, state} ->
        {:ok, state}

      {:ok, state, security_id} ->
        ids = Map.put(refs, :security_id, security_id)

        insert_transaction(
          entry,
          build_transaction_attrs(entry, state, ids, import_hash),
          state
        )

      {:error, _} = error ->
        error
    end
  end

  # ADR-0050 §4: an ambiguous name is never guessed. The row passed the hash
  # check, so it needs the name, and the apply refuses it unmapped.
  defp ambiguous_ref(refs) do
    Enum.find_value(refs, fn
      {_leg, {:ambiguous, _kind, _pp_name} = ref} -> ref
      _other -> nil
    end)
  end

  defp ambiguous_account_error({:ambiguous, kind, pp_name}, state) do
    ids = Map.fetch!(state.ambiguous_names, {kind, pp_name})
    {:ambiguous_account_name, account_kind(kind), pp_name, ids}
  end

  defp account_kind(:cash), do: :cash_account
  defp account_kind(:depot), do: :securities_account

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

  # A remap ran at apply start and left its resolution cached, so the only
  # mapping a first resolution can meet is a `:create` acknowledgment.
  defp first_resolution(entry, ref, key, state) do
    case Map.fetch(state.security_mappings, key) do
      {:ok, :create} ->
        create_security(entry, ref, key, state)

      {:ok, _executed_at_start} ->
        {:error, {:invalid_security_mapping, key}}

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

  # ADR-0050 §3: the operator's remaps — and the ISIN change a remap records —
  # run from the mapping at apply start, in the order the file first names
  # their keys, not from the first row that reaches them, so a key whose rows
  # are all hash hits still gets the decision the preview confirmed. A
  # `:create` acknowledgment stays lazy: it creates on the first row that
  # reaches it, because a security no inserted row needs would be exactly the
  # duplicate the hash-first order prevents. A mapping of a key the file does
  # not carry is not executed.
  #
  # One key standing for two references of the file fails closed (E25 S5,
  # F36): the apply is refused before any row, never decided twice.
  defp execute_security_mappings(flat_entries, state) do
    with {:ok, keyed} <-
           flat_entries |> Enum.flat_map(&file_ref/1) |> SecurityResolver.unique_keys() do
      Enum.reduce_while(keyed, {:ok, state}, fn {key, ref}, {:ok, state} ->
        case execute_security_mapping(ref, key, Map.get(state.security_mappings, key), state) do
          {:ok, state} -> {:cont, {:ok, state}}
          {:error, _} = error -> {:halt, error}
        end
      end)
    end
  end

  defp file_ref(%Entry{security: nil}), do: []

  defp file_ref(%Entry{} = entry) do
    ref = SecurityResolver.effective_ref(entry)
    if SecurityResolver.blank_ref?(ref), do: [], else: [ref]
  end

  defp execute_security_mapping(_ref, _key, nil, state), do: {:ok, state}
  defp execute_security_mapping(_ref, _key, :create, state), do: {:ok, state}

  defp execute_security_mapping(ref, key, {:existing, id}, state) when is_integer(id) do
    apply_existing_mapping(ref, key, id, false, state)
  end

  defp execute_security_mapping(ref, key, {:existing, id, :record_isin_change}, state)
       when is_integer(id) do
    apply_existing_mapping(ref, key, id, true, state)
  end

  defp execute_security_mapping(_ref, key, _other, _state) do
    {:error, {:invalid_security_mapping, key}}
  end

  defp apply_existing_mapping(ref, key, id, record_change?, state) do
    case Map.fetch(state.live_index.securities_by_id, id) do
      :error ->
        # ADR-0050 §10: a remap onto a security merged away since the preview
        # names the survivor; one deleted without a merge is invalid.
        case Lifecycle.merged_into(:security, id) do
          nil ->
            {:error, {:invalid_security_mapping, key}}

          survivor ->
            diverged = %{kind: :security, key: key, id: id, merged_into: survivor}
            {:error, {:resolution_diverged, diverged}}
        end

      {:ok, security} ->
        case maybe_record_isin_change(state, security, ref, key, record_change?) do
          {:ok, state, security, recorded?} ->
            state =
              state
              |> cache_resolution(key, {:security, security.id, :override})
              |> track_security_override(key, security.id, recorded?)

            {:ok, state}

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
      %Result{r | alias_matches: [match | r.alias_matches]}
    end)
  end

  defp maybe_record_alias(state, _entry, _ref, _tier, _security_id), do: state

  defp record_unresolved(state, %Entry{} = entry, key, reason) do
    state
    |> Map.put(:outcome, {:unresolved, key, reason})
    |> Map.update!(:result, fn %Result{} = r ->
      unresolved = %{row: entry.source_row, key: key, reason: reason}
      %Result{r | unresolved_entries: [unresolved | r.unresolved_entries]}
    end)
  end

  defp track_security_override(state, key, security_id, recorded_isin_change?) do
    Map.update!(state, :result, fn %Result{} = r ->
      override = %{
        key: key,
        security_id: security_id,
        recorded_isin_change: recorded_isin_change?
      }

      %Result{r | security_overrides: [override | r.security_overrides]}
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

  # --- account resolution (ADR-0050 §4: resolving creates nothing) ---

  # Each of a row's four account names resolves to the id of an account that
  # exists (mapped onto an existing record, found by live or former name, or
  # materialized earlier in this run), to `{:ambiguous, kind, pp_name}` for a
  # name whose resolution tier names several accounts, or to
  # `{:pending, :cash | :depot, pp_name}`, one a `create` choice or an
  # unmatched name would create. Two legs are one account when their refs are
  # equal: the same id, or the same file name.
  defp account_refs(%Entry{} = entry, state) do
    %{
      cash_id: account_ref(:cash, entry.pp_account_name, state.cash_by_name, state),
      counter_cash_id:
        account_ref(:cash, entry.pp_counter_account_name, state.cash_by_name, state),
      depot_id: account_ref(:depot, entry.pp_portfolio_name, state.depot_by_name, state),
      counter_depot_id:
        account_ref(:depot, entry.pp_counter_portfolio_name, state.depot_by_name, state)
    }
  end

  defp account_ref(_kind, nil, _by_name, _state), do: nil

  defp account_ref(kind, pp_name, by_name, state) do
    cond do
      Map.has_key?(by_name, pp_name) -> Map.fetch!(by_name, pp_name)
      Map.has_key?(state.ambiguous_names, {kind, pp_name}) -> {:ambiguous, kind, pp_name}
      true -> {:pending, kind, pp_name}
    end
  end

  # ADR-0050 §5: a transfer whose two legs resolve to one account can never be
  # inserted (its CHECK rejects equal legs), and it is economically void.
  defp internal_transfer?(%Entry{kind: "cash_transfer"}, %{cash_id: a, counter_cash_id: b}),
    do: not is_nil(a) and a == b

  defp internal_transfer?(%Entry{kind: "security_transfer"}, %{depot_id: a, counter_depot_id: b}),
    do: not is_nil(a) and a == b

  defp internal_transfer?(_entry, _refs), do: false

  defp record_internal_transfer(state, %Entry{} = entry) do
    {pp_name, pp_counter_name} =
      case entry.kind do
        "security_transfer" -> {entry.pp_portfolio_name, entry.pp_counter_portfolio_name}
        _cash_transfer -> {entry.pp_account_name, entry.pp_counter_account_name}
      end

    transfer = %{
      row: entry.source_row,
      kind: entry.kind,
      date: entry.date,
      gross_amount: entry.gross_amount,
      quantity: entry.quantity,
      currency_code: entry.currency_code,
      security_name: entry.security && entry.security[:name],
      pp_name: pp_name,
      pp_counter_name: pp_counter_name,
      reason: "skipped: both legs resolve to one account, so the transfer is void"
    }

    state
    |> Map.put(:outcome, :skipped)
    |> Map.update!(:result, fn %Result{} = r ->
      %Result{r | internal_transfers: [transfer | r.internal_transfers]}
    end)
  end

  # --- lazy creation (ADR-0050 §4) ---

  # Runs only for a row that inserts: every pending account the row's attrs
  # name is created now, a depot's linked cash account with it where that is
  # pending too. A pending depot of the primary leg links to the row's own cash
  # account; an unmapped counter depot falls back to the portfolio's first
  # cash account (a SECURITY_TRANSFER may carry no cash side). The user can
  # re-wire either after the import.
  defp materialize_accounts(%Entry{} = entry, attrs, state) do
    with {:ok, state, attrs} <-
           materialize(attrs, :cash_account_id, state, &materialize_cash(&1, entry, &2)),
         {:ok, state, attrs} <-
           materialize(attrs, :counter_cash_account_id, state, &materialize_cash(&1, entry, &2)),
         {:ok, state, attrs} <-
           materialize(
             attrs,
             :securities_account_id,
             state,
             &materialize_depot(&1, entry, &2, :row)
           ) do
      materialize(
        attrs,
        :counter_securities_account_id,
        state,
        &materialize_depot(&1, entry, &2, :counter)
      )
    end
  end

  defp materialize(attrs, field, state, create) do
    case Map.get(attrs, field) do
      {:pending, _kind, pp_name} ->
        with {:ok, state, id} <- create.(pp_name, state) do
          {:ok, state, Map.put(attrs, field, id)}
        end

      _id_or_nil ->
        {:ok, state, attrs}
    end
  end

  defp materialize_cash(pp_name, %Entry{} = entry, state) do
    case Map.fetch(state.cash_by_name, pp_name) do
      {:ok, id} ->
        {:ok, state, id}

      :error ->
        # A `create` choice carries its name and the currency of the file's
        # bookings on that account; an unmatched name is created as named, in
        # the currency of the row that creates it.
        %{name: name, currency_code: currency} =
          Map.get(state.pending_cash, pp_name, %{
            name: pp_name,
            currency_code: entry.currency_code || state.default_currency
          })

        create_cash(pp_name, name, currency, state)
    end
  end

  defp create_cash(pp_name, name, currency, state) do
    attrs = %{portfolio_id: state.portfolio_id, name: name, currency_code: currency}

    case Portfolios.create_cash_account(Actor.import_session(), attrs) do
      {:ok, cash} ->
        state =
          state
          |> Map.update!(:cash_by_name, &Map.put(&1, pp_name, cash.id))
          |> Map.update!(:pending_cash, &Map.delete(&1, pp_name))
          |> bump_result(:created_cash_accounts)
          |> track_created_account(:created_cash_account_ids, cash.id)

        {:ok, state, cash.id}

      {:error, changeset} ->
        {:error, {:cash_create_failed, name, changeset}}
    end
  end

  defp materialize_depot(pp_name, %Entry{} = entry, state, leg) do
    case Map.fetch(state.depot_by_name, pp_name) do
      {:ok, id} ->
        {:ok, state, id}

      :error ->
        with {:ok, state, name, cash_id} <- depot_spec(pp_name, entry, state, leg) do
          create_depot(pp_name, name, cash_id, state)
        end
    end
  end

  defp depot_spec(pp_name, entry, state, leg) do
    case Map.fetch(state.pending_depots, pp_name) do
      {:ok, %{name: name, cash: {:existing, cash_id}}} ->
        {:ok, state, name, cash_id}

      {:ok, %{name: name, cash: {:pp, pp_cash}}} ->
        with {:ok, state, cash_id} <- materialize_cash(pp_cash, entry, state) do
          {:ok, state, name, cash_id}
        end

      :error ->
        unmatched_depot_cash(pp_name, entry, state, leg)
    end
  end

  defp unmatched_depot_cash(pp_name, %Entry{pp_account_name: nil}, _state, :row),
    do: {:error, {:depot_needs_cash, pp_name}}

  defp unmatched_depot_cash(pp_name, %Entry{pp_account_name: pp_cash} = entry, state, :row) do
    with {:ok, state, cash_id} <- materialize_cash(pp_cash, entry, state) do
      {:ok, state, pp_name, cash_id}
    end
  end

  defp unmatched_depot_cash(pp_name, _entry, state, :counter) do
    case List.first(Map.values(state.cash_by_name)) || first_cash_account_id(state) do
      nil -> {:error, {:counter_depot_needs_cash, pp_name}}
      cash_id -> {:ok, state, pp_name, cash_id}
    end
  end

  defp first_cash_account_id(state) do
    Repo.one(
      from(c in CashAccount,
        where: c.portfolio_id == ^state.portfolio_id,
        order_by: [asc: c.name, asc: c.id],
        limit: 1,
        select: c.id
      )
    )
  end

  defp create_depot(pp_name, name, cash_id, state) do
    attrs = %{portfolio_id: state.portfolio_id, cash_account_id: cash_id, name: name}

    case Portfolios.create_securities_account(Actor.import_session(), attrs) do
      {:ok, depot} ->
        state =
          state
          |> Map.update!(:depot_by_name, &Map.put(&1, pp_name, depot.id))
          |> Map.update!(:pending_depots, &Map.delete(&1, pp_name))
          |> bump_result(:created_securities_accounts)
          |> track_created_account(:created_securities_account_ids, depot.id)

        {:ok, state, depot.id}

      {:error, changeset} ->
        {:error, {:depot_create_failed, name, changeset}}
    end
  end

  # --- transaction attrs by kind ---

  defp build_transaction_attrs(%Entry{} = entry, state, ids, import_hash) do
    base = %{
      portfolio_id: state.portfolio_id,
      type: entry.kind,
      date: entry.date,
      currency_code: entry.currency_code || state.default_currency,
      notes: entry.note,
      gross_amount: entry.gross_amount,
      fees: entry.fees || Decimal.new(0),
      taxes: entry.taxes || Decimal.new(0),
      import_hash: import_hash
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
          |> Map.merge(settlement_legs(entry, state, ids.security_id))

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

  # ADR-0033 (issue #569): a Portfolio Performance export books a
  # cross-currency trade in the ACCOUNT currency, so the row alone carries no
  # security-currency leg. Persist the ADR-0015 settlement fields at write
  # time — `settlement_amount` is the account-currency trade amount (read
  # off the cash amount net of fees and taxes, the settlement guard's
  # relation inverted, #395: PP prints the per-share Kurs rounded, so
  # quantity × Kurs can miss the Betrag by more than the guard's cent;
  # quantity × price only without a cash amount), `security_amount` is that amount converted through
  # the STORED hub rate at the booking date, `settlement_fx_rate` their
  # ratio — so the cost fold can carry an honest cost pair without any
  # read-time rate lookup. No stored rate for the booking date means no
  # derivable native leg: the fields stay nil and the position's
  # decomposition reads honestly unavailable, never a guess (requirement 4).
  defp settlement_legs(%Entry{} = entry, state, security_id) do
    entry_currency = entry.currency_code || state.default_currency

    with true <- is_integer(security_id),
         %Security{currency_code: security_currency} <-
           Map.get(state.live_index.securities_by_id, security_id),
         true <- is_binary(security_currency) and security_currency != entry_currency,
         %Decimal{} = quantity <- entry.quantity,
         %Decimal{} = price <- entry.price,
         %Date{} = date <- entry.date,
         settlement_amount =
           SettlementGuard.trade_amount(entry.kind, entry.gross_amount, entry.fees, entry.taxes) ||
             Decimal.mult(quantity, price),
         {:ok, %Decimal{} = security_amount} <-
           Fx.convert(settlement_amount, entry_currency, security_currency, date),
         false <- Decimal.equal?(security_amount, 0) do
      %{
        security_amount: security_amount,
        settlement_amount: settlement_amount,
        settlement_fx_rate: settlement_amount |> Decimal.div(security_amount) |> Decimal.round(6)
      }
    else
      _no_derivable_native_leg -> %{}
    end
  end

  # `collapse?` is false only for a companion whose parent did not collapse
  # (E25 S5, F37): the in-run key would take two equal refunds of two
  # different rows for one.
  defp insert_transaction(entry, attrs, state, collapse? \\ true) do
    key = dedup_key(attrs)

    # Two-layer idempotency (#533): the stored content `import_hash` skips exact
    # re-inserts (and exact within-file duplicates), and since ADR-0050 §3 it
    # runs first, in `process_entry/2`, before anything resolves. On top of
    # that, a stable, formatting-tolerant key over the *resolved* DB identity
    # (portfolio, security/account ids, normalized decimals) skips a re-import
    # whose only difference is PP-export drift (decimal precision, or a
    # security rename when matched by ISIN). The key set is a PRE-import
    # snapshot and is deliberately NOT extended during the import: `time` is
    # not persisted on a transaction, so two legitimate same-day/same-amount
    # bookings (distinct only by time) must not collapse — within-file
    # de-duplication is the hash's job, not this key's.
    #
    # A row naming a pending account (ADR-0050 §4) carries a
    # `{:pending, kind, pp_name}` placeholder in its key, which matches no
    # existing and no earlier inserted booking: nothing was booked on an
    # account that does not exist yet.
    cond do
      MapSet.member?(state.existing_dedup_keys, key) ->
        {:ok, record_duplicate(state, entry, :economics)}

      collapse? and MapSet.member?(state.seen_run_keys, run_key(key, entry)) ->
        {:ok, state |> bump_result(:skipped_duplicates) |> record_collapsed(entry)}

      true ->
        with {:ok, state, attrs} <- materialize_accounts(entry, attrs, state) do
          insert_new_transaction(entry, attrs, run_key(dedup_key(attrs), entry), state)
        end
    end
  end

  # N:1 within-run dedup (ADR-0029 §2): two file rows carrying different
  # identities of ONE paper (old + new ISIN) resolve to the same security and
  # therefore to an identical resolved dedup key while their content hashes
  # differ — they collapse to one insert, surfaced in the result. `entry.time`
  # joins the run key so two legitimate same-day bookings distinct only by
  # their intraday time never collapse, and the file's four account names join
  # it (ADR-0050 §6) so two equal rows from different file accounts that
  # resolve to one account (twin fees, twin savings plans after a merge) are
  # both inserted.
  defp run_key(key, %Entry{} = entry) do
    {key, entry.time, entry.pp_portfolio_name, entry.pp_account_name,
     entry.pp_counter_portfolio_name, entry.pp_counter_account_name}
  end

  # #769: a skipped duplicate names its source row and the layer that skipped
  # it, next to the unimportable rows, so a silent skip is visible where the
  # operator reads the result. ADR-0050 §3 adds the layer `:retired` and counts
  # each layer in `already_imported`.
  defp record_duplicate(state, %Entry{} = entry, layer) do
    reason =
      case layer do
        :hash ->
          "already booked: an identical row was imported before (stored content hash)"

        :retired ->
          "already booked: a merge removed the row with this content (retired content hash)"

        :economics ->
          "already booked: an existing booking has the same date, security, quantity and amount"
      end

    state
    |> bump_result(:skipped_duplicates)
    |> Map.put(:outcome, {:duplicate, layer})
    |> Map.update!(:result, fn %Result{} = r ->
      %Result{
        r
        | duplicate_entries: [
            %{row: entry.source_row, reason: reason, layer: layer} | r.duplicate_entries
          ],
          already_imported: Map.update!(r.already_imported, layer, &(&1 + 1))
      }
    end)
  end

  defp record_collapsed(state, %Entry{} = entry) do
    state
    |> Map.put(:outcome, :collapsed)
    |> Map.update!(:result, fn %Result{} = r ->
      collapsed = %{
        row: entry.source_row,
        reason: "collapsed: resolves to the same booking as an earlier row in this file"
      }

      %Result{r | collapsed_duplicates: [collapsed | r.collapsed_duplicates]}
    end)
  end

  defp insert_new_transaction(entry, attrs, run_key, state) do
    changeset =
      %Transaction{}
      |> Transaction.import_changeset(attrs)
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
          |> Map.put(:outcome, :inserted)
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
  defp bump_result(state, field) when is_atom(field) do
    Map.update!(state, :result, fn %Result{} = r ->
      Map.put(r, field, Map.fetch!(r, field) + 1)
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
end
