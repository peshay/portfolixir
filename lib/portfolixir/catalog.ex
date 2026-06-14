defmodule Portfolixir.Catalog do
  @moduledoc "Security master data and online search integration."

  import Ecto.Query
  require Logger

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Catalog.LogoDiscovery
  alias Portfolixir.Catalog.LogoLookup
  alias Portfolixir.Catalog.LogoStore
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Catalog.QuoteSync
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Catalog.SecurityFields
  alias Portfolixir.Catalog.SecurityFields.Field
  alias Portfolixir.Catalog.SecuritySearch.SearchResult
  alias Portfolixir.Catalog.SecurityWithMetrics
  alias Portfolixir.Journal
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo

  @doc """
  Lists securities with optional :query, :filters and :sort. Unknown keys or
  invalid operators are silently dropped (with a Logger warning).

  Options:
    * `:query` – substring match on name/ticker/isin/wkn (case-insensitive)
    * `:filters` – list of `{field_key, op, value}` tuples
    * `:sort` – `{field_key, :asc | :desc}`, default `{:name, :asc}`
    * `:limit` – cap the number of rows returned (for pagination)
    * `:offset` – skip this many rows (for pagination)
  """
  def list_securities(opts \\ []) when is_list(opts) do
    sort = opts[:sort] || {:name, :asc}

    Security
    |> from(as: :security)
    |> apply_query(opts[:query])
    |> apply_filters(opts[:filters] || [])
    |> apply_holding_status(opts[:holding_status])
    |> apply_logo_status(opts[:logo_status])
    |> apply_sort(db_sort_or_default(sort))
    |> apply_limit(opts[:limit])
    |> apply_offset(opts[:offset])
    |> Repo.all()
  end

  @doc """
  Returns the set of security ids flagged `excluded_from_allocation_targets`.

  Used by `Portfolixir.Portfolios.Allocation` to keep flagged positions out of
  the steering basis (the 100%) while leaving valuation and performance
  untouched. A `MapSet` so the allocation can test membership cheaply.
  """
  def excluded_from_allocation_target_ids do
    Security
    |> where([s], s.excluded_from_allocation_targets == true)
    |> select([s], s.id)
    |> Repo.all()
    |> MapSet.new()
  end

  # `:logo_status` narrows the list by logo state, used by the "securities
  # without logo" overview. `:missing` excludes both stored logos and rows the
  # user explicitly locked to "no logo".
  defp apply_logo_status(query, status) when status in [:missing, "missing"] do
    from(s in query,
      where:
        fragment(
          "(? ->> ?) IS NULL AND coalesce(? ->> ?, 'false') <> 'true'",
          s.attributes,
          ^"logo_path",
          s.attributes,
          ^"logo_locked"
        )
    )
  end

  defp apply_logo_status(query, status) when status in [:present, "present"] do
    from(s in query, where: not is_nil(fragment("? ->> ?", s.attributes, ^"logo_path")))
  end

  defp apply_logo_status(query, _status), do: query

  defp apply_limit(query, nil), do: query
  defp apply_limit(query, value) when is_integer(value), do: limit(query, ^value)

  defp apply_offset(query, nil), do: query
  defp apply_offset(query, value) when is_integer(value), do: offset(query, ^value)

  @doc """
  Like `list_securities/1` but returns `%SecurityWithMetrics{}` wrappers,
  enriched with latest/prev/1M/1Y closes from quote history. Sort on metric
  columns is applied in Elixir post-enrichment (DB sort falls back to
  `{:name, :asc}` for that case).
  """
  def list_securities_with_metrics(opts \\ []) when is_list(opts) do
    sort = opts[:sort] || {:name, :asc}

    opts
    |> list_securities()
    |> Quotes.attach_metrics()
    |> sort_metric_rows(sort)
  end

  @doc """
  Backfills `asset_class` for securities that have none persisted yet, using
  the same heuristic as `Security.effective_asset_class/1`.

  Legacy rows imported before asset-class inference existed keep
  `asset_class = nil`. The securities list derives a class for display via
  `effective_asset_class/1`, but column-backed filters match the persisted
  value, so such a row could be shown as e.g. ETF yet disappear when filtering
  for ETF. Persisting the inferred class keeps display and filters consistent.

  Rows with an explicit class, or where inference yields nothing, are left
  unchanged. Returns the number of rows updated.

  FR-28 note: this is a **migration-only** data backfill invoked from immutable
  historical migrations (which run before the `securities` guard trigger is
  armed), so its arity cannot change and it carries no `actor`. The audit
  journal's no-bypass meta-test excludes it as a migration helper, not as a
  grandfathered context writer. Calling it at runtime against the armed table
  fails the guard loudly — by design.
  """
  def backfill_inferred_asset_classes do
    # Schema-snapshot safe: select only the columns asset-class inference reads
    # and update via update_all. This data backfill is invoked from historical
    # migrations, so it must never SELECT or write columns that did not yet
    # exist at that point in history (e.g. columns added by later migrations).
    Security
    |> where([s], is_nil(s.asset_class))
    |> select([s], %{id: s.id, name: s.name, isin: s.isin, ticker_symbol: s.ticker_symbol})
    |> Repo.all()
    |> Enum.reduce(0, fn attrs, updated ->
      case Security.effective_asset_class(struct(Security, attrs)) do
        class when is_binary(class) ->
          Security
          |> where([s], s.id == ^attrs.id)
          |> Repo.update_all(set: [asset_class: class])

          updated + 1

        _ ->
          updated
      end
    end)
  end

  defp db_sort_or_default({key, _dir} = sort) do
    case SecurityFields.get(key) do
      %Field{source: :metric} -> {:name, :asc}
      _ -> sort
    end
  end

  defp db_sort_or_default(other), do: other

  defp sort_metric_rows(rows, {key, dir}) do
    case SecurityFields.get(key) do
      %Field{source: :metric} = field ->
        Enum.sort_by(rows, &metric_sort_key(field, &1), metric_comparator(dir))

      _ ->
        rows
    end
  end

  defp sort_metric_rows(rows, _), do: rows

  defp metric_sort_key(field, %SecurityWithMetrics{} = wrapped) do
    SecurityFields.value(field, wrapped)
  end

  defp metric_comparator(:asc) do
    fn a, b -> compare_nilable(a, b, :asc) end
  end

  defp metric_comparator(:desc) do
    fn a, b -> compare_nilable(a, b, :desc) end
  end

  defp compare_nilable(nil, nil, _), do: true
  defp compare_nilable(nil, _, :asc), do: false
  defp compare_nilable(_, nil, :asc), do: true
  defp compare_nilable(nil, _, :desc), do: false
  defp compare_nilable(_, nil, :desc), do: true

  defp compare_nilable(%Decimal{} = a, %Decimal{} = b, :asc), do: Decimal.compare(a, b) != :gt
  defp compare_nilable(%Decimal{} = a, %Decimal{} = b, :desc), do: Decimal.compare(a, b) != :lt
  defp compare_nilable(%Date{} = a, %Date{} = b, :asc), do: Date.compare(a, b) != :gt
  defp compare_nilable(%Date{} = a, %Date{} = b, :desc), do: Date.compare(a, b) != :lt
  defp compare_nilable(a, b, :asc), do: a <= b
  defp compare_nilable(a, b, :desc), do: a >= b

  def count_securities, do: Repo.aggregate(Security, :count, :id)

  def get_security!(id), do: Repo.get!(Security, id)

  def get_security(id) when is_integer(id), do: Repo.get(Security, id)

  def get_security(id) when is_binary(id) do
    case Integer.parse(id) do
      {security_id, ""} -> get_security(security_id)
      _ -> nil
    end
  end

  def get_security(_id), do: nil

  @doc """
  Creates a security on behalf of `actor` (FR-28). The insert and its audit
  journal entry commit in one transaction (ADR-0015, P9); the security table is
  guard-armed, so this is the only sanctioned create path.
  """
  def create_security(%Actor{} = actor, attrs) when is_map(attrs) do
    multi =
      Multi.new()
      |> Multi.insert(:security, Security.changeset(%Security{}, attrs))
      |> Journal.record(actor, resource_type: "security", operation: :create, source: :security)

    case Repo.transaction(multi) do
      {:ok, %{security: security}} ->
        maybe_enrich_security(security)
        {:ok, security}

      {:error, :security, %Ecto.Changeset{} = changeset, _changes} ->
        {:error, changeset}
    end
  end

  @doc false
  # One supervised task syncs the batch sequentially. Spawning a task per
  # security (a large import creates hundreds) floods the provider and
  # exhausts the DB connection pool — page loads right after an import then
  # time out with 500s. Logos already queue through the LogoDiscovery server.
  def enrich_security_ids_async(ids) when is_list(ids) do
    if quote_enrichment_enabled?() and ids != [] do
      Task.Supervisor.start_child(Portfolixir.LogoSupervisor, fn ->
        Enum.each(ids, fn id ->
          case get_security(id) do
            %Security{} = security -> QuoteSync.sync_security(security)
            nil -> :ok
          end
        end)
      end)
    end

    if logo_enrichment_enabled?(), do: LogoDiscovery.enqueue_security_ids(ids)
    :ok
  end

  @doc false
  def enqueue_missing_security_logos_async do
    LogoDiscovery.enqueue_missing_security_logos()
  end

  @doc false
  def enrich_security_async(%Security{id: id}), do: enrich_security_async(id)

  def enrich_security_async(id) when is_integer(id) do
    if quote_enrichment_enabled?() do
      Task.Supervisor.start_child(Portfolixir.LogoSupervisor, fn ->
        case get_security(id) do
          %Security{} = security -> QuoteSync.sync_security(security)
          nil -> :ok
        end
      end)
    end

    if logo_enrichment_enabled?(), do: LogoDiscovery.enqueue_security_ids([id])
    :ok
  end

  defp maybe_enrich_security(%Security{} = security) do
    if Repo.in_transaction?() do
      :ok
    else
      enrich_security_async(security)
    end
  end

  defp quote_enrichment_enabled? do
    Application.get_env(:portfolixir, QuoteSync, [])
    |> Keyword.get(:enabled?, false)
  end

  defp logo_enrichment_enabled? do
    Application.get_env(:portfolixir, :enable_logo_discovery, false)
  end

  @doc """
  Updates a security on behalf of `actor` (FR-28). The update and its audit
  journal entry (with the pre-image as `before`) commit in one transaction.
  """
  def update_security(%Actor{} = actor, %Security{} = security, attrs) when is_map(attrs) do
    multi =
      Multi.new()
      |> Multi.update(:security, Security.changeset(security, attrs))
      |> Journal.record(actor,
        resource_type: "security",
        operation: :update,
        source: :security,
        before: security
      )

    case Repo.transaction(multi) do
      {:ok, %{security: updated}} -> {:ok, updated}
      {:error, :security, %Ecto.Changeset{} = changeset, _changes} -> {:error, changeset}
    end
  end

  @doc """
  Deletes a security on behalf of `actor` (FR-28). The deletion is journaled
  with the full `before` snapshot, so a removed security stays traceable in the
  audit journal.
  """
  def delete_security(%Actor{} = actor, %Security{} = security) do
    multi =
      Multi.new()
      |> Multi.delete(:security, Security.delete_changeset(security))
      |> Journal.record(actor,
        resource_type: "security",
        operation: :delete,
        source: :security,
        before: security
      )

    case Repo.transaction(multi) do
      {:ok, %{security: deleted}} -> {:ok, deleted}
      {:error, :security, %Ecto.Changeset{} = changeset, _changes} -> {:error, changeset}
    end
  end

  @doc """
  Reports the logo state of a security for the API/UI.

  Returns a map with the stored `path`, the resolving `source` (e.g.
  `"coingecko"`, `"wikipedia"`, `"manual"`), whether a logo is present and
  whether the choice is `locked` (manual override or explicit removal).
  """
  def logo_status(%Security{attributes: attributes}) do
    attrs = attributes || %{}
    path = attrs["logo_path"]

    %{
      path: path,
      source: attrs["logo_source"],
      has_logo: is_binary(path),
      locked: attrs["logo_locked"] == true
    }
  end

  @doc """
  Sets a manual logo override from an image URL. Locks the security so
  background discovery never replaces the manual choice.
  """
  def set_logo_override(%Security{} = security, url, opts \\ []) when is_binary(url) do
    LogoStore.store_manual_override(security, url, opts)
  end

  @doc "Removes a security's logo and records an explicit \"no logo\" decision."
  def remove_logo(%Security{} = security, opts \\ []) do
    LogoStore.remove_logo(security, opts)
  end

  @doc """
  Re-runs automatic logo discovery for a single security synchronously,
  bypassing the background queue. Used by the "search again" action. A locked
  security is left untouched.
  """
  def rediscover_logo(%Security{} = security, opts \\ []) do
    if logo_status(security).locked do
      :skip
    else
      LogoLookup.run(security, opts)
    end
  end

  @doc """
  Sets the persisted `asset_class` on many securities in one statement on behalf
  of `actor` (FR-28). `code` must be a valid asset-class code (callers pass a
  built-in category key), or `nil` to clear it back to "automatic" (inferred on
  read). Returns the count of rows updated.

  This bulk reclassification is journaled as a single aggregate `update` entry
  on `resource_type: "security"` (resource_id `nil`) carrying the affected ids —
  the guard-armed `securities` table still requires the actor on every row, so
  the whole `update_all` runs inside one actor-set transaction (ADR-0015).
  """
  def set_asset_class(%Actor{} = _actor, [], _code), do: 0

  def set_asset_class(%Actor{} = actor, security_ids, code) when is_list(security_ids) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    multi =
      Multi.new()
      |> Multi.update_all(
        :bulk,
        from(s in Security, where: s.id in ^security_ids),
        set: [asset_class: code, updated_at: now]
      )
      |> Multi.run(:bulk_record, fn _repo, %{bulk: {count, _}} ->
        {:ok, %{id: nil, asset_class: code, security_ids: security_ids, updated_count: count}}
      end)
      |> Journal.record(actor,
        resource_type: "security",
        operation: :update,
        source: :bulk_record
      )

    {:ok, %{bulk: {count, _}}} = Repo.transaction(multi)
    count
  end

  @doc """
  Finds an existing security that matches the search result (provider+online_id,
  ISIN, or ticker+currency) without inserting. Returns `{:exists, security}`
  when found, `:not_found` otherwise.
  """
  def find_matching_security(%SearchResult{} = result, market \\ nil) do
    attrs = SearchResult.to_security_attrs(result, market)

    with nil <- lookup_by_provider(attrs),
         nil <- lookup_by_isin(attrs),
         nil <- lookup_by_ticker(attrs) do
      :not_found
    else
      %Security{} = existing -> {:exists, existing}
    end
  end

  defp lookup_by_provider(%{provider: provider, online_id: online_id})
       when is_binary(provider) and is_binary(online_id) do
    Repo.get_by(Security, provider: provider, online_id: online_id)
  end

  defp lookup_by_provider(_), do: nil

  defp lookup_by_isin(%{isin: isin}) when is_binary(isin) do
    Repo.get_by(Security, isin: isin)
  end

  defp lookup_by_isin(_), do: nil

  defp lookup_by_ticker(%{ticker_symbol: ticker, currency_code: currency})
       when is_binary(ticker) and is_binary(currency) do
    Repo.get_by(Security, ticker_symbol: ticker, currency_code: currency)
  end

  defp lookup_by_ticker(_), do: nil

  @doc """
  Creates a security from a search result. When an existing record is found,
  returns `{:conflict, existing_security}` so the UI can ask the user whether
  to open the existing record or merge the online fields.
  """
  def create_from_search_result(
        %Actor{} = actor,
        %SearchResult{} = result,
        market \\ nil,
        overrides \\ %{}
      ) do
    attrs = result |> SearchResult.to_security_attrs(market) |> Map.merge(overrides)

    with nil <- lookup_by_provider(attrs),
         nil <- lookup_by_isin(attrs),
         nil <- lookup_by_ticker(attrs) do
      create_security(actor, attrs)
    else
      %Security{} = existing -> {:conflict, existing}
    end
  end

  @doc """
  Merges online fields from a search result into an existing security. Keeps
  user-edited fields (`note`) and merges `attributes` rather than replacing.
  """
  def merge_search_result(actor, existing, result, market \\ nil, overrides \\ %{})

  def merge_search_result(
        %Actor{} = actor,
        %Security{} = existing,
        %SearchResult{} = result,
        market,
        overrides
      ) do
    incoming = SearchResult.to_security_attrs(result, market)

    merged_attributes =
      Map.merge(existing.attributes || %{}, incoming[:attributes] || %{})

    attrs =
      incoming
      |> Map.drop([:note, :attributes])
      |> Map.put(:attributes, merged_attributes)
      |> Map.merge(normalize_overrides(overrides))

    update_security(actor, existing, attrs)
  end

  defp normalize_overrides(overrides) when is_map(overrides) do
    overrides
    |> Enum.flat_map(fn
      {k, v} when is_atom(k) ->
        [{k, v}]

      {k, v} when is_binary(k) ->
        case Map.fetch(string_to_security_key(), k) do
          {:ok, atom} -> [{atom, v}]
          :error -> []
        end
    end)
    |> Map.new()
  end

  defp normalize_overrides(_), do: %{}

  defp string_to_security_key do
    ~w(name ticker_symbol isin wkn currency_code exchange_code asset_class
       note feed feed_url latest_feed latest_feed_url is_retired
       online_id provider)a
    |> Enum.map(fn key -> {Atom.to_string(key), key} end)
    |> Map.new()
  end

  # -- query helpers ---------------------------------------------------------

  defp apply_query(query, nil), do: query
  defp apply_query(query, ""), do: query

  defp apply_query(query, term) when is_binary(term) do
    pattern = "%" <> escape_like(String.trim(term)) <> "%"

    from(security in query,
      where:
        ilike(security.name, ^pattern) or
          ilike(security.ticker_symbol, ^pattern) or
          ilike(security.isin, ^pattern) or
          ilike(security.wkn, ^pattern)
    )
  end

  defp escape_like(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  defp apply_filters(query, filters) do
    Enum.reduce(filters, query, fn filter, acc ->
      case normalize_filter(filter) do
        {:ok, key, op, value} ->
          field = SecurityFields.get!(key)

          if SecurityFields.valid_filter?(key, op, value) do
            add_filter(acc, field, op, value)
          else
            Logger.warning("dropping invalid security filter: #{inspect(filter)}")
            acc
          end

        :error ->
          Logger.warning("dropping malformed security filter: #{inspect(filter)}")
          acc
      end
    end)
  end

  defp apply_holding_status(query, status) do
    case normalize_holding_status(status) do
      :all ->
        query

      :held ->
        from(s in query,
          join: h in subquery(holding_totals_query()),
          on: h.security_id == s.id,
          where: fragment("? <> 0", h.quantity)
        )

      :not_held ->
        from(s in query,
          left_join: h in subquery(holding_totals_query()),
          on: h.security_id == s.id,
          where: is_nil(h.security_id) or fragment("? = 0", h.quantity)
        )
    end
  end

  defp normalize_holding_status(nil), do: :all
  defp normalize_holding_status(""), do: :all
  defp normalize_holding_status(:all), do: :all
  defp normalize_holding_status("all"), do: :all
  defp normalize_holding_status(:held), do: :held
  defp normalize_holding_status("held"), do: :held
  defp normalize_holding_status(:not_held), do: :not_held
  defp normalize_holding_status("not_held"), do: :not_held

  defp normalize_holding_status(other) do
    Logger.warning("dropping invalid holding status filter: #{inspect(other)}")
    :all
  end

  defp holding_totals_query do
    from(t in Transaction,
      where: t.type in ["buy", "sell"],
      group_by: t.security_id,
      select: %{
        security_id: t.security_id,
        quantity:
          fragment(
            "sum(CASE WHEN ? = 'buy' THEN ? WHEN ? = 'sell' THEN -? ELSE 0 END)",
            t.type,
            t.quantity,
            t.type,
            t.quantity
          )
      }
    )
  end

  defp normalize_filter({key, op, value}) when is_atom(key) and is_atom(op) do
    {:ok, key, op, value}
  end

  defp normalize_filter(%{key: key, op: op, value: value}) when is_atom(key) and is_atom(op) do
    {:ok, key, op, value}
  end

  defp normalize_filter(_), do: :error

  defp add_filter(query, %Field{source: :column, key: key}, :eq, value),
    do: from(s in query, where: field(s, ^key) == ^value)

  defp add_filter(query, %Field{source: :column, key: key}, :neq, value),
    do: from(s in query, where: field(s, ^key) != ^value)

  defp add_filter(query, %Field{source: :column, key: key}, :contains, value),
    do: from(s in query, where: ilike(field(s, ^key), ^"%#{value}%"))

  defp add_filter(query, %Field{source: :column, key: key}, :starts_with, value),
    do: from(s in query, where: ilike(field(s, ^key), ^"#{value}%"))

  defp add_filter(query, %Field{source: :column, key: key}, :gt, value),
    do: from(s in query, where: field(s, ^key) > ^value)

  defp add_filter(query, %Field{source: :column, key: key}, :lt, value),
    do: from(s in query, where: field(s, ^key) < ^value)

  defp add_filter(query, %Field{source: :column, key: key}, :is_true, _),
    do: from(s in query, where: field(s, ^key) == true)

  defp add_filter(query, %Field{source: :column, key: key}, :is_false, _),
    do: from(s in query, where: field(s, ^key) == false)

  defp add_filter(query, %Field{source: :column, key: key}, :is_nil, _),
    do: from(s in query, where: is_nil(field(s, ^key)))

  defp add_filter(query, %Field{source: {:attributes, jsonb_key}}, :eq, value),
    do:
      from(s in query,
        where: fragment("? ->> ? = ?", s.attributes, ^jsonb_key, ^to_string(value))
      )

  defp add_filter(query, %Field{source: {:attributes, jsonb_key}}, :neq, value),
    do:
      from(s in query,
        where: fragment("? ->> ? <> ?", s.attributes, ^jsonb_key, ^to_string(value))
      )

  defp add_filter(query, %Field{source: {:attributes, jsonb_key}}, :contains, value),
    do:
      from(s in query,
        where: fragment("(? ->> ?) ILIKE ?", s.attributes, ^jsonb_key, ^"%#{value}%")
      )

  defp add_filter(query, %Field{source: {:attributes, jsonb_key}}, :starts_with, value),
    do:
      from(s in query,
        where: fragment("(? ->> ?) ILIKE ?", s.attributes, ^jsonb_key, ^"#{value}%")
      )

  defp apply_sort(query, {key, dir}) when is_atom(key) and dir in [:asc, :desc] do
    case SecurityFields.get(key) do
      %Field{sortable?: true} = field ->
        order_by_field(query, field, dir)

      _ ->
        from(s in query, order_by: [asc: s.name])
    end
  end

  defp apply_sort(query, _), do: from(s in query, order_by: [asc: s.name])

  defp order_by_field(query, %Field{source: :column, key: key}, :asc) do
    from(s in query, order_by: [asc: field(s, ^key)])
  end

  defp order_by_field(query, %Field{source: :column, key: key}, :desc) do
    from(s in query, order_by: [desc: field(s, ^key)])
  end

  defp order_by_field(query, %Field{source: {:attributes, jsonb_key}, type: type}, :asc)
       when type in [:integer, :decimal] do
    from(s in query, order_by: [asc: fragment("(? ->> ?)::numeric", s.attributes, ^jsonb_key)])
  end

  defp order_by_field(query, %Field{source: {:attributes, jsonb_key}, type: type}, :desc)
       when type in [:integer, :decimal] do
    from(s in query, order_by: [desc: fragment("(? ->> ?)::numeric", s.attributes, ^jsonb_key)])
  end

  defp order_by_field(query, %Field{source: {:attributes, jsonb_key}}, :asc) do
    from(s in query, order_by: [asc: fragment("? ->> ?", s.attributes, ^jsonb_key)])
  end

  defp order_by_field(query, %Field{source: {:attributes, jsonb_key}}, :desc) do
    from(s in query, order_by: [desc: fragment("? ->> ?", s.attributes, ^jsonb_key)])
  end
end
