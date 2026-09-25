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
end
