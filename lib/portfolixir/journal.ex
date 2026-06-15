defmodule Portfolixir.Journal do
  @moduledoc """
  Append-only audit journal for financial writes (ADR-0016, FR-28).

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
    * `:scenario_id` — marks a persisted what-if write; defaults to `nil` (real).
    * `:journal_step` — the Multi step name for the insert; defaults to
      `:journal_entry`.

  Returns the augmented `Ecto.Multi`. The actor is set first (so the guard
  trigger sees it during the business write) and reset last.
  """
  @spec record(Multi.t(), Actor.t(), keyword()) :: Multi.t()
  def record(%Multi{} = multi, %Actor{} = actor, opts) when is_list(opts) do
    resource_type = Keyword.fetch!(opts, :resource_type)
    operation = Keyword.fetch!(opts, :operation)
    source = Keyword.fetch!(opts, :source)
    before = Keyword.get(opts, :before)
    scenario_id = Keyword.get(opts, :scenario_id)
    journal_step = Keyword.get(opts, :journal_step, :journal_entry)

    multi
    |> Multi.prepend(set_actor_multi(actor))
    |> Multi.run(journal_step, fn repo, changes ->
      record = Map.fetch!(changes, source)
      insert_entry(repo, actor, operation, resource_type, record, before, scenario_id)
    end)
    |> Multi.run(:journal_reset_actor, fn repo, _changes -> reset_actor(repo) end)
  end

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

  defp insert_entry(repo, %Actor{} = actor, operation, resource_type, record, before, scenario_id) do
    {actor_type, actor_label} = Actor.to_columns(actor)

    attrs = %{
      actor_type: actor_type,
      actor_label: actor_label,
      operation: operation,
      resource_type: resource_type,
      resource_id: resource_id(record),
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

  defp resource_id(%{id: id}) when not is_nil(id), do: to_string(id)
  defp resource_id(_record), do: nil

  defp filter_scenarios(query, true), do: query
  defp filter_scenarios(query, _), do: where(query, [e], is_nil(e.scenario_id))

  defp filter_eq(query, _field, nil), do: query
  defp filter_eq(query, field, value), do: where(query, [e], field(e, ^field) == ^value)

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, n) when is_integer(n) and n > 0, do: limit(query, ^n)
end
