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

  alias Portfolixir.Input.BoundedDate
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
  A new name for the window keyed `benchmark_security_id` and `start`: the
  key is the context's, put as a change and bounded like every stored date
  (`Portfolixir.Input.BoundedDate`); only `name` is cast from `attrs`.
  """
  @spec create_changeset(pos_integer(), Date.t(), map()) :: Ecto.Changeset.t()
  def create_changeset(benchmark_security_id, %Date{} = start, attrs) when is_map(attrs) do
    %__MODULE__{}
    |> change(benchmark_security_id: benchmark_security_id, start: start)
    |> changeset(attrs)
  end

  @doc """
  A rename of a stored name, or a new one from `create_changeset/3`; only
  `name` is cast from `attrs`.
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(window_name, attrs) when is_map(attrs) do
    window_name
    |> cast(attrs, [:name])
    |> trim_name()
    |> validate_required([:name])
    |> Text.validate(:name, max: @name_max)
    |> validate_required([:benchmark_security_id, :start])
    |> BoundedDate.validate([:start])
    |> unique_constraint([:benchmark_security_id, :start],
      name: :crash_window_names_key_index,
      message: "already names this window"
    )
    |> check_constraint(:name, name: :crash_window_names_name_check)
  end

  @doc """
  Trims a crash window's name, a detected window's or a manual one's
  (ADR-0058 §4), before each changeset requires it and bounds it with
  `Portfolixir.Input.Text.validate/3` at `name_max/0` characters.
  """
  @spec trim_name(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def trim_name(changeset), do: update_change(changeset, :name, &trim/1)

  defp trim(name) when is_binary(name), do: String.trim(name)
  defp trim(other), do: other
end
