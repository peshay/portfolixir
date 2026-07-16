defmodule Portfolixir.Buckets do
  @moduledoc """
  Tag-based wealth scoping: buckets, assignments, and views (ADR-0018, FR-4).

  Buckets are overlapping tags on holdings. Assignment is depot-default +
  per-position override (with `:explicit_empty` distinct from `:inherit`); cash
  accounts carry their own bucket set. Views are global `{include | :all, exclude}`
  filters over buckets, with exclude winning.

  One bucket dimension is exclusive (ADR-0024): a depot/cash account carries at
  most one `"scope"`-dimension bucket (enforced here on assignment), while
  `"tag"` buckets stay free overlapping tags. The one-time portfolio migration
  (`seed_portfolio_scope_buckets/1`) seeds a scope bucket + view per portfolio.

  This context is the **only** writer of the bucket/view tables and is born
  actor-first (ADR-0017): bucket-definition and assignment writes are routed
  through `Journal.record/3` in the same `Ecto.Multi`, so each is attributable in
  the audit journal. **View-definition writes are deliberately not journaled**
  (ADR-0018 §5); they still take an `Actor` first argument for the uniform
  write-path signature (and so the P2 write-actor gate accepts them).

  Resolution helpers delegate the algebra to the pure engine
  `Portfolixir.Engines.BucketResolution` (architecture D2/P3) — this context only
  loads the data the engine needs.
  """
  import Ecto.Query

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Buckets.Bucket
  alias Portfolixir.Buckets.CashAccountBucket
  alias Portfolixir.Buckets.PositionBucketOverride
  alias Portfolixir.Buckets.SecuritiesAccountBucket
  alias Portfolixir.Buckets.View
  alias Portfolixir.Buckets.ViewExcludeBucket
  alias Portfolixir.Buckets.ViewIncludeBucket
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Engines.BucketResolution
  alias Portfolixir.Journal
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.Portfolio
  alias Portfolixir.Portfolios.SecuritiesAccount
  alias Portfolixir.Repo

  @scope_dimension "scope"
  @seed_name_suffix " (Portfolio)"
  @name_max_length 100

  # -- buckets (reads) -------------------------------------------------------

  def list_buckets, do: Repo.all(from(b in Bucket, order_by: [asc: b.name, asc: b.id]))

  def get_bucket(id), do: Repo.get(Bucket, id)

  def get_bucket!(id), do: Repo.get!(Bucket, id)

  # -- buckets (journaled writes) --------------------------------------------

  @doc "Creates a bucket on behalf of `actor`; the insert and its journal entry commit together."
  def create_bucket(%Actor{} = actor, attrs) when is_map(attrs) do
    Multi.new()
    |> Multi.insert(:bucket, Bucket.changeset(%Bucket{}, attrs))
    |> Journal.record(actor, resource_type: "bucket", operation: :create, source: :bucket)
    |> Repo.transaction()
    |> case do
      {:ok, %{bucket: bucket}} -> {:ok, bucket}
      {:error, :bucket, %Ecto.Changeset{} = changeset, _} -> {:error, changeset}
    end
  end

  @doc "Updates a bucket on behalf of `actor` (journaled with the pre-image)."
  def update_bucket(%Actor{} = actor, %Bucket{} = bucket, attrs) when is_map(attrs) do
    Multi.new()
    |> Multi.update(:bucket, Bucket.changeset(bucket, attrs))
    |> Journal.record(actor,
      resource_type: "bucket",
      operation: :update,
      source: :bucket,
      before: bucket
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{bucket: bucket}} -> {:ok, bucket}
      {:error, :bucket, %Ecto.Changeset{} = changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Deletes a bucket on behalf of `actor` (journaled with the pre-image). Cascade
  removes the bucket from every assignment and view set.
  """
  def delete_bucket(%Actor{} = actor, %Bucket{} = bucket) do
    Multi.new()
    |> Multi.delete(:bucket, bucket)
    |> Journal.record(actor,
      resource_type: "bucket",
      operation: :delete,
      source: :bucket,
      before: bucket
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{bucket: bucket}} -> {:ok, bucket}
      {:error, :bucket, %Ecto.Changeset{} = changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Finds the bucket named `name` (trimmed) or creates it as a free `"tag"`-
  dimension bucket on behalf of `actor` (journaled like any bucket create).
  Used by the import applier (ADR-0024 story 5): an entered tag that matches
  an existing bucket reuses it instead of erroring on the unique name.

  The lookup is dimension-safe (fix round): a name that belongs to an
  exclusive `"scope"`-dimension bucket is **not** reused as a tag — assigning
  a scope bucket as if it were a free tag would silently break the one-scope-
  bucket-per-account invariant. Returns `{:error, :name_taken_by_scope_bucket}`
  so callers can surface a clear message.
  """
  def ensure_tag_bucket(%Actor{} = actor, name) when is_binary(name) do
    trimmed = String.trim(name)

    case Repo.get_by(Bucket, name: trimmed) do
      %Bucket{dimension: @scope_dimension} -> {:error, :name_taken_by_scope_bucket}
      %Bucket{} = bucket -> {:ok, bucket}
      nil -> create_bucket(actor, %{name: trimmed, dimension: "tag"})
    end
  end

  @doc """
  Pre-validates a tag-bucket name **before** any write, so an import can
  reject a bad tag in the preview instead of aborting the whole apply at the
  end (fix round). Mirrors exactly what `ensure_tag_bucket/2` would hit:
  the 100-character name limit and the scope-bucket name collision.
  """
  @spec validate_tag_bucket_name(String.t()) ::
          :ok | {:error, :name_too_long | :name_taken_by_scope_bucket}
  def validate_tag_bucket_name(name) when is_binary(name) do
    trimmed = String.trim(name)

    cond do
      String.length(trimmed) > @name_max_length ->
        {:error, :name_too_long}

      match?(%Bucket{dimension: @scope_dimension}, Repo.get_by(Bucket, name: trimmed)) ->
        {:error, :name_taken_by_scope_bucket}

      true ->
        :ok
    end
  end

  # -- depot default assignment (journaled) ----------------------------------

  @doc """
  Replaces the depot's default bucket set with `bucket_ids` on behalf of `actor`.
  Recorded as one aggregate `depot_bucket_assignment` journal entry.
  """
  def set_depot_default_buckets(%Actor{} = actor, %SecuritiesAccount{id: sa_id}, bucket_ids)
      when is_list(bucket_ids) do
    bucket_ids = Enum.uniq(bucket_ids)

    with :ok <- validate_bucket_ids(bucket_ids),
         :ok <- validate_exclusive_dimension(bucket_ids) do
      entries = Enum.map(bucket_ids, &%{securities_account_id: sa_id, bucket_id: &1})

      Multi.new()
      |> Multi.delete_all(
        :clear,
        from(x in SecuritiesAccountBucket, where: x.securities_account_id == ^sa_id)
      )
      |> insert_all_step(:assign, SecuritiesAccountBucket, entries)
      |> Multi.run(:record, fn _repo, _changes ->
        {:ok, %{id: nil, securities_account_id: sa_id, bucket_ids: bucket_ids}}
      end)
      |> Journal.record(actor,
        resource_type: "depot_bucket_assignment",
        operation: :update,
        source: :record
      )
      |> Repo.transaction()
      |> normalize_assignment_result()
    end
  end

  @doc "Bucket ids in a depot's default set."
  def depot_default_bucket_ids(securities_account_id) do
    Repo.all(
      from(x in SecuritiesAccountBucket,
        where: x.securities_account_id == ^securities_account_id,
        order_by: [asc: x.bucket_id],
        select: x.bucket_id
      )
    )
  end

  # -- cash-account assignment (journaled) -----------------------------------

  @doc """
  Replaces a cash account's bucket set with `bucket_ids` on behalf of `actor`.
  Recorded as one aggregate `cash_account_bucket_assignment` journal entry.
  """
  def set_cash_account_buckets(%Actor{} = actor, %CashAccount{id: ca_id}, bucket_ids)
      when is_list(bucket_ids) do
    bucket_ids = Enum.uniq(bucket_ids)

    with :ok <- validate_bucket_ids(bucket_ids),
         :ok <- validate_exclusive_dimension(bucket_ids) do
      entries = Enum.map(bucket_ids, &%{cash_account_id: ca_id, bucket_id: &1})

      Multi.new()
      |> Multi.delete_all(
        :clear,
        from(x in CashAccountBucket, where: x.cash_account_id == ^ca_id)
      )
      |> insert_all_step(:assign, CashAccountBucket, entries)
      |> Multi.run(:record, fn _repo, _changes ->
        {:ok, %{id: nil, cash_account_id: ca_id, bucket_ids: bucket_ids}}
      end)
      |> Journal.record(actor,
        resource_type: "cash_account_bucket_assignment",
        operation: :update,
        source: :record
      )
      |> Repo.transaction()
      |> normalize_assignment_result()
    end
  end

  @doc "Bucket ids assigned to a cash account."
  def cash_account_bucket_ids(cash_account_id) do
    Repo.all(
      from(x in CashAccountBucket,
        where: x.cash_account_id == ^cash_account_id,
        order_by: [asc: x.bucket_id],
        select: x.bucket_id
      )
    )
  end

  # -- per-position override (journaled) -------------------------------------

  @doc """
  Sets the per-position override for `(securities_account, security)` to
  `bucket_ids` on behalf of `actor`. An empty list records the **explicit-empty**
  state (deliberately no buckets), distinct from inheriting the depot default.

  Like the account paths, the override enforces the ADR-0024 exclusive
  dimension (fix round): at most one `"scope"`-dimension bucket per position,
  rejected with `{:error, :exclusive_bucket_conflict}` before anything is
  written — otherwise an override could double-count a position into two
  scope-scoped totals.
  """
  def set_position_override(
        %Actor{} = actor,
        %SecuritiesAccount{id: sa_id},
        %Security{id: sec_id},
        bucket_ids
      )
      when is_list(bucket_ids) do
    with :ok <- validate_bucket_ids(bucket_ids),
         :ok <- validate_exclusive_dimension(bucket_ids) do
      entries =
        case Enum.uniq(bucket_ids) do
          [] ->
            [%{securities_account_id: sa_id, security_id: sec_id, bucket_id: nil}]

          ids ->
            Enum.map(ids, &%{securities_account_id: sa_id, security_id: sec_id, bucket_id: &1})
        end

      Multi.new()
      |> Multi.delete_all(:clear, position_override_query(sa_id, sec_id))
      |> Multi.insert_all(:assign, PositionBucketOverride, entries)
      |> Multi.run(:record, fn _repo, _changes ->
        {:ok,
         %{id: nil, securities_account_id: sa_id, security_id: sec_id, bucket_ids: bucket_ids}}
      end)
      |> Journal.record(actor,
        resource_type: "position_bucket_override",
        operation: :update,
        source: :record
      )
      |> Repo.transaction()
      |> normalize_assignment_result()
    end
  end

  @doc """
  Clears the per-position override, returning the position to **inherit** the
  depot default. Recorded as a `position_bucket_override` delete.
  """
  def clear_position_override(
        %Actor{} = actor,
        %SecuritiesAccount{id: sa_id},
        %Security{id: sec_id}
      ) do
    Multi.new()
    |> Multi.delete_all(:clear, position_override_query(sa_id, sec_id))
    |> Multi.run(:record, fn _repo, _changes ->
      {:ok, %{id: nil, securities_account_id: sa_id, security_id: sec_id}}
    end)
    |> Journal.record(actor,
      resource_type: "position_bucket_override",
      operation: :delete,
      source: :record
    )
    |> Repo.transaction()
    |> normalize_assignment_result()
  end

  @doc """
  The override state for a position: `:inherit`, `:explicit_empty`, or
  `{:explicit, bucket_ids}` (ADR-0018).
  """
  def position_override(securities_account_id, security_id) do
    from(o in position_override_query(securities_account_id, security_id),
      order_by: [asc: o.bucket_id],
      select: o.bucket_id
    )
    |> Repo.all()
    |> classify_override()
  end

  @doc "The resolved effective bucket ids for a position (override wins over depot default)."
  def effective_position_buckets(securities_account_id, security_id) do
    BucketResolution.effective_position_buckets(
      position_override(securities_account_id, security_id),
      depot_default_bucket_ids(securities_account_id)
    )
  end

  # -- views (reads) ---------------------------------------------------------

  def list_views, do: Repo.all(from(v in View, order_by: [asc: v.name, asc: v.id]))

  def get_view(id), do: Repo.get(View, id)

  def get_view!(id), do: Repo.get!(View, id)

  @doc """
  The pure filter for a view:
  `{:ok, %{include: :all | [bucket_id], exclude: [bucket_id]}}`.
  Feed it to `Portfolixir.Engines.BucketResolution.holdings_matching_view/2`.

  A vanished view returns `{:error, :view_not_found}` instead of raising
  (fix round): a stale view id — deleted in another tab between check and
  use — must degrade at the caller, never crash an async render or turn an
  API 404 into a 500.
  """
  def view_filter(view_id) do
    case Repo.get(View, view_id) do
      nil ->
        {:error, :view_not_found}

      view ->
        include =
          if view.include_all do
            :all
          else
            Repo.all(
              from(x in ViewIncludeBucket, where: x.view_id == ^view_id, select: x.bucket_id)
            )
          end

        exclude =
          Repo.all(
            from(x in ViewExcludeBucket, where: x.view_id == ^view_id, select: x.bucket_id)
          )

        {:ok, %{include: include, exclude: exclude}}
    end
  end

  # -- views (writes, actor-first but NOT journaled, ADR-0018 §5) -------------

  @doc "Creates a view. Actor-first for signature uniformity; view definition is not journaled."
  def create_view(%Actor{} = _actor, attrs) when is_map(attrs) do
    %View{}
    |> View.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a view definition (not journaled)."
  def update_view(%Actor{} = _actor, %View{} = view, attrs) when is_map(attrs) do
    view
    |> View.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a view definition. Journaled: deleting a view cascades the view's
  target plans (ADR-0027) — a financial-steering write, and the armed plan
  tables require the journal actor to be set when the cascade fires.
  """
  def delete_view(%Actor{} = actor, %View{} = view) do
    Multi.new()
    |> Multi.delete(:view, view)
    |> Journal.record(actor,
      resource_type: "view",
      operation: :delete,
      source: :view,
      before: view
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{view: deleted}} -> {:ok, deleted}
      {:error, :view, changeset, _changes} -> {:error, changeset}
    end
  end

  @doc """
  Replaces a view's include and exclude bucket sets (not journaled). Runs in one
  transaction so a view never observes a half-applied filter.
  """
  def set_view_buckets(%Actor{} = _actor, %View{id: view_id}, include_ids, exclude_ids)
      when is_list(include_ids) and is_list(exclude_ids) do
    with :ok <- validate_bucket_ids(include_ids ++ exclude_ids) do
      include_entries = Enum.map(include_ids, &%{view_id: view_id, bucket_id: &1})
      exclude_entries = Enum.map(exclude_ids, &%{view_id: view_id, bucket_id: &1})

      Multi.new()
      |> Multi.delete_all(:clear_in, from(x in ViewIncludeBucket, where: x.view_id == ^view_id))
      |> Multi.delete_all(:clear_ex, from(x in ViewExcludeBucket, where: x.view_id == ^view_id))
      |> insert_all_step(:include, ViewIncludeBucket, include_entries)
      |> insert_all_step(:exclude, ViewExcludeBucket, exclude_entries)
      |> Repo.transaction()
      |> case do
        {:ok, _} -> :ok
        {:error, _, reason, _} -> {:error, reason}
      end
    end
  end

  # -- view scope (read seam for analytics, #444) ----------------------------

  @doc """
  Loads a reusable scope for `portfolio_id` under `view_id`. With `view_id == nil`
  it returns `:unscoped` (everything is in scope, so analytics stay byte-identical
  to the unscoped path). Otherwise it bulk-loads — in a fixed number of queries —
  the view filter plus the portfolio's depot defaults, position overrides, and
  cash-account assignments, so subsequent membership checks need no further
  queries. The membership decision itself is the pure
  `Portfolixir.Engines.BucketResolution` (architecture D2/P3): this function is
  the shell that injects the data.

  A vanished `view_id` returns `{:error, :view_not_found}` (fix round) so the
  analytics caller can degrade instead of crashing on a stale id.
  """
  @spec load_scope(integer(), integer() | nil) ::
          :unscoped | map() | {:error, :view_not_found}
  def load_scope(_portfolio_id, nil), do: :unscoped

  def load_scope(portfolio_id, view_id) do
    case view_filter(view_id) do
      {:error, :view_not_found} = error ->
        error

      {:ok, view} ->
        %{
          view: view,
          depot_defaults: depot_defaults_for_portfolio(portfolio_id),
          overrides: overrides_for_portfolio(portfolio_id),
          cash: cash_assignments_for_portfolio(portfolio_id)
        }
    end
  end

  @doc """
  Loads a reusable **instance-wide** scope for `view_id` (ADR-0024): the same
  shape as `load_scope/2` but spanning every depot, position override, and cash
  account, so a cross-portfolio valuation can check membership without a
  portfolio filter. With `view_id == nil` it returns `:unscoped` (the
  "everything" scope — every account matches). A vanished `view_id` returns
  `{:error, :view_not_found}` (fix round).
  """
  @spec load_global_scope(integer() | nil) ::
          :unscoped | map() | {:error, :view_not_found}
  def load_global_scope(nil), do: :unscoped

  def load_global_scope(view_id) do
    case view_filter(view_id) do
      {:error, :view_not_found} = error ->
        error

      {:ok, view} ->
        %{
          view: view,
          depot_defaults: all_depot_defaults(),
          overrides: all_overrides(),
          cash: all_cash_assignments()
        }
    end
  end

  @doc """
  Reports whether the scope's **included** buckets overlap on any account: a
  depot or cash account carrying more than one included bucket (exclude wins,
  so excluded buckets never count). Returned as data for UI badges — computed
  from the already-loaded scope, no extra queries. The unscoped "everything"
  scope has no include set and reports no overlap. Overlap is account-level
  (depot defaults and cash assignments); a view whose buckets overlap still
  counts every account exactly once (deduplication is by construction).
  """
  @spec scope_overlap(:unscoped | map()) :: %{
          overlapping?: boolean(),
          securities_account_ids: [integer()],
          cash_account_ids: [integer()]
        }
  def scope_overlap(:unscoped) do
    %{overlapping?: false, securities_account_ids: [], cash_account_ids: []}
  end

  def scope_overlap(scope) when is_map(scope) do
    depot_ids = overlapping_owner_ids(scope.depot_defaults, scope.view)
    cash_ids = overlapping_owner_ids(scope.cash, scope.view)

    %{
      overlapping?: depot_ids != [] or cash_ids != [],
      securities_account_ids: depot_ids,
      cash_account_ids: cash_ids
    }
  end

  @doc """
  Whether the scope matches at least one account or overridden position
  (always true when unscoped or `include: :all`). Computed from the already-
  loaded scope, no extra queries. Drives the "matches no accounts" hint
  (fix round): a view whose include set is empty — or whose included buckets
  are no longer assigned anywhere — should say so instead of showing a silent
  zero total.
  """
  @spec scope_matches_any_account?(:unscoped | map()) :: boolean()
  def scope_matches_any_account?(:unscoped), do: true

  def scope_matches_any_account?(%{view: %{include: :all}}), do: true

  def scope_matches_any_account?(scope) when is_map(scope) do
    in_view? = &BucketResolution.in_view?(scope.view, &1)

    Enum.any?(scope.depot_defaults, fn {_owner, bucket_ids} -> in_view?.(bucket_ids) end) or
      Enum.any?(scope.cash, fn {_owner, bucket_ids} -> in_view?.(bucket_ids) end) or
      Enum.any?(scope.overrides, fn
        {_position, {:explicit, bucket_ids}} -> in_view?.(bucket_ids)
        {_position, _state} -> false
      end)
  end

  @doc "Whether the security position `{sa_id, sec_id}` is in `scope` (always true when unscoped)."
  @spec position_in_scope?(:unscoped | map(), integer(), integer()) :: boolean()
  def position_in_scope?(:unscoped, _sa_id, _sec_id), do: true

  def position_in_scope?(scope, sa_id, sec_id) when is_map(scope) do
    override = Map.get(scope.overrides, {sa_id, sec_id}, :inherit)

    effective =
      BucketResolution.effective_position_buckets(
        override,
        Map.get(scope.depot_defaults, sa_id, [])
      )

    BucketResolution.in_view?(scope.view, effective)
  end

  @doc "Whether the cash account is in `scope` (always true when unscoped)."
  @spec cash_in_scope?(:unscoped | map(), integer()) :: boolean()
  def cash_in_scope?(:unscoped, _cash_account_id), do: true

  def cash_in_scope?(scope, cash_account_id) when is_map(scope) do
    BucketResolution.in_view?(scope.view, Map.get(scope.cash, cash_account_id, []))
  end

  # -- portfolio -> scope-bucket seed (ADR-0024, epic story 2) ----------------

  @doc """
  Seeds the ADR-0024 portfolio migration: per existing portfolio one
  exclusive-dimension ("scope") bucket plus one editable view including exactly
  that bucket, and assigns each of the portfolio's depots and cash accounts to
  the bucket (pre-existing tag assignments are kept, not replaced).

  Seeded buckets and views carry the portfolio id in `source_portfolio_id`, so
  the seed is **idempotent** (an already-seeded portfolio is skipped entirely)
  and `rollback_portfolio_scope_seed/1` can remove exactly what was created.
  Naming is collision-safe (fix round): a taken portfolio name falls back to
  `"<name> (Portfolio)"`, then `"<name> (Portfolio 2)"` and so on until a name
  free among **both** buckets and views is found; over-long portfolio names
  are truncated to fit the 100-character bucket/view limit before suffixing.

  An account that already carries a **different** scope bucket is skipped
  (never crashed on) and counted in `skipped_existing_scope` — its existing
  scope assignment is the user's decision and wins.

  Bucket creations and account assignments are journaled under `actor` per
  ADR-0017 (the buckets table is guard-armed); view definitions stay
  unjournaled per ADR-0018 §5.

  Returns `{:ok, %{buckets_created: n, views_created: n, accounts_tagged: n,
  skipped_existing_scope: n}}`; a re-run over a fully seeded instance returns
  all zeros. A failed write stops the seed and reports **which portfolio**
  failed: `{:error, %{portfolio_id: id, portfolio_name: name, reason: reason}}`.
  """
  def seed_portfolio_scope_buckets(%Actor{} = actor) do
    empty = %{
      buckets_created: 0,
      views_created: 0,
      accounts_tagged: 0,
      skipped_existing_scope: 0
    }

    from(p in Portfolio, order_by: [asc: p.id])
    |> Repo.all()
    |> Enum.reduce_while({:ok, empty}, fn portfolio, {:ok, acc} ->
      case seed_portfolio(actor, portfolio, acc) do
        {:ok, acc} ->
          {:cont, {:ok, acc}}

        {:error, reason} ->
          {:halt,
           {:error, %{portfolio_id: portfolio.id, portfolio_name: portfolio.name, reason: reason}}}
      end
    end)
  end

  @doc """
  Reverts `seed_portfolio_scope_buckets/1`: deletes every bucket and view that
  carries a `source_portfolio_id` marker — and nothing else. Deleting a seeded
  bucket cascades its assignments and view links away; user-created buckets,
  views, and assignments are untouched. Bucket deletes are journaled under
  `actor`.
  """
  def rollback_portfolio_scope_seed(%Actor{} = actor) do
    Enum.each(seeded(Bucket), fn bucket -> {:ok, _} = delete_bucket(actor, bucket) end)
    Enum.each(seeded(View), fn view -> {:ok, _} = delete_view(actor, view) end)

    # A rolled-back migration also forgets that its notice was dismissed
    # (fix round): a later re-seed is a fresh migration and must be announced
    # again on the Wealth page.
    :ok = Portfolixir.Settings.reset_migration_notice()
    :ok
  end

  @doc """
  What the ADR-0024 portfolio migration created (for the one-time UI notice):
  the seeded buckets and views, each carrying its `source_portfolio_id`.
  `migrated?` is false once the seed was rolled back or never ran.
  """
  def migration_summary do
    buckets = seeded(Bucket)
    views = seeded(View)
    %{migrated?: buckets != [] or views != [], buckets: buckets, views: views}
  end

  defp seeded(schema) do
    Repo.all(from(r in schema, where: not is_nil(r.source_portfolio_id), order_by: [asc: r.id]))
  end

  defp seed_portfolio(%Actor{} = actor, %Portfolio{} = portfolio, acc) do
    with {:ok, bucket, acc} <- ensure_seeded_bucket(actor, portfolio, acc),
         {:ok, acc} <- ensure_seeded_view(portfolio, bucket, acc) do
      tag_portfolio_accounts(actor, portfolio, bucket, acc)
    end
  end

  defp ensure_seeded_bucket(%Actor{} = actor, %Portfolio{} = portfolio, acc) do
    case Repo.get_by(Bucket, source_portfolio_id: portfolio.id) do
      %Bucket{} = bucket ->
        {:ok, bucket, acc}

      nil ->
        with {:ok, bucket} <- create_seeded_bucket(actor, portfolio) do
          {:ok, bucket, %{acc | buckets_created: acc.buckets_created + 1}}
        end
    end
  end

  # Mirrors `create_bucket/2` (journaled insert) but stamps the seed marker,
  # which is deliberately not castable from attrs.
  defp create_seeded_bucket(%Actor{} = actor, %Portfolio{} = portfolio) do
    changeset =
      Bucket.changeset(%Bucket{source_portfolio_id: portfolio.id}, %{
        name: seed_bucket_name(portfolio),
        dimension: @scope_dimension
      })

    Multi.new()
    |> Multi.insert(:bucket, changeset)
    |> Journal.record(actor, resource_type: "bucket", operation: :create, source: :bucket)
    |> Repo.transaction()
    |> case do
      {:ok, %{bucket: bucket}} -> {:ok, bucket}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp ensure_seeded_view(%Portfolio{} = portfolio, %Bucket{} = bucket, acc) do
    if Repo.get_by(View, source_portfolio_id: portfolio.id) do
      {:ok, acc}
    else
      with :ok <- create_seeded_view(portfolio, bucket) do
        {:ok, %{acc | views_created: acc.views_created + 1}}
      end
    end
  end

  # The view and its single include link commit together; view definitions are
  # not journaled (ADR-0018 §5). The seeded view is a plain view — fully
  # editable, no system special-casing. The view prefers the bucket's exact
  # name (the pair reads as one unit); only a view-name collision — e.g. an
  # earlier partial seed plus a user view created in between — falls to the
  # numbered variants.
  defp create_seeded_view(%Portfolio{} = portfolio, %Bucket{} = bucket) do
    changeset =
      View.changeset(%View{source_portfolio_id: portfolio.id}, %{
        name: seed_view_name(bucket),
        include_all: false
      })

    Multi.new()
    |> Multi.insert(:view, changeset)
    |> Multi.insert(:include, fn %{view: view} ->
      %ViewIncludeBucket{view_id: view.id, bucket_id: bucket.id}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, _changes} -> :ok
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  # The seeded bucket name must be free among buckets AND views, so the view
  # created right after it can carry the same name.
  defp seed_bucket_name(%Portfolio{name: name}) do
    available_name(name, fn candidate ->
      not Repo.exists?(from(b in Bucket, where: b.name == ^candidate)) and
        not Repo.exists?(from(v in View, where: v.name == ^candidate))
    end)
  end

  defp seed_view_name(%Bucket{name: name}) do
    available_name(name, fn candidate ->
      not Repo.exists?(from(v in View, where: v.name == ^candidate))
    end)
  end

  # Collision-safe seed naming (fix round): the name itself, then
  # "<name> (Portfolio)", then "<name> (Portfolio 2)", "<name> (Portfolio 3)",
  # … — each with the base truncated so the whole candidate fits the
  # 100-character bucket/view name limit. The numbered tail is unbounded, so a
  # free name always exists and the seed can never abort on naming.
  defp available_name(base, free?) do
    base = String.trim(base)

    [fit_name(base, ""), fit_name(base, @seed_name_suffix)]
    |> Stream.concat(
      Stream.map(Stream.iterate(2, &(&1 + 1)), &fit_name(base, " (Portfolio #{&1})"))
    )
    |> Enum.find(free?)
  end

  defp fit_name(base, suffix) do
    String.slice(base, 0, max(@name_max_length - String.length(suffix), 1)) <> suffix
  end

  defp tag_portfolio_accounts(%Actor{} = actor, %Portfolio{id: pid}, %Bucket{} = bucket, acc) do
    depots = Repo.all(from(sa in SecuritiesAccount, where: sa.portfolio_id == ^pid))
    cash_accounts = Repo.all(from(ca in CashAccount, where: ca.portfolio_id == ^pid))

    depots
    |> Enum.map(&{&1, depot_default_bucket_ids(&1.id)})
    |> Enum.concat(Enum.map(cash_accounts, &{&1, cash_account_bucket_ids(&1.id)}))
    |> Enum.reduce_while({:ok, acc}, fn {account, current_ids}, {:ok, acc} ->
      case tag_account(account, bucket, current_ids, actor) do
        {:ok, :tagged} ->
          {:cont, {:ok, %{acc | accounts_tagged: acc.accounts_tagged + 1}}}

        {:ok, :skipped_existing_scope} ->
          {:cont, {:ok, %{acc | skipped_existing_scope: acc.skipped_existing_scope + 1}}}

        {:ok, :already_tagged} ->
          {:cont, {:ok, acc}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  # Adds the seeded scope bucket to the account's existing set. Idempotent:
  # already-tagged accounts are skipped. An account that already carries a
  # DIFFERENT scope bucket is skipped too (fix round) — the exclusive-dimension
  # rejection is expected there, not a crash: the user's existing scope
  # assignment wins over the seed.
  defp tag_account(account, %Bucket{id: bucket_id}, current_ids, %Actor{} = actor) do
    if bucket_id in current_ids do
      {:ok, :already_tagged}
    else
      case set_account_buckets(actor, account, current_ids ++ [bucket_id]) do
        :ok -> {:ok, :tagged}
        {:error, :exclusive_bucket_conflict} -> {:ok, :skipped_existing_scope}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp set_account_buckets(actor, %SecuritiesAccount{} = depot, ids),
    do: set_depot_default_buckets(actor, depot, ids)

  defp set_account_buckets(actor, %CashAccount{} = cash, ids),
    do: set_cash_account_buckets(actor, cash, ids)

  # -- helpers ---------------------------------------------------------------

  defp all_depot_defaults do
    from(x in SecuritiesAccountBucket, select: {x.securities_account_id, x.bucket_id})
    |> Repo.all()
    |> group_owner_ids()
  end

  defp all_cash_assignments do
    from(x in CashAccountBucket, select: {x.cash_account_id, x.bucket_id})
    |> Repo.all()
    |> group_owner_ids()
  end

  defp all_overrides do
    from(o in PositionBucketOverride,
      select: {o.securities_account_id, o.security_id, o.bucket_id}
    )
    |> Repo.all()
    |> classify_grouped_overrides()
  end

  # Owners (depot or cash-account ids) whose bucket set intersects the view's
  # include set in more than one bucket. Excluded buckets never count (exclude
  # wins); under `include: :all` every non-excluded bucket is included.
  defp overlapping_owner_ids(assignments, view) do
    assignments
    |> Enum.filter(fn {_owner, bucket_ids} -> included_bucket_count(view, bucket_ids) > 1 end)
    |> Enum.map(fn {owner, _bucket_ids} -> owner end)
    |> Enum.sort()
  end

  defp included_bucket_count(%{include: include, exclude: exclude}, bucket_ids) do
    bucket_ids
    |> Enum.uniq()
    |> Enum.reject(&(&1 in exclude))
    |> Enum.count(&(include == :all or &1 in include))
  end

  defp depot_defaults_for_portfolio(portfolio_id) do
    from(x in SecuritiesAccountBucket,
      join: sa in SecuritiesAccount,
      on: sa.id == x.securities_account_id,
      where: sa.portfolio_id == ^portfolio_id,
      select: {x.securities_account_id, x.bucket_id}
    )
    |> Repo.all()
    |> group_owner_ids()
  end

  defp cash_assignments_for_portfolio(portfolio_id) do
    from(x in CashAccountBucket,
      join: ca in CashAccount,
      on: ca.id == x.cash_account_id,
      where: ca.portfolio_id == ^portfolio_id,
      select: {x.cash_account_id, x.bucket_id}
    )
    |> Repo.all()
    |> group_owner_ids()
  end

  defp overrides_for_portfolio(portfolio_id) do
    from(o in PositionBucketOverride,
      join: sa in SecuritiesAccount,
      on: sa.id == o.securities_account_id,
      where: sa.portfolio_id == ^portfolio_id,
      select: {o.securities_account_id, o.security_id, o.bucket_id}
    )
    |> Repo.all()
    |> classify_grouped_overrides()
  end

  defp classify_grouped_overrides(rows) do
    rows
    |> Enum.group_by(fn {sa, sec, _b} -> {sa, sec} end, fn {_sa, _sec, b} -> b end)
    |> Map.new(fn {key, bucket_ids} -> {key, classify_override(bucket_ids)} end)
  end

  defp group_owner_ids(rows) do
    Enum.group_by(rows, fn {owner, _bucket} -> owner end, fn {_owner, bucket} -> bucket end)
  end

  # Resolves the raw override bucket-id rows for one position into its assignment
  # state. A single NULL row is the explicit-empty marker; the marker must never
  # coexist with real bucket rows — the context always writes one kind in a single
  # transaction, so a mixed set is corruption and fails loud (crash-by-design).
  defp classify_override([]), do: :inherit
  defp classify_override([nil]), do: :explicit_empty

  defp classify_override(bucket_ids) do
    if Enum.any?(bucket_ids, &is_nil/1) do
      raise "position_bucket_overrides mixes the explicit-empty marker with bucket rows"
    end

    {:explicit, bucket_ids}
  end

  # Rejects assignment/view-set requests that reference a non-existent bucket with
  # `{:error, :bucket_ids}` (a clean 422 at the web/MCP layer) instead of letting
  # the FK violation raise. `bucket_ids` are already integers by the time they
  # reach here (the web layer validates the shape).
  defp validate_bucket_ids([]), do: :ok

  defp validate_bucket_ids(bucket_ids) do
    existing =
      from(b in Bucket, where: b.id in ^bucket_ids, select: b.id)
      |> Repo.all()
      |> MapSet.new()

    if Enum.all?(bucket_ids, &MapSet.member?(existing, &1)),
      do: :ok,
      else: {:error, :bucket_ids}
  end

  # ADR-0024 invariant: an account carries AT MOST ONE bucket of the exclusive
  # "scope" dimension, so scope-scoped totals always add up. Free "tag" buckets
  # stay unrestricted. Rejected with `{:error, :exclusive_bucket_conflict}` (a
  # clean 422 at the web/MCP layer) before anything is written.
  defp validate_exclusive_dimension(bucket_ids) do
    scope_count =
      Repo.aggregate(
        from(b in Bucket, where: b.id in ^bucket_ids and b.dimension == @scope_dimension),
        :count
      )

    if scope_count > 1, do: {:error, :exclusive_bucket_conflict}, else: :ok
  end

  defp position_override_query(sa_id, sec_id) do
    from(o in PositionBucketOverride,
      where: o.securities_account_id == ^sa_id and o.security_id == ^sec_id
    )
  end

  # insert_all with an empty list is a no-op step (keeps the Multi shape uniform).
  defp insert_all_step(multi, _name, _schema, []), do: multi

  defp insert_all_step(multi, name, schema, entries),
    do: Multi.insert_all(multi, name, schema, entries)

  defp normalize_assignment_result({:ok, _changes}), do: :ok
  defp normalize_assignment_result({:error, _step, reason, _changes}), do: {:error, reason}
end
