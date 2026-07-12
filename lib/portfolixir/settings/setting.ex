defmodule Portfolixir.Settings.Setting do
  @moduledoc """
  One keyed user preference (ADR-0024): a plain string value under a unique
  key. Domain semantics (what a key means, how its value parses) live in
  `Portfolixir.Settings`, not here.
  """

  use Ecto.Schema

  import Ecto.Changeset

  schema "settings" do
    field(:key, :string)
    field(:value, :string)

    timestamps()
  end

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:key, :value])
    |> validate_required([:key, :value])
    |> unique_constraint(:key)
  end
end
