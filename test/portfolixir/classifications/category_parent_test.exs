defmodule Portfolixir.Classifications.CategoryParentTest do
  # E25 S4, F11 (#889): a category's parent carried a foreign key and nothing
  # else, so the ordinary write path accepted a parent that made the tree a
  # cycle, or a parent from another classification, and one ancestor walk had
  # neither a visited set nor a depth bound. The writes now refuse such a
  # parent, and every read over the tree terminates on a cycle that is
  # already stored.
  use Portfolixir.DataCase, async: true

  import Ecto.Query
  import Portfolixir.WorldFixtures, only: [base_world: 0, create_security!: 1, buy!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.Classifications.Category
  alias Portfolixir.Portfolios.Allocation
  alias Portfolixir.Portfolios.CategoryResult
  alias Portfolixir.Portfolios.Targets
  alias Portfolixir.Repo

  defp tree!(name) do
    {:ok, classification} =
      Classifications.create_classification(Actor.owner_ui(), %{name: name})

    classification
  end

  defp category!(classification, name, parent \\ nil) do
    {:ok, category} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: classification.id,
        name: name,
        parent_id: parent && parent.id
      })

    category
  end

  # A parent chain that is already stored, the way history written before the
  # guard looks: past the changeset, under the journal's actor.
  defp store_parent!(%Category{id: id}, parent_id) do
    {:ok, {1, _}} =
      Repo.transaction(fn ->
        {type, _label} = Actor.to_columns(Actor.owner_ui())
        Repo.query!("SELECT set_config('portfolixir.journal_actor', $1, true)", [type])

        Category
        |> where(id: ^id)
        |> Repo.update_all(set: [parent_id: parent_id])
      end)
  end

  # Runs one read in a process with a bounded heap and a deadline, so a walk
  # that never ends fails this test instead of the node running the suite.
  defp returns?(fun) do
    supervisor = start_supervised!(Task.Supervisor, id: make_ref())

    task =
      Task.Supervisor.async_nolink(supervisor, fn ->
        Process.flag(:max_heap_size, %{size: 20_000_000, kill: true, error_logger: false})
        fun.()
      end)

    case Task.yield(task, 5_000) || Task.shutdown(task, :brutal_kill) do
      {:ok, _result} -> true
      _ -> false
    end
  end

  defp parent_error(changeset), do: Keyword.get(changeset.errors, :parent_id)

  # User story:
  # As the operator arranging a classification tree (and the agent doing it
  # over the API),
  # I want a parent that would make a category its own ancestor, or that sits
  # in another classification, to be refused with a field error,
  # so that one ordinary write cannot turn the tree into a loop that every
  # allocation and result read has to walk.
  #
  # Acceptance criteria:
  # - A category is refused as its own parent, and as the parent of any of its
  #   ancestors, on update; nothing is stored and nothing is journaled.
  # - A parent from another classification is refused on create and update.
  # - An update cannot move a category into another classification.
  # - Re-homing a category under a non-descendant of the same tree still works.
  test "a cycle-forming or cross-classification parent is refused on create and update" do
    tree = tree!("Strategy")
    other = tree!("Other")

    a = category!(tree, "A")
    b = category!(tree, "B", a)
    c = category!(tree, "C", b)
    foreign = category!(other, "Foreign")

    assert {:error, changeset} =
             Classifications.update_category(Actor.owner_ui(), a, %{parent_id: a.id})

    assert {"would make the category its own ancestor", _} = parent_error(changeset)

    assert {:error, changeset} =
             Classifications.update_category(Actor.owner_ui(), a, %{"parent_id" => c.id})

    assert {"would make the category its own ancestor", _} = parent_error(changeset)

    assert {:error, changeset} =
             Classifications.update_category(Actor.owner_ui(), b, %{parent_id: foreign.id})

    assert {"must belong to the same classification", _} = parent_error(changeset)

    assert {:error, changeset} =
             Classifications.create_category(Actor.owner_ui(), %{
               classification_id: tree.id,
               name: "D",
               parent_id: foreign.id
             })

    assert {"must belong to the same classification", _} = parent_error(changeset)

    assert Repo.get!(Category, a.id).parent_id == nil
    assert Repo.get!(Category, b.id).parent_id == a.id

    assert {:ok, moved} =
             Classifications.update_category(Actor.owner_ui(), c, %{
               "classification_id" => other.id,
               "name" => "C2"
             })

    assert moved.classification_id == tree.id
    assert moved.name == "C2"

    assert {:ok, rehomed} =
             Classifications.update_category(Actor.owner_ui(), c, %{parent_id: a.id})

    assert rehomed.parent_id == a.id
  end

  # User story:
  # As the operator whose tree already holds a parent loop from before the
  # guard,
  # I want every read over the tree to return,
  # so that the pages and reads that could show me the loop stay usable.
  #
  # Acceptance criteria:
  # - With a two-category loop and a self-parent stored, the category results,
  #   the allocation, the effective targets, the tree list, the column specs
  #   and the per-level names each return.
  test "every category-result read returns over a stored cycle and a self-parent" do
    world = base_world()
    tree = tree!("Loop")

    a = category!(tree, "A")
    b = category!(tree, "B", a)
    selfie = category!(tree, "Self")

    store_parent!(a, b.id)
    store_parent!(selfie, selfie.id)

    security = create_security!(name: "Loop Holdings AG", ticker: "LHA")
    buy!(world, security, quantity: "1", price: "10")

    {:ok, _} = Classifications.assign_security(Actor.owner_ui(), security.id, tree.id, b.id)

    pid = world.portfolio.id
    prices = %{security.id => Decimal.new("12")}

    assert returns?(fn -> CategoryResult.for_portfolio(pid, tree.id, prices: prices) end)
    assert returns?(fn -> CategoryResult.for_all_portfolios(tree.id, prices: prices) end)
    assert returns?(fn -> Allocation.for_portfolio(pid, tree.id, prices: prices) end)
    assert returns?(fn -> Targets.effective_targets(pid) end)
    assert returns?(fn -> Classifications.list_trees() end)
    assert returns?(fn -> Classifications.column_specs() end)
    assert returns?(fn -> Classifications.security_level_names(tree.id, 2) end)
  end
end
