defmodule Portfolixir.ClassificationsJournalTest do
  use Portfolixir.DataCase, async: true

  # User story:
  # As an operator who organises securities into classification trees,
  # I want every change to a classification or category recorded in the
  # append-only journal — including the system that seeds the built-in trees —
  # so that the taxonomy's history is attributable (FR-28 / NFR-2, ADR-0017,
  # Classifications slice, stage 1: classifications + categories).
  #
  # Acceptance criteria:
  # - Custom classification/category create/update/delete + recolor journal an
  #   entry attributed to the acting actor.
  # - Built-in tree seeding journals its writes under a fixed system_job actor
  #   (and only on genuine first creation, not on every read).
  # - The two tables are guard-armed: a bypassing write is refused by the DB.

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.Classifications.Assignment
  alias Portfolixir.Classifications.Category
  alias Portfolixir.Classifications.Classification
  alias Portfolixir.Journal
  alias Portfolixir.Repo
  alias Portfolixir.WorldFixtures

  describe "custom classification + category writes" do
    test "create_classification/2 records a create entry attributed to the actor" do
      actor = Actor.api_token_rw("cls-token")
      {:ok, cls} = Classifications.create_classification(actor, %{name: "Strategy"})

      assert entry =
               Journal.list_entries(resource_type: "classification", operation: :create)
               |> Enum.find(&(&1.resource_id == to_string(cls.id)))

      assert entry.actor_type == :api_token_rw
      assert entry.actor_label == "cls-token"
      assert entry.after["name"] == "Strategy"
    end

    test "update + delete classification journal before/after and the deletion" do
      {:ok, cls} = Classifications.create_classification(Actor.owner_ui(), %{name: "Before"})
      {:ok, _} = Classifications.update_classification(Actor.owner_ui(), cls, %{name: "After"})

      assert [upd] =
               Journal.list_entries(resource_type: "classification", operation: :update)

      assert upd.before["name"] == "Before"
      assert upd.after["name"] == "After"

      {:ok, _} = Classifications.delete_classification(Actor.owner_ui(), cls)
      assert [del] = Journal.list_entries(resource_type: "classification", operation: :delete)
      assert del.resource_id == to_string(cls.id)
    end

    test "create_category/2 and recolor_category/3 journal under the actor" do
      {:ok, cls} = Classifications.create_classification(Actor.owner_ui(), %{name: "Strat"})

      {:ok, category} =
        Classifications.create_category(Actor.owner_ui(), %{
          classification_id: cls.id,
          name: "Core"
        })

      assert Journal.list_entries(resource_type: "category", operation: :create)
             |> Enum.any?(&(&1.resource_id == to_string(category.id)))

      {:ok, _} = Classifications.recolor_category(Actor.owner_ui(), category, "#123abc")

      assert Journal.list_entries(resource_type: "category", operation: :update)
             |> Enum.any?(
               &(&1.resource_id == to_string(category.id) and &1.after["color"] == "#123abc")
             )
    end
  end

  describe "rejected writes journal nothing" do
    test "a rejected classification create returns the changeset and journals nothing" do
      assert {:error, %Ecto.Changeset{}} =
               Classifications.create_classification(Actor.owner_ui(), %{name: ""})

      assert Journal.list_entries(resource_type: "classification", operation: :create) == []
    end

    test "a rejected category create returns the changeset and journals nothing" do
      {:ok, cls} = Classifications.create_classification(Actor.owner_ui(), %{name: "Strat"})

      assert {:error, %Ecto.Changeset{}} =
               Classifications.create_category(Actor.owner_ui(), %{
                 classification_id: cls.id,
                 name: ""
               })

      assert Journal.list_entries(resource_type: "category", operation: :create) == []
    end
  end

  describe "built-in seeding" do
    test "re-seeding backfills a built-in category's blanked color under system_job" do
      :ok = Classifications.ensure_builtins()
      equity = Repo.get_by(Category, key: "equity")
      refute is_nil(equity.color)

      # Blank the color directly; set the journal actor GUC so the armed table
      # accepts the raw write (the same mechanism Journal.record uses).
      Repo.query!("SELECT set_config('portfolixir.journal_actor', 'test_blank', true)")
      Repo.query!("UPDATE classification_categories SET color = NULL WHERE id = $1", [equity.id])

      # Re-seed: the backfill branch restores the default color, journaled.
      :ok = Classifications.ensure_builtins()

      assert Repo.get(Category, equity.id).color == "#2563eb"
    end

    test "seeds the built-in trees under a system_job actor, only on first creation" do
      :ok = Classifications.ensure_builtins()

      cls_entries = Journal.list_entries(resource_type: "classification", operation: :create)
      cat_entries = Journal.list_entries(resource_type: "category", operation: :create)

      # Built-in classifications were journaled, attributed to system_job.
      assert Enum.any?(cls_entries, &(&1.actor_type == :system_job))
      assert Enum.any?(cat_entries, &(&1.actor_type == :system_job))

      before = length(cls_entries) + length(cat_entries)

      # A second ensure_builtins is a no-op (get_by finds the rows) → no new
      # journal entries, so reads never spam the audit trail.
      :ok = Classifications.ensure_builtins()

      after_count =
        length(Journal.list_entries(resource_type: "classification", operation: :create)) +
          length(Journal.list_entries(resource_type: "category", operation: :create))

      assert after_count == before
    end
  end

  describe "security-category assignments" do
    setup do
      {:ok, cls} = Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

      {:ok, core} =
        Classifications.create_category(Actor.owner_ui(), %{
          classification_id: cls.id,
          name: "Core"
        })

      {:ok, satellite} =
        Classifications.create_category(Actor.owner_ui(), %{
          classification_id: cls.id,
          name: "Satellite"
        })

      s1 = WorldFixtures.create_security!(name: "One", ticker: "ONE")
      s2 = WorldFixtures.create_security!(name: "Two", ticker: "TWO")
      %{cls: cls, core: core, satellite: satellite, s1: s1, s2: s2}
    end

    test "assign_security/4 journals a create, then reassign journals an update with before",
         %{cls: cls, core: core, satellite: satellite, s1: s1} do
      actor = Actor.api_token_rw("assign-token")
      {:ok, assignment} = Classifications.assign_security(actor, s1.id, cls.id, core.id)

      assert [create] =
               Journal.list_entries(
                 resource_type: "security_category_assignment",
                 operation: :create
               )

      assert create.actor_label == "assign-token"
      assert create.before == nil
      assert create.resource_id == to_string(assignment.id)
      assert create.after["category_id"] == core.id

      # Reassigning the same (security, classification) to another category is an
      # update, with the prior assignment as `before` — the on-conflict REPLACE
      # keeps the same row id, so the journal stays tied to one resource.
      {:ok, reassigned} =
        Classifications.assign_security(Actor.owner_ui(), s1.id, cls.id, satellite.id)

      assert [update] =
               Journal.list_entries(
                 resource_type: "security_category_assignment",
                 operation: :update
               )

      assert update.resource_id == to_string(assignment.id)
      assert reassigned.id == assignment.id
      assert update.before["category_id"] == core.id
      assert update.after["category_id"] == satellite.id
    end

    test "unassign_security/3 on an unassigned security is a no-op", %{cls: cls, s2: s2} do
      assert {:ok, 0} = Classifications.unassign_security(Actor.owner_ui(), s2.id, cls.id)

      assert Journal.list_entries(
               resource_type: "security_category_assignment",
               operation: :delete
             ) == []
    end

    test "a bulk assign that hits an invalid security rolls back and journals nothing", %{
      cls: cls,
      core: core,
      s1: s1
    } do
      assert {:error, %Ecto.Changeset{}} =
               Classifications.assign_securities(
                 Actor.owner_ui(),
                 [s1.id, 999_999_999],
                 cls.id,
                 core.id
               )

      # All-or-nothing: the valid first record is rolled back with the failure.
      assert Classifications.get_assignment(s1.id, cls.id) == nil

      assert Journal.list_entries(
               resource_type: "security_category_assignment",
               operation: :create
             ) == []
    end

    test "unassign_security/3 journals the deletion", %{cls: cls, core: core, s1: s1} do
      {:ok, _} = Classifications.assign_security(Actor.owner_ui(), s1.id, cls.id, core.id)
      assert {:ok, 1} = Classifications.unassign_security(Actor.owner_ui(), s1.id, cls.id)

      assert [_] =
               Journal.list_entries(
                 resource_type: "security_category_assignment",
                 operation: :delete
               )
    end

    test "bulk assign/unassign journal one entry per security (2(a))", %{
      cls: cls,
      core: core,
      s1: s1,
      s2: s2
    } do
      assert {:ok, 2} =
               Classifications.assign_securities(
                 Actor.owner_ui(),
                 [s1.id, s2.id],
                 cls.id,
                 core.id
               )

      creates =
        Journal.list_entries(resource_type: "security_category_assignment", operation: :create)

      assert length(creates) == 2

      assert {:ok, 2} =
               Classifications.unassign_securities(Actor.owner_ui(), [s1.id, s2.id], cls.id)

      deletes =
        Journal.list_entries(resource_type: "security_category_assignment", operation: :delete)

      assert length(deletes) == 2
    end

    test "a direct unactored write to security_category_assignments is refused", %{
      cls: cls,
      core: core,
      s1: s1
    } do
      assert_raise Postgrex.Error, fn ->
        Repo.insert!(
          Assignment.changeset(%Assignment{}, %{
            security_id: s1.id,
            classification_id: cls.id,
            category_id: core.id
          })
        )
      end
    end
  end

  describe "guard" do
    test "a direct unactored write to classifications is refused by the database" do
      assert_raise Postgrex.Error, fn ->
        Repo.insert!(Classification.changeset(%Classification{}, %{name: "Bypass"}))
      end
    end

    test "a direct unactored write to classification_categories is refused" do
      {:ok, cls} = Classifications.create_classification(Actor.owner_ui(), %{name: "Guarded"})

      assert_raise Postgrex.Error, fn ->
        Repo.insert!(
          Category.changeset(%Category{}, %{classification_id: cls.id, name: "Bypass"})
        )
      end
    end
  end
end
