defmodule Portfolixir.Journal do
  @moduledoc """
  Append-only audit journal for financial writes (ADR-0017, FR-28).

  This is the **only** module that writes `audit_journal`. A context routes a
  financial write through `record/3`, which appends the journal insert to the
  caller's `Ecto.Multi` so the business write and its journal entry commit in one
  database transaction — both or neither.

  `record/3` also sets the transaction-local `portfolixir.journal_actor` session
  variable that the per-table guard trigger requires (and resets it in a final
  step, so a stale actor cannot leak across the Ecto SQL sandbox's outer
  transaction). Until a context is armed, no guard trigger exists; `record/3` is
  still the correct seam to journal that context's writes.

  The read surface (`list_entries/1`) default-filters to real (non-scenario)
  writes; pass `include_scenarios: true` to include persisted what-if entries.
  """
  import Ecto.Query

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Derived.Invalidation
  alias Portfolixir.Journal.Entry
  alias Portfolixir.Journal.Serializer
  alias Portfolixir.Repo

  @actor_setting "portfolixir.journal_actor"

  @doc """
  Appends an audit-journal step to `multi`, recording one entry for the write
  produced by the `:source` step.

  Options:

    * `:resource_type` (required) — stable string code, e.g. `"transaction"`.
    * `:operation` (required) — one of `Entry.operations/0`.
    * `:source` (required) — the name of the `Ecto.Multi` step whose result is
      the written record; its serialized form becomes `after` and supplies
      `resource_id`.
    * `:before` — the prior record/changeset-data struct (for `update`/`delete`);
      serialized into `before`. Defaults to `nil` (creates).
    * `:before_step` — instead of `:before`, the name of an earlier Multi step
      whose result is the prior image, for an aggregate the write reads
      inside its own transaction (a view's definition, E25 S6, F45).
    * `:resource_id` — the id the entry is filed under when the `:source`
      record is an aggregate without one of its own (a security's quotes are
      filed under the security's id, E25 S6); defaults to the record's `id`.
    * `:scenario_id` — marks a persisted what-if write; defaults to `nil` (real).
    * `:journal_step` — the Multi step name for the insert; defaults to
      `:journal_entry`.

  Returns the augmented `Ecto.Multi`. The actor is set first (so the guard
  trigger sees it during the business write) and reset last.

  An `update` whose record equals its `:before` snapshot changed nothing and
  records no entry: the step answers `:unchanged` (E25 S6, G02).

  **The before-image is read under a lock** (E25 S6, F49). When `:before` is
  a stored row (a schema struct with an id) of an `update`, a `delete` or an
  `upsert`, a step `{:journal_lock, journal_step}` runs first — right after
  the actor is set, ahead of the business write — and re-reads that row under
  the lock the write itself takes (`FOR NO KEY UPDATE` for an update or an
  upsert, `FOR UPDATE` for a delete). The re-read row, not the struct the
  caller read earlier outside the transaction, is the entry's before-image,
  and a business step builds its changeset on it through `locked_row/2`; an
  `update`'s after-image is the row re-read after the write, as stored. Two
  writers acting on one read therefore chain in the journal (the second's
  before-image is the first's after-image) instead of both claiming the same
  prior state. A row that is gone by then fails the lock step with
  `:not_found`, before anything is written: the transaction answers
  `{:error, {:journal_lock, step}, :not_found, changes}`. An upsert's prior
  row that is gone leaves no before-image instead: the upsert inserts it
  afresh.
  """
  @spec record(Multi.t(), Actor.t(), keyword()) :: Multi.t()
  def record(%Multi{} = multi, %Actor{} = actor, opts) when is_list(opts) do
    resource_type = Keyword.fetch!(opts, :resource_type)
    operation = Keyword.fetch!(opts, :operation)
    source = Keyword.fetch!(opts, :source)
    before = Keyword.get(opts, :before)
    scenario_id = Keyword.get(opts, :scenario_id)
    journal_step = Keyword.get(opts, :journal_step, :journal_entry)
    filed_under = Keyword.get(opts, :resource_id)
    lock_step = lock_step(operation, before, journal_step)
    image_step = Keyword.get(opts, :before_step) || lock_step

    multi
    |> Multi.prepend(lock_before_multi(lock_step, operation, before))
    |> Multi.prepend(set_actor_multi(actor))
    |> Multi.run(journal_step, fn repo, changes ->
      before = locked_before(changes, image_step, before)
      record = stored_after(repo, operation, lock_step, Map.fetch!(changes, source))

      if unchanged?(operation, before, record) do
        {:ok, :unchanged}
      else
        id = if filed_under, do: to_string(filed_under), else: resource_id(record)
        insert_entry(repo, actor, {operation, resource_type, id}, record, before, scenario_id)
      end
    end)
    |> Multi.run(:derived_invalidation, fn repo, changes ->
      # ADR-0032 §3.4 / ADR-0039 I5: the data version of every basis this
      # write can affect is bumped here, inside the writing transaction, so no
      # read after a committed write can be served a pre-write derived value.
      # A write kind the resolver does not know widens to "every portfolio"
      # rather than to none.
      # #851: the before-image rides along, so an edit that MOVES a record
      # (a transaction to another security or portfolio) also bumps what the
      # record used to affect — the radius is the union of both images.
      Invalidation.after_write(
        repo,
        resource_type,
        Map.fetch!(changes, source),
        locked_before(changes, image_step, before)
      )

      {:ok, :invalidated}
    end)
    |> Multi.run(:journal_reset_actor, fn repo, _changes -> reset_actor(repo) end)
  end

  @doc """
  The row the lock step of `journal_step` re-read under its lock (F49), for a
  business step to build its changeset on: `Multi.update(:x,
  &Schema.changeset(Journal.locked_row(&1), attrs))`. The changeset then
  starts from the stored row, as the before-image does, not from the
  caller's earlier read.
  """
  @spec locked_row(map(), atom()) :: struct()
  def locked_row(changes, journal_step \\ :journal_entry),
    do: Map.fetch!(changes, {:journal_lock, journal_step})

  @doc """
  Whether a transaction result is the journal's lock step finding its row
  gone (F49): `{:error, {:journal_lock, _}, :not_found, _}`.
  """
  @spec row_gone?(term()) :: boolean()
  def row_gone?({:error, {:journal_lock, _step}, :not_found, _changes}), do: true
  def row_gone?(_result), do: false

  @doc """
  Lists journal entries, newest first. Filters (all optional):
  `:resource_type`, `:resource_id`, `:actor_type`, `:operation`, `:limit`.
  By default only real writes are returned; `include_scenarios: true` adds
  persisted what-if entries.
  """
  @spec list_entries(keyword()) :: [Entry.t()]
  def list_entries(opts \\ []) when is_list(opts) do
    Entry
    |> filter_scenarios(opts[:include_scenarios])
    |> filter_eq(:resource_type, opts[:resource_type])
    |> filter_eq(:resource_id, opts[:resource_id])
    |> filter_eq(:actor_type, opts[:actor_type])
    |> filter_eq(:operation, opts[:operation])
    |> order_by([e], desc: e.inserted_at, desc: e.id)
    |> maybe_limit(opts[:limit])
    |> Repo.all()
  end

  defp insert_entry(
         repo,
         %Actor{} = actor,
         {operation, resource_type, id},
         record,
         before,
         scenario_id
       ) do
    {actor_type, actor_label} = Actor.to_columns(actor)

    attrs = %{
      actor_type: actor_type,
      actor_label: actor_label,
      operation: operation,
      resource_type: resource_type,
      resource_id: id,
      before: Serializer.snapshot(before),
      after: Serializer.snapshot(record),
      scenario_id: scenario_id
    }

    %Entry{}
    |> Entry.changeset(attrs)
    |> repo.insert()
  end

  defp set_actor_multi(%Actor{} = actor) do
    Multi.run(Multi.new(), :journal_set_actor, fn repo, _changes ->
      {type, label} = Actor.to_columns(actor)
      payload = if label, do: type <> ":" <> label, else: type
      # set_config/3 is the parameterizable form of `SET LOCAL` (is_local = true),
      # so the actor value is bound, never string-interpolated into SQL.
      repo.query!("SELECT set_config($1, $2, true)", [@actor_setting, payload])
      {:ok, payload}
    end)
  end

  defp reset_actor(repo) do
    repo.query!("SELECT set_config($1, NULL, true)", [@actor_setting])
    {:ok, :reset}
  end

  # F49: only a stored row of an update, a delete or an upsert is re-read
  # under a lock; an aggregate (a map, a struct without a table or an id)
  # keeps the image its caller built.
  defp lock_step(operation, %schema{id: id}, journal_step)
       when operation in [:update, :delete, :upsert] and not is_nil(id) do
    if function_exported?(schema, :__schema__, 1) and schema.__schema__(:source) != nil,
      do: {:journal_lock, journal_step},
      else: nil
  end

  defp lock_step(_operation, _before, _journal_step), do: nil

  defp lock_before_multi(nil, _operation, _before), do: Multi.new()

  # The lock is the one the write itself takes, only earlier: an update of
  # non-key columns holds FOR NO KEY UPDATE, so a booking's foreign-key check
  # (KEY SHARE) on the row does not wait for it; a delete holds FOR UPDATE.
  defp lock_before_multi(step, :delete, before),
    do: lock_row_multi(step, before, from(r in before.__struct__, lock: "FOR UPDATE"), :not_found)

  # An upsert whose prior row is gone inserts it afresh: its before-image is
  # then none, not an error.
  defp lock_before_multi(step, :upsert, before),
    do: lock_row_multi(step, before, from(r in before.__struct__, lock: "FOR NO KEY UPDATE"), nil)

  defp lock_before_multi(step, :update, before),
    do:
      lock_row_multi(
        step,
        before,
        from(r in before.__struct__, lock: "FOR NO KEY UPDATE"),
        :not_found
      )

  defp lock_row_multi(step, %{id: id}, query, when_gone) do
    Multi.run(Multi.new(), step, fn repo, _changes ->
      case {repo.one(from(r in query, where: r.id == ^id)), when_gone} do
        {nil, nil} -> {:ok, nil}
        {nil, :not_found} -> {:error, :not_found}
        {row, _when_gone} -> {:ok, row}
      end
    end)
  end

  defp locked_before(_changes, nil, before), do: before
  defp locked_before(changes, step, _before), do: Map.fetch!(changes, step)

  # An update's after-image is the row as stored: the struct Ecto returns is
  # the caller's read with the changes applied, which misses what another
  # writer changed in between.
  defp stored_after(repo, :update, step, %schema{id: id} = record) when not is_nil(step),
    do: repo.get(schema, id) || record

  defp stored_after(_repo, _operation, _step, record), do: record

  # An update whose after-image equals its before-image changed nothing: a
  # valid changeset without changes is not written (Ecto returns the row
  # untouched), and it leaves no entry either (E25 S6, G02). A real change
  # keeps ADR-0017's full before and after snapshots.
  defp unchanged?(:update, before, record) when not is_nil(before),
    do: Serializer.snapshot(before) == Serializer.snapshot(record)

  defp unchanged?(_operation, _before, _record), do: false

  defp resource_id(%{id: id}) when not is_nil(id), do: to_string(id)
  defp resource_id(_record), do: nil

  defp filter_scenarios(query, true), do: query
  defp filter_scenarios(query, _), do: where(query, [e], is_nil(e.scenario_id))

  defp filter_eq(query, _field, nil), do: query
  defp filter_eq(query, field, value), do: where(query, [e], field(e, ^field) == ^value)

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, n) when is_integer(n) and n > 0, do: limit(query, ^n)
end
