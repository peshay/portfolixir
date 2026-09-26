defmodule Portfolixir.Portfolios.PolicyRule do
  @moduledoc """
  The stable identity of a policy rule (ADR-0049 §1, §4): the context it is
  evaluated in, and the operator's name for it — a label on that identity,
  not part of it: a rename is a journaled edit of this row outside the
  versioning (§4 as amended 2026-09-24, #872).

  The predicate is **not** here. It lives on the rule's versions
  (`Portfolixir.Portfolios.PolicyRuleVersion`), because a rule is a standard in
  force over a period: editing it adds a version, and the old one stays
  readable as the standard of its own period.

  The context is `portfolio_id` plus an optional `view_id`; `view_id` NULL is
  the portfolio-wide scope, the convention target plans use (ADR-0020). The
  measure a rule reads is taken on that context's steerable basis. Neither the
  context nor the portfolio is re-assignable: a rule moved to another context
  would be a different standard, and it is created as one.

  Journaled and guard-armed from the migration that created the table
  (ADR-0017).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Input.Text
  alias Portfolixir.Portfolios.PolicyRuleVersion

  # Mirrors the `policy_rules.name` column width.
  @max_name 255

  @type t :: %__MODULE__{}

  schema "policy_rules" do
    field(:portfolio_id, :integer)
    field(:view_id, :integer)
    field(:name, :string)

    # Read-side annotations of the rule list (ADR-0049 §9), relative to the
    # list's `as_of`; virtual, so they never reach the DB or the journal.
    field(:status, Ecto.Enum, values: [:in_force, :scheduled, :retired], virtual: true)
    field(:version_in_force, :map, virtual: true)
    field(:next_version, :map, virtual: true)

    has_many(:versions, PolicyRuleVersion, preload_order: [asc: :valid_from, asc: :id])

    timestamps()
  end

  @doc false
  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [:portfolio_id, :view_id, :name])
    |> validate_name()
    |> validate_required([:portfolio_id])
    |> foreign_key_constraint(:portfolio_id)
    |> foreign_key_constraint(:view_id)
  end

  @doc """
  The rename (#872, ADR-0049 §4 as amended by the Sprint 16 plan D-6): the
  name is the operator's label on the rule, so it is the one field a stored
  rule may change. The context is not cast, whatever `attrs` carries, and the
  name passes the same validation as on create.
  """
  def rename_changeset(%__MODULE__{} = rule, attrs) do
    rule
    |> cast(attrs, [:name])
    |> validate_name()
  end

  # One validation for the name, shared by every writer of it.
  defp validate_name(changeset) do
    changeset
    |> update_change(:name, &trim/1)
    |> validate_required([:name])
    |> Text.validate(:name, max: @max_name)
  end

  # A blank name casts to nil, which a rename carries as a change.
  defp trim(name) when is_binary(name), do: String.trim(name)
  defp trim(nil), do: nil
end
