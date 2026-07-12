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
  """
  def set_position_override(
        %Actor{} = actor,
        %SecuritiesAccount{id: sa_id},
        %Security{id: sec_id},
        bucket_ids
      )
      when is_list(bucket_ids) do
    with :ok <- validate_bucket_ids(bucket_ids) do
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
  The pure filter for a view: `%{include: :all | [bucket_id], exclude: [bucket_id]}`.
  Feed it to `Portfolixir.Engines.BucketResolution.holdings_matching_view/2`.
  """
  def view_filter(view_id) do
    view = Repo.get!(View, view_id)

    include =
      if view.include_all do
        :all
      else
        Repo.all(from(x in ViewIncludeBucket, where: x.view_id == ^view_id, select: x.bucket_id))
      end

    exclude =
      Repo.all(from(x in ViewExcludeBucket, where: x.view_id == ^view_id, select: x.bucket_id))

    %{include: include, exclude: exclude}
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

  @doc "Deletes a view definition (not journaled)."
  def delete_view(%Actor{} = _actor, %View{} = view), do: Repo.delete(view)

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
  """
  @spec load_scope(integer(), integer() | nil) :: :unscoped | map()
  def load_scope(_portfolio_id, nil), do: :unscoped

  def load_scope(portfolio_id, view_id) do
    %{
      view: view_filter(view_id),
      depot_defaults: depot_defaults_for_portfolio(portfolio_id),
      overrides: overrides_for_portfolio(portfolio_id),
      cash: cash_assignments_for_portfolio(portfolio_id)
    }
  end

  @doc """
  Loads a reusable **instance-wide** scope for `view_id` (ADR-0024): the same
  shape as `load_scope/2` but spanning every depot, position override, and cash
  account, so a cross-portfolio valuation can check membership without a
  portfolio filter. With `view_id == nil` it returns `:unscoped` (the
  "everything" scope — every account matches).
  """
  @spec load_global_scope(integer() | nil) :: :unscoped | map()
  def load_global_scope(nil), do: :unscoped

  def load_global_scope(view_id) do
    %{
      view: view_filter(view_id),
      depot_defaults: all_depot_defaults(),
      overrides: all_overrides(),
      cash: all_cash_assignments()
    }
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
  A portfolio whose name is already taken falls back deterministically to
  `"<name> (Portfolio)"`.

  Bucket creations and account assignments are journaled under `actor` per
  ADR-0017 (the buckets table is guard-armed); view definitions stay
  unjournaled per ADR-0018 §5.

  Returns `{:ok, %{buckets_created: n, views_created: n, accounts_tagged: n}}`;
  a re-run over a fully seeded instance returns all zeros.
  """
  def seed_portfolio_scope_buckets(%Actor{} = actor) do
    empty = %{buckets_created: 0, views_created: 0, accounts_tagged: 0}

    summary =
      from(p in Portfolio, order_by: [asc: p.id])
      |> Repo.all()
      |> Enum.reduce(empty, fn portfolio, acc -> seed_portfolio(actor, portfolio, acc) end)

    {:ok, summary}
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
    {bucket, acc} = ensure_seeded_bucket(actor, portfolio, acc)
    acc = ensure_seeded_view(portfolio, bucket, acc)
    tag_portfolio_accounts(actor, portfolio, bucket, acc)
  end

  defp ensure_seeded_bucket(%Actor{} = actor, %Portfolio{} = portfolio, acc) do
    case Repo.get_by(Bucket, source_portfolio_id: portfolio.id) do
      %Bucket{} = bucket ->
        {bucket, acc}

      nil ->
        bucket = create_seeded_bucket!(actor, portfolio)
        {bucket, %{acc | buckets_created: acc.buckets_created + 1}}
    end
  end

  # Mirrors `create_bucket/2` (journaled insert) but stamps the seed marker,
  # which is deliberately not castable from attrs.
  defp create_seeded_bucket!(%Actor{} = actor, %Portfolio{} = portfolio) do
    changeset =
      Bucket.changeset(%Bucket{source_portfolio_id: portfolio.id}, %{
        name: seed_name(portfolio.name, Bucket),
        dimension: @scope_dimension
      })

    {:ok, %{bucket: bucket}} =
      Multi.new()
      |> Multi.insert(:bucket, changeset)
      |> Journal.record(actor, resource_type: "bucket", operation: :create, source: :bucket)
      |> Repo.transaction()

    bucket
  end

  defp ensure_seeded_view(%Portfolio{} = portfolio, %Bucket{} = bucket, acc) do
    if Repo.get_by(View, source_portfolio_id: portfolio.id) do
      acc
    else
      create_seeded_view!(portfolio, bucket)
      %{acc | views_created: acc.views_created + 1}
    end
  end

  # The view and its single include link commit together; view definitions are
  # not journaled (ADR-0018 §5). The seeded view is a plain view — fully
  # editable, no system special-casing.
  defp create_seeded_view!(%Portfolio{} = portfolio, %Bucket{} = bucket) do
    changeset =
      View.changeset(%View{source_portfolio_id: portfolio.id}, %{
        name: seed_name(portfolio.name, View),
        include_all: false
      })

    {:ok, _} =
      Multi.new()
      |> Multi.insert(:view, changeset)
      |> Multi.insert(:include, fn %{view: view} ->
        %ViewIncludeBucket{view_id: view.id, bucket_id: bucket.id}
      end)
      |> Repo.transaction()

    :ok
  end

  defp seed_name(name, schema) do
    if Repo.exists?(from(r in schema, where: r.name == ^name)),
      do: name <> @seed_name_suffix,
      else: name
  end

  defp tag_portfolio_accounts(%Actor{} = actor, %Portfolio{id: pid}, %Bucket{} = bucket, acc) do
    depots = Repo.all(from(sa in SecuritiesAccount, where: sa.portfolio_id == ^pid))
    cash_accounts = Repo.all(from(ca in CashAccount, where: ca.portfolio_id == ^pid))

    tagged =
      Enum.count(depots, &tag_account(&1, bucket, depot_default_bucket_ids(&1.id), actor)) +
        Enum.count(cash_accounts, &tag_account(&1, bucket, cash_account_bucket_ids(&1.id), actor))

    %{acc | accounts_tagged: acc.accounts_tagged + tagged}
  end

  # Adds the seeded scope bucket to the account's existing set (idempotent:
  # already-tagged accounts are skipped). Returns whether a write happened.
  defp tag_account(account, %Bucket{id: bucket_id}, current_ids, %Actor{} = actor) do
    if bucket_id in current_ids do
      false
    else
      :ok = set_account_buckets(actor, account, current_ids ++ [bucket_id])
      true
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
