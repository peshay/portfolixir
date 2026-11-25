defmodule Portfolixir.Repo.Migrations.AddScopeAndOriginToDashboards do
  @moduledoc """
  Sprint 32 S1 (ADR-0062's amendment of 2026-11-25, point 4; I61): a
  dashboard's own scope and its origin.

    * `view_id` — the view the dashboard's widgets read, before the
      address's scope and the default view, overridden by an item's own.
      Like an item's view it is no foreign key: a deleted view leaves it
      dangling, read as the default and said in the top bar, and the next
      save drops it (`Portfolixir.Dashboards`). A dashboard holds no
      figure and names no row it depends on.
    * `template_key` — the key of the template a copy was made from, if
      any; it reads nothing and only answers „where did this come from“.
      Bounded like a template key (1 to 40 characters).

  Both are null for every dashboard stored before this migration.
  """
  use Ecto.Migration

  def up do
    alter table(:dashboards) do
      add(:view_id, :bigint)
      add(:template_key, :string, size: 40)
    end

    create(constraint(:dashboards, :dashboards_view_id_check, check: "view_id >= 1"))

    create(
      constraint(:dashboards, :dashboards_template_key_check,
        check: "char_length(template_key) BETWEEN 1 AND 40"
      )
    )
  end

  def down do
    drop(constraint(:dashboards, :dashboards_template_key_check))
    drop(constraint(:dashboards, :dashboards_view_id_check))

    alter table(:dashboards) do
      remove(:template_key)
      remove(:view_id)
    end
  end
end
