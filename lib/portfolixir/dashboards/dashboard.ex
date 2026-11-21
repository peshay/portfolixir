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
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Dashboards.Layout
  alias Portfolixir.Input.Text

  @name_max 60

  @type t :: %__MODULE__{
          id: pos_integer() | nil,
          name: String.t() | nil,
          position: pos_integer() | nil,
          layout: [map()],
          lock_version: pos_integer(),
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
            put_change(changeset, :layout, layout)

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
