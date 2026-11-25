defmodule Portfolixir.Dashboards.Seed do
  @moduledoc """
  A seed record (ADR-0062's amendment of 2026-11-25, point 5; Sprint 32
  S3): the key of a starter template the boot stored once, or counted as
  stored, so a starter the operator deleted is never stored again
  (`Portfolixir.Dashboards.Starters`). Keyed by the template's key; it
  holds no figure and names no dashboard.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Dashboards.Templates

  @type t :: %__MODULE__{template_key: String.t() | nil, seeded_at: DateTime.t() | nil}

  @primary_key {:template_key, :string, autogenerate: false}
  schema "dashboard_seeds" do
    field(:seeded_at, :utc_datetime_usec)
  end

  @doc "A record of the starter `template_key`, seeded at `at`: one of the starters' keys."
  @spec changeset(String.t(), DateTime.t()) :: Ecto.Changeset.t()
  def changeset(template_key, %DateTime{} = at) do
    %__MODULE__{}
    |> change(template_key: template_key, seeded_at: at)
    |> validate_inclusion(:template_key, Enum.map(Templates.starters(), & &1.key))
    |> unique_constraint(:template_key, name: :dashboard_seeds_pkey)
    |> check_constraint(:template_key, name: :dashboard_seeds_template_key_check)
  end
end
