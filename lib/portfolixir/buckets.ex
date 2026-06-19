defmodule Portfolixir.Buckets do
  @moduledoc """
  Tag-based wealth scoping: buckets, assignments, and views (ADR-0018, FR-4).

  Buckets are overlapping tags on holdings. Assignment is depot-default +
  per-position override (with `:explicit_empty` distinct from `:inherit`); cash
  accounts carry their own bucket set. Views are global `{include | :all, exclude}`
  filters over buckets, with exclude winning.

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
  alias Portfolixir.Portfolios.SecuritiesAccount
  alias Portfolixir.Repo

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

    with :ok <- validate_bucket_ids(bucket_ids) do
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

    with :ok <- validate_bucket_ids(bucket_ids) do
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

  # -- helpers ---------------------------------------------------------------

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
