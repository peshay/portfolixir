defmodule Portfolixir.Buckets.View do
  @moduledoc """
  A view: a named, global filter over buckets (ADR-0018). A holding matches when
  it is included — always under `include_all`, otherwise when it carries one of
  the `view_include_buckets` — and carries none of the `view_exclude_buckets`.
  Exclude always wins.

  View-definition edits are journaled with the view's whole definition,
  `Portfolixir.Buckets.ViewDefinition` (ADR-0018 §5 as amended in Sprint 16;
  E25 S6, F45), by the `Portfolixir.Buckets` writers; the `views` table and
  its bucket-set link tables stay unarmed scope tables
  (`Portfolixir.Journal.Allowlist`), so that rests on the writers.

  `source_portfolio_id` marks a view seeded by the ADR-0024 portfolio migration
  (NULL = user-created); the migration rollback removes only marked records. It
  is a marker, not a restriction — seeded views stay fully editable — and it is
  deliberately not castable, so user and API writes never set it.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Input.Text

  @type t :: %__MODULE__{}

  schema "views" do
    field(:name, :string)
    field(:include_all, :boolean, default: true)
    field(:source_portfolio_id, :integer)

    timestamps()
  end

  def changeset(view, attrs) do
    view
    |> cast(attrs, [:name, :include_all])
    |> normalize_name()
    |> validate_required([:name, :include_all])
    |> Text.validate(:name, max: 100)
    |> unique_constraint(:name)
  end

  defp normalize_name(changeset) do
    update_change(changeset, :name, fn
      value when is_binary(value) -> String.trim(value)
      value -> value
    end)
  end
end
