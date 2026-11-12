defmodule Portfolixir.Crashes.WindowName do
  @moduledoc """
  The name of a detected crash window (ADR-0058 §3), stored with the
  window's key: the crash benchmark's security id and the window's start,
  read back as `d:<benchmark_security_id>:<start>`. The window itself is
  derived at read and never stored (§2), so a name never moves its dates.

  The key is set by the context from a window the rule detects now
  (`Portfolixir.Crashes.name_window/3`); a caller states only the name: at
  most 80 characters, one line, under ADR-0054 §4's text rules
  (`Portfolixir.Input.Text`), trimmed.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Input.Text

  @name_max 80

  @type t :: %__MODULE__{
          id: pos_integer() | nil,
          benchmark_security_id: pos_integer() | nil,
          start: Date.t() | nil,
          name: String.t() | nil,
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "crash_window_names" do
    field(:benchmark_security_id, :integer)
    field(:start, :date)
    field(:name, :string)

    timestamps(inserted_at: :created_at, type: :utc_datetime_usec)
  end

  @doc "The longest name in characters: 80 (ADR-0058 §4)."
  @spec name_max() :: pos_integer()
  def name_max, do: @name_max

  @doc """
  A new name for the window keyed `benchmark_security_id` and `start`, or a
  rename of a stored one; only `name` is cast from `attrs`.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = window_name, attrs) when is_map(attrs) do
    window_name
    |> cast(attrs, [:name])
    |> validate_name()
    |> validate_required([:benchmark_security_id, :start])
    |> unique_constraint([:benchmark_security_id, :start],
      name: :crash_window_names_key_index,
      message: "already names this window"
    )
    |> check_constraint(:name, name: :crash_window_names_name_check)
  end

  @doc """
  The one rule for a crash window's name, a detected window's or a manual
  one's (ADR-0058 §4): trimmed, required, at most 80 characters, one line,
  ADR-0054 §4's text rules.
  """
  @spec validate_name(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def validate_name(changeset) do
    changeset
    |> update_change(:name, &trim/1)
    |> validate_required([:name])
    |> Text.validate(:name, max: @name_max)
  end

  defp trim(name) when is_binary(name), do: String.trim(name)
  defp trim(other), do: other
end
