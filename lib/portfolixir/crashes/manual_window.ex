defmodule Portfolixir.Crashes.ManualWindow do
  @moduledoc """
  A crash window a person drew (ADR-0058 §4): `name`, `start` and `trough`
  (the end of the decline), the creating token (`author`, `operator` or
  `agent`, derived from the credential, ADR-0054 §1; `actor`, the token's
  name), `created_at`. Read back as `m:<id>` with `kind: "manual"` on
  every surface, since its dates were chosen by a person who may have known
  the outcome. It may overlap a detected window or another manual one.

  The caller states `name`, `start` and `trough`, each under §4's rules:
  the name as a detected window's (`Portfolixir.Crashes.WindowName.validate_name/1`),
  the dates ISO calendar dates (`Portfolixir.Input.BoundedDate`), the
  trough after the start, neither after `today`, the day of the write. The
  creating token is the system's to state and stays the creator's on an
  edit.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Crashes.WindowName
  alias Portfolixir.Input.BoundedDate
  alias Portfolixir.Input.Text

  @authors ~w(operator agent)a
  # The width of `crash_manual_windows.actor` (character varying(255)).
  @actor_max 255

  @type t :: %__MODULE__{
          id: pos_integer() | nil,
          name: String.t() | nil,
          start: Date.t() | nil,
          trough: Date.t() | nil,
          author: :operator | :agent | nil,
          actor: String.t() | nil,
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "crash_manual_windows" do
    field(:name, :string)
    field(:start, :date)
    field(:trough, :date)
    field(:author, Ecto.Enum, values: @authors)
    field(:actor, :string)

    timestamps(inserted_at: :created_at, type: :utc_datetime_usec)
  end

  @doc """
  A new manual window, or an edit of a stored one, from the caller's
  `attrs` (any of `name`, `start`, `trough`), checked against `today`.
  The creating token is put by the context on a new window, never cast.
  """
  @spec changeset(t(), map(), Date.t()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = window, attrs, %Date{} = today) when is_map(attrs) do
    window
    |> cast(attrs, [:name, :start, :trough])
    |> WindowName.validate_name()
    |> validate_required([:start, :trough, :author])
    |> BoundedDate.validate([:start, :trough])
    |> validate_not_future([:start, :trough], today)
    |> validate_order()
    |> Text.validate(:actor, max: @actor_max)
    |> check_constraint(:name, name: :crash_manual_windows_name_check)
    |> check_constraint(:trough,
      name: :crash_manual_windows_dates_check,
      message: "must be after start"
    )
    |> check_constraint(:author, name: :crash_manual_windows_author_check)
  end

  defp validate_not_future(changeset, fields, today) do
    Enum.reduce(fields, changeset, fn field, acc ->
      validate_change(acc, field, fn ^field, date ->
        if Date.after?(date, today), do: [{field, "must not be in the future"}], else: []
      end)
    end)
  end

  defp validate_order(changeset) do
    start = get_field(changeset, :start)
    trough = get_field(changeset, :trough)

    if match?(%Date{}, start) and match?(%Date{}, trough) and not Date.after?(trough, start),
      do: add_error(changeset, :trough, "must be after start"),
      else: changeset
  end
end
