defmodule Portfolixir.Dashboards do
  @moduledoc """
  Dashboards composed from widgets (ADR-0062, FR-60).

  * **The registry** (`Portfolixir.Dashboards.Widgets`): every widget kind,
    in code, with its sizes, the read it draws, its period rule and its
    scope (§1).
  * **The templates** (`Portfolixir.Dashboards.Templates`): curated
    layouts in code, never stored and never edited; copied into a stored
    dashboard by `copy_template/3` (§3).
  * **The stored dashboards** (`Portfolixir.Dashboards.Dashboard`): a name,
    a position, a validated layout (`Portfolixir.Dashboards.Layout`) and a
    `lock_version`, at most `max_dashboards/0` of them (§2).

  A dashboard holds no figure: it is arrangement, not data, no part of the
  ledger and no input of any money read. Reads never write: a fresh
  instance stores nothing, and `entries/0` then offers the templates.
  """

  use Gettext, backend: PortfolixirWeb.Gettext

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Dashboards.Dashboard
  alias Portfolixir.Dashboards.Layout
  alias Portfolixir.Dashboards.Templates
  alias Portfolixir.Dashboards.Widgets
  alias Portfolixir.DryRun
  alias Portfolixir.Journal
  alias Portfolixir.Repo

  @max_dashboards 50
  @max_id 9_223_372_036_854_775_807
  @resource_type "dashboard"
  # The transaction advisory lock a create takes before it counts
  # (`Portfolixir.LockTable` row 30).
  @count_lock "dashboards|count"

  @typedoc """
  A refused write: the changeset (the name, the layout naming its first bad
  item in the error's metadata, the lock_version or the position), a key
  the write does not take or one it needs, an unknown id, or the 51st
  dashboard.
  """
  @type refusal ::
          Ecto.Changeset.t()
          | {:unknown_fields, %{String.t() => [String.t()]}}
          | {:missing_fields, %{String.t() => [String.t()]}}
          | :not_found
          | :too_many_dashboards

  @typedoc """
  A menu entry: a stored dashboard, or a template offered while none is
  stored.
  """
  @type entry ::
          %{type: :dashboard, dashboard: Dashboard.t()}
          | %{type: :template, template: Templates.t()}

  # --- the registry and the templates ---------------------------------------

  @doc "Every registered widget kind (`Portfolixir.Dashboards.Widgets.kinds/0`)."
  @spec widgets() :: [Widgets.kind()]
  def widgets, do: Widgets.kinds()

  @doc "The widget kind under `key`, matched as a string, or `:error`."
  @spec fetch_widget(term()) :: {:ok, Widgets.kind()} | :error
  def fetch_widget(key), do: Widgets.fetch(key)

  @doc "The templates this release offers."
  @spec templates() :: [Templates.t()]
  def templates, do: Templates.templates()

  @doc "The template under `key`, matched as a string, or `:error`."
  @spec fetch_template(term()) :: {:ok, Templates.t()} | :error
  def fetch_template(key), do: Templates.fetch(key)

  @doc """
  Validates a layout without storing it (`Portfolixir.Dashboards.Layout.validate/1`):
  `{:ok, normalized}` or `{:error, refusal}` naming the first bad item.
  """
  @spec validate_layout(term()) :: {:ok, [Layout.item()]} | {:error, Layout.refusal()}
  def validate_layout(layout), do: Layout.validate(layout)

  @doc "The most dashboards an instance stores (ADR-0062 §2)."
  @spec max_dashboards() :: pos_integer()
  def max_dashboards, do: @max_dashboards

  @doc "The longest dashboard name, in characters."
  @spec name_max() :: pos_integer()
  def name_max, do: Dashboard.name_max()

  # --- reads ----------------------------------------------------------------

  @doc "The stored dashboards in the menu's order: by position, then id."
  @spec list_dashboards() :: [Dashboard.t()]
  def list_dashboards,
    do: Repo.all(from(d in Dashboard, order_by: [asc: d.position, asc: d.id]))

  @doc """
  The menu's dashboard entries, each marked: the stored dashboards in
  their order, or, while none is stored, the templates (ADR-0062 §3: the
  first entry of a fresh instance is „Überblick“, read-only). Writes
  nothing.
  """
  @spec entries() :: [entry()]
  def entries do
    case list_dashboards() do
      [] -> Enum.map(Templates.templates(), &%{type: :template, template: &1})
      stored -> Enum.map(stored, &%{type: :dashboard, dashboard: &1})
    end
  end

  @doc "The stored dashboard `id`, or `nil` (also for an id no row can carry)."
  @spec get_dashboard(term()) :: Dashboard.t() | nil
  def get_dashboard(id) when is_integer(id) and id >= 1 and id <= @max_id,
    do: Repo.get(Dashboard, id)

  def get_dashboard(_id), do: nil

  # --- writes ---------------------------------------------------------------
  #
  # Every stored write is one journal entry under its actor (ADR-0017),
  # resource type "dashboard"; the table's guard refuses one that is not.

  @doc """
  Creates a dashboard on behalf of `actor` from `attrs`, which take only
  `name` and `layout` (string or atom keys; the layout defaults to the
  empty one). It is placed at the end of the menu (one past the highest
  position) with lock_version 1, journaled as a create.

  `{:error, :too_many_dashboards}` when `max_dashboards/0` are stored: the
  count is read under a transaction advisory lock every create takes, so
  two creates cannot both pass it. Nothing is written on a refusal.
  """
  @spec create_dashboard(Actor.t(), map()) :: {:ok, Dashboard.t()} | {:error, refusal()}
  def create_dashboard(%Actor{} = actor, attrs) when is_map(attrs) do
    with :ok <- closed(attrs, ~w(name layout), "a dashboard's create") do
      changeset = Dashboard.changeset(%Dashboard{}, string_attrs(attrs))

      if changeset.valid?,
        do: insert(actor, changeset),
        else: {:error, Map.put(changeset, :action, :insert)}
    end
  end

  @doc """
  Copies the template `key` into a stored dashboard on behalf of `actor`
  („Anpassen“, ADR-0062 §3): its layout, under `attrs`' `name`, or the
  template's title in the current locale when none is given. `attrs` take
  only `name`. Journaled as a create, under the same limit; an unknown key
  is `{:error, :not_found}`. The template stays as shipped.
  """
  @spec copy_template(Actor.t(), term(), map()) :: {:ok, Dashboard.t()} | {:error, refusal()}
  def copy_template(%Actor{} = actor, key, attrs) when is_map(attrs) do
    with {:ok, template} <- template_or_not_found(key),
         :ok <- closed(attrs, ~w(name), "a template's copy") do
      name = Map.get(string_attrs(attrs), "name", Templates.title(template.key))
      create_dashboard(actor, %{"name" => name, "layout" => template.layout})
    end
  end

  @doc """
  Replaces the name and the layout of the dashboard `id` on behalf of
  `actor`. `attrs` take exactly `name`, `layout` and `lock_version`, the
  lock_version the caller read (ADR-0062 §2): under the row's lock, a
  stored lock_version that differs answers `{:error, :stale, stored}`, the
  dashboard as stored, and nothing is written. Otherwise the replace raises
  lock_version by one and is journaled as an update with its before-image;
  one that changes nothing writes and journals nothing.
  """
  @spec replace_dashboard(Actor.t(), term(), map()) ::
          {:ok, Dashboard.t()} | {:error, :stale, Dashboard.t()} | {:error, refusal()}
  def replace_dashboard(%Actor{} = actor, id, attrs) when is_map(attrs) do
    fields = ~w(name layout lock_version)

    with :ok <- closed(attrs, fields, "a dashboard's replace"),
         attrs = string_attrs(attrs),
         :ok <- required(attrs, fields, "a dashboard's replace"),
         {:ok, read_version} <- lock_version(attrs),
         {:ok, prior} <- fetch(id) do
      Multi.new()
      |> Multi.run(:current, fn _repo, changes ->
        current = Journal.locked_row(changes)

        if current.lock_version == read_version,
          do: {:ok, current},
          else: {:error, current}
      end)
      |> Multi.update(:dashboard, fn %{current: current} ->
        Dashboard.changeset(current, Map.take(attrs, ~w(name layout)))
      end)
      |> journal(actor, :update, prior)
      |> Repo.transaction()
      |> case do
        {:error, :current, %Dashboard{} = stored, _changes} -> {:error, :stale, stored}
        result -> written(result)
      end
    end
  end

  @doc """
  Renames the dashboard `id` on behalf of `actor` under the name's rules,
  journaled as an update; lock_version rises by one.
  """
  @spec rename_dashboard(Actor.t(), term(), term()) :: {:ok, Dashboard.t()} | {:error, refusal()}
  def rename_dashboard(%Actor{} = actor, id, name) do
    update(actor, id, &Dashboard.changeset(&1, %{"name" => name}))
  end

  @doc """
  Moves the dashboard `id` to `position` in the menu (a whole number from
  1 to `Portfolixir.Dashboards.Dashboard.max_position/0`) on behalf of
  `actor`, journaled as an update. Only this row changes: the menu reads
  by position, then id.
  """
  @spec reposition_dashboard(Actor.t(), term(), term()) ::
          {:ok, Dashboard.t()} | {:error, refusal()}
  def reposition_dashboard(%Actor{} = actor, id, position) do
    update(actor, id, &Dashboard.position_changeset(&1, position))
  end

  @doc """
  Deletes the dashboard `id` on behalf of `actor`, journaled as a delete
  with its before-image. It deletes nothing else: no figure, view or
  other dashboard depends on it.
  """
  @spec delete_dashboard(Actor.t(), term()) :: {:ok, Dashboard.t()} | {:error, :not_found}
  def delete_dashboard(%Actor{} = actor, id) do
    with {:ok, prior} <- fetch(id) do
      # The row as the journal's lock step re-read it, so the answer is the
      # row deleted, the entry's before-image, not the earlier read.
      Multi.new()
      |> Multi.delete(:dashboard, &Journal.locked_row/1)
      |> journal(actor, :delete, prior)
      |> Repo.transaction()
      |> written()
    end
  end

  @doc """
  The dry run of `delete_dashboard/2` (`Portfolixir.DryRun`): the real
  delete in a transaction that always rolls back, answering per kind of
  row the count and the ids it removes — the one dashboard, and nothing
  else. Writes nothing.
  """
  @spec dry_run_delete_dashboard(Actor.t(), term()) ::
          {:ok, DryRun.removed()} | {:error, :not_found | :concurrent_change}
  def dry_run_delete_dashboard(%Actor{} = actor, id) do
    with {:ok, _prior} <- fetch(id) do
      DryRun.run([dashboards: Dashboard], fn -> delete_dashboard(actor, id) end)
    end
  end

  defp insert(actor, changeset) do
    Repo.transaction(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [@count_lock])

      if Repo.aggregate(Dashboard, :count) >= @max_dashboards,
        do: Repo.rollback(:too_many_dashboards)

      # One past the highest, capped where a reposition stops: two may then
      # share the last position, and the menu reads them by id.
      position =
        min(
          (Repo.one(from(d in Dashboard, select: max(d.position))) || 0) + 1,
          Dashboard.max_position()
        )

      Multi.new()
      |> Multi.insert(:dashboard, Ecto.Changeset.put_change(changeset, :position, position))
      |> journal(actor, :create, nil)
      |> Repo.transaction()
      |> written()
      |> case do
        {:ok, dashboard} -> dashboard
        {:error, refusal} -> Repo.rollback(refusal)
      end
    end)
  end

  defp update(actor, id, build) do
    with {:ok, prior} <- fetch(id) do
      Multi.new()
      |> Multi.update(:dashboard, &build.(Journal.locked_row(&1)))
      |> journal(actor, :update, prior)
      |> Repo.transaction()
      |> written()
    end
  end

  defp journal(multi, actor, operation, prior) do
    Journal.record(multi, actor,
      resource_type: @resource_type,
      operation: operation,
      source: :dashboard,
      before: prior
    )
  end

  defp written({:ok, %{dashboard: dashboard}}), do: {:ok, dashboard}
  defp written({:error, :dashboard, %Ecto.Changeset{} = invalid, _changes}), do: {:error, invalid}
  defp written({:error, {:journal_lock, _step}, :not_found, _changes}), do: {:error, :not_found}

  defp fetch(id) do
    case get_dashboard(id) do
      %Dashboard{} = dashboard -> {:ok, dashboard}
      nil -> {:error, :not_found}
    end
  end

  defp template_or_not_found(key) do
    case Templates.fetch(key) do
      {:ok, template} -> {:ok, template}
      :error -> {:error, :not_found}
    end
  end

  # The keys a write takes, read as strings (an atom key from code as its
  # name); a key it does not take is refused by name, never made an atom.
  defp closed(attrs, fields, write) do
    attrs
    |> Map.keys()
    |> Enum.map(&key_name/1)
    |> Enum.reject(&(&1 in fields))
    |> case do
      [] ->
        :ok

      unknown ->
        message = "is unknown: #{write} takes only #{Enum.join(fields, ", ")}"
        {:error, {:unknown_fields, Map.new(unknown, &{&1, [message]})}}
    end
  end

  defp required(attrs, fields, write) do
    case Enum.reject(fields, &Map.has_key?(attrs, &1)) do
      [] ->
        :ok

      missing ->
        message = "is required: #{write} takes #{Enum.join(fields, ", ")}"
        {:error, {:missing_fields, Map.new(missing, &{&1, [message]})}}
    end
  end

  defp lock_version(%{"lock_version" => version})
       when is_integer(version) and version >= 1 and version <= @max_id,
       do: {:ok, version}

  defp lock_version(_attrs) do
    {:error,
     %Dashboard{}
     |> Ecto.Changeset.change()
     |> Ecto.Changeset.add_error(
       :lock_version,
       dgettext_noop("errors", "must be the whole number the dashboard was read with"),
       validation: :lock_version
     )
     |> Map.put(:action, :update)}
  end

  defp string_attrs(attrs), do: Map.new(attrs, fn {key, value} -> {key_name(key), value} end)

  defp key_name(key) when is_binary(key), do: key
  defp key_name(key) when is_atom(key), do: Atom.to_string(key)
  defp key_name(key), do: inspect(key)
end
