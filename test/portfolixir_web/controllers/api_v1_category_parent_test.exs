defmodule PortfolixirWeb.ApiV1CategoryParentTest do
  # E25 S4, F11 (#889): the category writers refuse a parent that would close
  # a loop in the tree or that sits in another classification, on the API and
  # therefore on the MCP tools that call it.
  use PortfolixirWeb.ConnCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.Classifications.Category
  alias Portfolixir.Repo

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    {:ok, tree} = Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})
    {:ok, other} = Classifications.create_classification(Actor.owner_ui(), %{name: "Other"})

    {:ok, root} =
      Classifications.create_category(Actor.owner_ui(), %{classification_id: tree.id, name: "R"})

    {:ok, child} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: tree.id,
        name: "C",
        parent_id: root.id
      })

    {:ok, foreign} =
      Classifications.create_category(Actor.owner_ui(), %{classification_id: other.id, name: "F"})

    %{conn: conn, tree: tree, root: root, child: child, foreign: foreign}
  end

  # User story:
  # As the agent arranging a classification tree over the API,
  # I want a parent that loops the tree or crosses classifications answered
  # with a field error,
  # so that my write cannot leave a tree every read has to walk forever.
  #
  # Acceptance criteria:
  # - PATCH with the category's own id or a descendant's id as parent answers
  #   422 on parent_id and changes nothing.
  # - POST or PATCH with a parent from another classification answers 422 on
  #   parent_id.
  test "a looping or foreign parent answers 422 on parent_id", ctx do
    %{conn: conn, tree: tree, root: root, child: child, foreign: foreign} = ctx
    base = "/api/v1/classifications/#{tree.id}/categories"

    for {path, body} <- [
          {"#{base}/#{root.id}", %{"category" => %{"parent_id" => root.id}}},
          {"#{base}/#{root.id}", %{"category" => %{"parent_id" => child.id}}},
          {"#{base}/#{child.id}", %{"category" => %{"parent_id" => foreign.id}}}
        ] do
      response = conn |> patch(path, body) |> json_response(422)
      assert [_message] = response["errors"]["parent_id"]
    end

    response =
      conn
      |> post(base, %{"category" => %{"name" => "N", "parent_id" => foreign.id}})
      |> json_response(422)

    assert ["must belong to the same classification"] = response["errors"]["parent_id"]

    assert Repo.get!(Category, root.id).parent_id == nil
    assert Repo.get!(Category, child.id).parent_id == root.id
  end

  # User story (#940):
  # As the agent building a classification tree over the API,
  # I want a parent that would put a category below the tree's 32nd level
  # answered with a field error naming the level,
  # so that I learn the bound from the refusal, as the screen's operator does.
  #
  # Acceptance criteria:
  # - POST under the category on level 32 answers 422 on parent_id: "would
  #   put a category on level 33; a classification has at most 32 levels".
  # - PATCH moving a category with a child under level 31 answers the same,
  #   naming the level its child would take, and moves nothing.
  test "a parent below the tree's last level answers 422 on parent_id", ctx do
    %{conn: conn, tree: tree, root: root, child: child} = ctx
    base = "/api/v1/classifications/#{tree.id}/categories"

    # R and C are levels 1 and 2; levels 3 to 32 below them.
    deepest =
      Enum.reduce(3..32, child, fn level, parent ->
        {:ok, category} =
          Classifications.create_category(Actor.owner_ui(), %{
            classification_id: tree.id,
            name: "L#{level}",
            parent_id: parent.id
          })

        category
      end)

    refusal = ["would put a category on level 33; a classification has at most 32 levels"]

    response =
      conn
      |> post(base, %{"category" => %{"name" => "L33", "parent_id" => deepest.id}})
      |> json_response(422)

    assert response["errors"]["parent_id"] == refusal

    level_31 = Repo.get!(Category, deepest.parent_id)

    {:ok, branch} =
      Classifications.create_category(Actor.owner_ui(), %{classification_id: tree.id, name: "B"})

    {:ok, _twig} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: tree.id,
        name: "T",
        parent_id: branch.id
      })

    response =
      conn
      |> patch("#{base}/#{branch.id}", %{"category" => %{"parent_id" => level_31.id}})
      |> json_response(422)

    assert response["errors"]["parent_id"] == refusal
    assert Repo.get!(Category, branch.id).parent_id == nil
    assert root.parent_id == nil
  end
end
