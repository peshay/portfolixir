defmodule Portfolixir.Dashboards.Dashboard do
  @moduledoc """
  A stored dashboard (ADR-0062 §2): its `name` (1 to `name_max/0`
  characters, trimmed, one line, `Portfolixir.Input.Text`), its `position`
  in the menu (1 or more; the menu reads by position, then id), its
  `layout` (`Portfolixir.Dashboards.Layout`, stored normalized) and its
  `lock_version`, which every change raises by one so a replace built on an
  older read is refused (§2, "Concurrent writes").

  A dashboard is arrangement, not data: it holds no figure, names no row by
  a foreign key (a view is named inside the layout, and a deleted view
  leaves it dangling, §2), and is no part of the ledger.

  **Its own scope and its origin** (ADR-0062's amendment of 2026-11-25,
  point 4; Sprint 32 S1): `view_id`, the view its widgets read before the
  address's scope and the default view, overridden by an item's own,
  validated as an item's is (`scope_changeset/2`) and, like it, no foreign
  key; `template_key`, the template a copy was made from, which reads
  nothing and no write sets but the copy.
  """
  use Ecto.Schema
  import Ecto.Changeset

  import Ecto.Query, only: [from: 2]

  alias Portfolixir.Buckets.View
  alias Portfolixir.Dashboards.Grid
  alias Portfolixir.Dashboards.Layout
  alias Portfolixir.Dashboards.Templates
  alias Portfolixir.Input.Text
  alias Portfolixir.Repo

  @name_max 60
  @max_bigint 9_223_372_036_854_775_807

  @type t :: %__MODULE__{
          id: pos_integer() | nil,
          name: String.t() | nil,
          position: pos_integer() | nil,
          layout: [map()],
          lock_version: pos_integer(),
          grid: pos_integer(),
          view_id: pos_integer() | nil,
          template_key: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "dashboards" do
    field(:name, :string)
    field(:position, :integer)
    # Stored as a jsonb array; validated and normalized by Layout, never
    # cast item by item.
    field(:layout, {:array, :map}, default: [])
    field(:lock_version, :integer, default: 1)
    # The grid the layout was written on (`Portfolixir.Dashboards.Grid`):
    # every write of a layout stores the current one.
    field(:grid, :integer, default: 2)
    # Sprint 32 S1: the dashboard's own view (no foreign key, §2) and the
    # template it was copied from.
    field(:view_id, :integer)
    field(:template_key, :string)

    timestamps(type: :utc_datetime_usec)
  end

  @doc "The longest name, in characters (code points)."
  @spec name_max() :: pos_integer()
  def name_max, do: @name_max

  @doc """
  A new dashboard, or a stored one changed, from `attrs`: any of `"name"`
  and `"layout"` (string keys, as the context passes them). The layout is
  validated by `Portfolixir.Dashboards.Layout.validate/1` and put
  normalized; a refusal is one error on `:layout` whose metadata carry the
  refusal's `index`, `field` and `reason` (and `other` for an overlap). A
  change raises `lock_version` by one; a changeset that changes nothing
  leaves it.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = dashboard, attrs) when is_map(attrs) do
    dashboard
    |> cast(attrs, [:name])
    |> update_change(:name, &trim/1)
    |> validate_required([:name])
    |> Text.validate(:name, max: @name_max)
    |> put_layout(attrs)
    # Every string a normalized layout holds is a registered key, but the
    # text rule stands behind it at any depth, as for every stored map.
    |> Text.validate_map(:layout)
    |> check_constraint(:name, name: :dashboards_name_check)
    |> check_constraint(:layout, name: :dashboards_layout_check)
    |> bump_lock_version()
  end

  @doc """
  The dashboard's own view from `attrs`' `"view_id"` (Sprint 32 S1): a
  whole number naming a view that exists, or `nil` to clear it; anything
  else is refused on `:view_id` („names no view“), checked against
  PostgreSQL's `bigint` before the views are read. Without the key the
  changeset is unchanged. A change raises `lock_version` by one.
  """
  @spec scope_changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def scope_changeset(%__MODULE__{} = dashboard, attrs),
    do: dashboard |> change() |> scope_changeset(attrs)

  def scope_changeset(%Ecto.Changeset{} = changeset, attrs) when is_map(attrs) do
    case Map.fetch(attrs, "view_id") do
      :error ->
        changeset

      {:ok, nil} ->
        changeset |> put_change(:view_id, nil) |> bump_lock_version()

      {:ok, id} ->
        if view_exists?(id),
          do: changeset |> put_change(:view_id, id) |> bump_lock_version(),
          else: add_error(changeset, :view_id, "names no view", validation: :view)
    end
    |> check_constraint(:view_id, name: :dashboards_view_id_check)
  end

  @doc """
  The copy's origin (Sprint 32 S1): `template_key`, one of the templates'
  keys this release ships, or `nil` for a dashboard made from empty. Only a
  create sets it; no write's attrs take it.
  """
  @spec origin_changeset(Ecto.Changeset.t(), String.t() | nil) :: Ecto.Changeset.t()
  def origin_changeset(%Ecto.Changeset{} = changeset, template_key) do
    changeset
    |> put_change(:template_key, template_key)
    |> validate_inclusion(:template_key, Enum.map(Templates.templates(), & &1.key))
    |> check_constraint(:template_key, name: :dashboards_template_key_check)
  end

  @doc """
  The changeset with a dangling own view dropped (§2, as a replace drops an
  item's stale view): a stored `view_id` whose view no longer exists is
  cleared. Reads the views table once when a view is stored.
  """
  @spec drop_dangling_view(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def drop_dangling_view(%Ecto.Changeset{data: %{view_id: id}} = changeset)
      when is_integer(id) do
    if view_exists?(id),
      do: changeset,
      else: changeset |> put_change(:view_id, nil) |> bump_lock_version()
  end

  def drop_dangling_view(changeset), do: changeset

  @doc "Whether `id` names a view that exists (a whole number within `bigint`)."
  @spec view_exists?(term()) :: boolean()
  def view_exists?(id) when is_integer(id) and id >= 1 and id <= @max_bigint,
    do: Repo.exists?(from(v in View, where: v.id == ^id))

  def view_exists?(_id), do: false

  @doc """
  The dashboard moved to `position` in the menu: a whole number from 1 to
  `max_position/0`.
  """
  @spec position_changeset(t(), term()) :: Ecto.Changeset.t()
  def position_changeset(%__MODULE__{} = dashboard, position) when is_integer(position) do
    dashboard
    |> change(position: position)
    |> validate_number(:position,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: max_position()
    )
    |> check_constraint(:position, name: :dashboards_position_check)
    |> bump_lock_version()
  end

  # A whole number only: "2" or 2.0 is refused, never read as 2.
  def position_changeset(%__MODULE__{} = dashboard, _position) do
    dashboard
    |> change()
    |> add_error(:position, "must be a whole number", validation: :integer)
  end

  @doc "The highest position a write may name."
  @spec max_position() :: pos_integer()
  def max_position, do: 10_000

  defp trim(name) when is_binary(name), do: String.trim(name)
  defp trim(other), do: other

  defp put_layout(changeset, attrs) do
    case Map.fetch(attrs, "layout") do
      :error ->
        changeset

      {:ok, raw} ->
        # A replace drops a view id its stored layout already holds and
        # whose view is gone (ADR-0062 §2); a create has none stored.
        case Layout.validate(raw, stored: changeset.data.layout) do
          {:ok, layout} ->
            changeset
            |> put_change(:layout, layout)
            |> put_change(:grid, Grid.current())

          {:error, refusal} ->
            add_error(
              changeset,
              :layout,
              refusal.message,
              Map.to_list(Map.delete(refusal, :message))
            )
        end
    end
  end

  defp bump_lock_version(%Ecto.Changeset{changes: changes} = changeset) when changes == %{},
    do: changeset

  defp bump_lock_version(%Ecto.Changeset{data: %{id: nil}} = changeset), do: changeset

  defp bump_lock_version(changeset),
    do: put_change(changeset, :lock_version, changeset.data.lock_version + 1)
end
