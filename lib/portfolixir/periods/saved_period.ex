defmodule Portfolixir.Periods.SavedPeriod do
  @moduledoc """
  A stored period (ADR-0062's amendment of 2026-11-25, point 6; Sprint 32
  T2): its `name` (1 to `name_max/0` characters, trimmed, one line,
  `Portfolixir.Input.Text`), its first day `from` and its last day `to`, or
  none for "until today", and its `lock_version`, which every change raises
  by one so a replace built on an older read is refused.

  A period is arrangement, not data: it holds no figure and names no row; a
  pin names it by reference (`saved:<id>`), and a deleted one leaves the
  pin dangling. `from` and `to` are stored as `starts_on` and `ends_on`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Clock
  alias Portfolixir.Input.BoundedDate
  alias Portfolixir.Input.Text

  @name_max 40
  @first_day ~D[1970-01-01]

  @type t :: %__MODULE__{
          id: pos_integer() | nil,
          name: String.t() | nil,
          from: Date.t() | nil,
          to: Date.t() | nil,
          lock_version: pos_integer(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "saved_periods" do
    field(:name, :string)
    field(:from, :date, source: :starts_on)
    field(:to, :date, source: :ends_on)
    field(:lock_version, :integer, default: 1)

    timestamps(type: :utc_datetime_usec)
  end

  @doc "The longest name, in characters (code points)."
  @spec name_max() :: pos_integer()
  def name_max, do: @name_max

  @doc """
  A new period, or a stored one changed, from `attrs` (string keys, as the
  context passes them): `"name"`, `"from"` (an ISO date or a `Date`, from
  1970, not after today) and `"to"` (one on or after `from`, or `nil`:
  until today). A change raises `lock_version` by one; a changeset that
  changes nothing leaves it.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = period, attrs) when is_map(attrs) do
    period
    |> cast(attrs, [:name, :from, :to])
    |> update_change(:name, &trim/1)
    |> validate_required([:name, :from])
    |> Text.validate(:name, max: @name_max)
    |> BoundedDate.validate([:from, :to])
    |> validate_from()
    |> validate_span()
    |> check_constraint(:name, name: :saved_periods_name_check)
    |> check_constraint(:to, name: :saved_periods_span_check)
    |> bump_lock_version()
  end

  defp trim(name) when is_binary(name), do: String.trim(name)
  defp trim(other), do: other

  # A period begins on a day that has come: one not yet begun is refused,
  # as the vocabulary refuses a quarter to come.
  defp validate_from(changeset) do
    validate_change(changeset, :from, fn :from, from ->
      cond do
        Date.before?(from, @first_day) -> [from: "must be on or after 1970-01-01"]
        Date.after?(from, Clock.today()) -> [from: "must not be after today"]
        true -> []
      end
    end)
  end

  defp validate_span(changeset) do
    from = get_field(changeset, :from)
    to = get_field(changeset, :to)

    if from && to && Date.after?(from, to),
      do: add_error(changeset, :to, "must be on or after from", validation: :span),
      else: changeset
  end

  defp bump_lock_version(%Ecto.Changeset{changes: changes} = changeset) when changes == %{},
    do: changeset

  defp bump_lock_version(%Ecto.Changeset{data: %{id: nil}} = changeset), do: changeset

  defp bump_lock_version(changeset),
    do: put_change(changeset, :lock_version, changeset.data.lock_version + 1)
end
