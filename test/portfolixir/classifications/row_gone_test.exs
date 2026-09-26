defmodule Portfolixir.Classifications.RowGoneTest do
  # E25 S6, F49 (#884): every classification writer re-reads the row it
  # writes under its lock, so a row another writer removed after the caller
  # read it answers not_found — never a stale-entry error, a 500. And the
  # removal of an assignment another writer removed first is the same
  # outcome as the removal itself: nothing left to remove.
  #
  # The race tests run the other writer at the exact point of the window
  # through `Portfolixir.Interleave`. Every name is synthetic.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.Interleave
  alias Portfolixir.Journal
  alias Portfolixir.WorldFixtures

  # User story:
  # As the operator renaming, recolouring or moving a category another tab
  # deleted a moment ago,
  # I want a not-found answer,
  # so that the page reloads the tree instead of failing.
  #
  # Acceptance criteria:
  # - An update, a recolour of a deleted category, and a reassignment of a
  #   deleted assignment answer {:error, :not_found} and journal nothing.
  test "a write on a deleted category or assignment answers not_found" do
    {tree, [growth, value]} = tree!("Style", ["Growth", "Value"])
    security = WorldFixtures.create_security!(name: "Synthetic Style Fund", ticker: "SSTY")
    {:ok, assignment} = assign!(security, tree, growth)
    other = WorldFixtures.create_security!(name: "Synthetic Style Fund B", ticker: "SSTB")

    {:ok, _} = Classifications.unassign_security(Actor.owner_ui(), security.id, tree.id)
    {:ok, _} = Classifications.delete_category(Actor.owner_ui(), value)
    before = journal_count()

    assert {:error, :not_found} =
             Classifications.update_category(Actor.owner_ui(), value, %{name: "Deep value"})

    assert {:error, :not_found} =
             Classifications.recolor_category(Actor.owner_ui(), value, "#123456")

    assert {:error, :not_found} =
             Classifications.reassign_assignment(Actor.owner_ui(), assignment, other.id)

    assert journal_count() == before
  end

  # User story:
  # As the operator removing a security from a category while an agent
  # removes the same assignment,
  # I want the second removal to answer that nothing was left to remove,
  # so that neither of us sees an error for a state we both wanted.
  #
  # Acceptance criteria:
  # - The assignment is deleted between the removal's read and its delete:
  #   the removal answers {:ok, 0}; the assignment is gone, with one journal
  #   entry, the other writer's.
  test "an assignment another writer removed first is already gone" do
    {tree, [growth]} = tree!("Style", ["Growth"])
    security = WorldFixtures.create_security!(name: "Synthetic Style Fund", ticker: "SSTY")
    {:ok, _assignment} = assign!(security, tree, growth)

    assignment_read? = fn
      %{source: "security_category_assignments", query: query} -> not (query =~ "FOR")
      _metadata -> false
    end

    assert {{:ok, 0}, {:ok, 1}} =
             Interleave.run(
               assignment_read?,
               fn -> Classifications.unassign_security(agent(), security.id, tree.id) end,
               fn -> Classifications.unassign_security(Actor.owner_ui(), security.id, tree.id) end
             )

    refute Classifications.get_assignment(security.id, tree.id)

    assert [%{actor_type: :api_token_rw}] =
             Journal.list_entries(
               resource_type: "security_category_assignment",
               operation: :delete
             )
  end

  # User story:
  # As the operator deleting a category while another tab deletes its whole
  # classification,
  # I want a not-found answer,
  # so that the page reloads instead of failing on a tree that is gone.
  #
  # Acceptance criteria:
  # - The classification is deleted between the category delete's check and
  #   its tree lock: the delete answers {:error, :not_found} and writes
  #   nothing more.
  test "a category whose classification another writer deleted answers not_found" do
    {tree, [growth]} = tree!("Style", ["Growth"])

    tree_read? = fn
      %{source: "classifications", query: query} -> not (query =~ "FOR")
      _metadata -> false
    end

    {result, mark} =
      Interleave.run(
        tree_read?,
        fn ->
          {:ok, _} = Classifications.delete_classification(Actor.owner_ui(), tree)
          journal_count()
        end,
        fn -> Classifications.delete_category(Actor.owner_ui(), growth) end
      )

    assert {:error, :not_found} = result
    assert journal_count() == mark
    refute Classifications.get_category(growth.id)
  end

  # --- world --------------------------------------------------------------------

  defp agent, do: Actor.api_token_rw("synthetic-agent")

  defp tree!(name, category_names) do
    {:ok, tree} = Classifications.create_classification(Actor.owner_ui(), %{name: name})

    categories =
      for category_name <- category_names do
        {:ok, category} =
          Classifications.create_category(Actor.owner_ui(), %{
            classification_id: tree.id,
            name: category_name
          })

        category
      end

    {tree, categories}
  end

  defp assign!(security, tree, category),
    do: Classifications.assign_security(Actor.owner_ui(), security.id, tree.id, category.id)

  defp journal_count, do: Repo.aggregate(Journal.Entry, :count, :id)
end
