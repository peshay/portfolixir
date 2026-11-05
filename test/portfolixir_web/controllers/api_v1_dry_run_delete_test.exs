defmodule PortfolixirWeb.ApiV1DryRunDeleteTest do
  # Sprint 25 X1 (#894, idea F21; plan D-4): DELETE of a classification, a
  # category and a view takes dry_run=true, which answers what the delete
  # would remove, or the refusal it would answer, and writes nothing.
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Classifications
  alias Portfolixir.Portfolios.PolicyRules
  alias Portfolixir.Portfolios.Snapshots
  alias Portfolixir.Portfolios.Targets
  alias Portfolixir.Repo

  defp owner, do: Actor.owner_ui()

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    %{conn: conn, t: world()}
  end

  # A custom tree with a root and a child holding one security, a plan with
  # a category and a position target, and a view including one bucket with
  # a plan of its own and a depot snapshot.
  defp world do
    world = base_world(name: "Dry Run API")
    security = create_security!(name: "Bramble Coast Energy plc", ticker: "BCE")
    {:ok, classification} = Classifications.create_classification(owner(), %{name: "Themes"})

    {:ok, root} =
      Classifications.create_category(owner(), %{
        classification_id: classification.id,
        name: "Energy"
      })

    {:ok, child} =
      Classifications.create_category(owner(), %{
        classification_id: classification.id,
        name: "Offshore wind",
        parent_id: root.id
      })

    {:ok, _} = Classifications.assign_security(owner(), security.id, classification.id, child.id)

    {:ok, _} =
      Targets.set_targets(owner(), world.portfolio.id, classification.id, [
        %{category_id: child.id, target_weight: Decimal.new("0.4")},
        %{category_id: child.id, security_id: security.id, target_weight: Decimal.new("0.2")}
      ])

    suffix = System.unique_integer([:positive])
    {:ok, view} = Buckets.create_view(owner(), %{name: "Themes scope #{suffix}"})
    {:ok, bucket} = Buckets.create_bucket(owner(), %{name: "Themed #{suffix}", dimension: "tag"})
    :ok = Buckets.set_view_buckets(owner(), view, [bucket.id], [])

    {:ok, _} =
      Targets.set_targets(
        owner(),
        world.portfolio.id,
        classification.id,
        [%{category_id: root.id, target_weight: Decimal.new("0.5")}],
        view: view
      )

    {:ok, _} =
      Snapshots.create_snapshot(owner(), %{
        name: "Mid-year",
        view_id: view.id,
        as_of: ~D[2026-07-01]
      })

    %{world: world, classification: classification, root: root, child: child, view: view}
  end

  # Every table of the database with its row count, the journal included.
  defp table_counts do
    %{rows: tables} =
      Repo.query!("SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY 1")

    Map.new(tables, fn [table] ->
      %{rows: [[count]]} = Repo.query!(~s[SELECT count(*) FROM "#{table}"])
      {table, count}
    end)
  end

  defp journal_deletes do
    [operation: :delete]
    |> Portfolixir.Journal.list_entries()
    |> Enum.group_by(& &1.resource_type, &String.to_integer(&1.resource_id))
    |> Map.new(fn {type, ids} -> {type, Enum.sort(ids)} end)
  end

  defp ids(answer, kind), do: get_in(answer, ["would_remove", kind, "ids"])

  # User story (X1, #894):
  # As the operator's agent about to delete a classification over the API,
  # I want DELETE with dry_run=true to answer what the delete would remove,
  # so that I can tell the operator before anything goes.
  #
  # Acceptance criteria:
  # - 200 with data {dry_run: true, would_remove: {kind: {count, ids}}}, one
  #   entry per kind the delete reaches.
  # - Nothing is written: every table and the journal count the same.
  # - The real delete that follows journals the deletes of exactly those ids.
  test "DELETE a classification with dry_run=true answers what goes and writes nothing",
       %{conn: conn, t: t} do
    counts = table_counts()
    path = "/api/v1/classifications/#{t.classification.id}"

    answer = conn |> delete(path <> "?dry_run=true") |> json_response(200) |> Map.fetch!("data")

    assert table_counts() == counts
    assert answer["dry_run"] == true

    assert Map.keys(answer["would_remove"]) |> Enum.sort() ==
             ~w(assignments categories classifications target_plans targets)

    assert answer["would_remove"]["classifications"] == %{
             "count" => 1,
             "ids" => [t.classification.id]
           }

    assert answer["would_remove"]["categories"]["count"] == 2

    assert conn |> delete(path) |> json_response(200) == %{"data" => %{"deleted" => true}}

    journaled = journal_deletes()
    assert ids(answer, "classifications") == journaled["classification"]
    assert ids(answer, "categories") == journaled["category"]
    assert ids(answer, "assignments") == journaled["security_category_assignment"]
    assert ids(answer, "target_plans") == journaled["target_plan"]
    assert ids(answer, "targets") == journaled["target"]
  end

  # User story (X1, #894):
  # As the operator's agent about to delete a category over the API,
  # I want its dry run to name the sub-categories, assignments and targets
  # that go with it.
  #
  # Acceptance criteria:
  # - 200 with the kinds categories, assignments and targets; nothing is
  #   written; the real delete journals exactly those ids.
  test "DELETE a category with dry_run=true answers what goes and writes nothing",
       %{conn: conn, t: t} do
    counts = table_counts()
    path = "/api/v1/classifications/#{t.classification.id}/categories/#{t.root.id}"

    answer = conn |> delete(path <> "?dry_run=true") |> json_response(200) |> Map.fetch!("data")

    assert table_counts() == counts
    assert answer["dry_run"] == true
    assert Map.keys(answer["would_remove"]) |> Enum.sort() == ~w(assignments categories targets)
    assert ids(answer, "categories") == Enum.sort([t.root.id, t.child.id])

    assert conn |> delete(path) |> json_response(200) == %{"data" => %{"deleted" => true}}

    journaled = journal_deletes()
    assert ids(answer, "categories") == journaled["category"]
    assert ids(answer, "assignments") == journaled["security_category_assignment"]
    assert ids(answer, "targets") == journaled["target"]
  end

  # User story (X1, #894):
  # As the operator's agent about to delete a view over the API,
  # I want its dry run to name its bucket sets, its plans with their targets
  # and its depot snapshots.
  #
  # Acceptance criteria:
  # - 200 (where the real delete answers 204) with the kinds views,
  #   view_include_buckets, view_exclude_buckets, target_plans, targets and
  #   depot_snapshots; nothing is written; the real delete journals exactly
  #   the ids of the journaled kinds.
  test "DELETE a view with dry_run=true answers what goes and writes nothing",
       %{conn: conn, t: t} do
    counts = table_counts()
    path = "/api/v1/views/#{t.view.id}"

    answer = conn |> delete(path <> "?dry_run=true") |> json_response(200) |> Map.fetch!("data")

    assert table_counts() == counts
    assert answer["dry_run"] == true

    assert Map.keys(answer["would_remove"]) |> Enum.sort() ==
             ~w(depot_snapshots target_plans targets view_exclude_buckets view_include_buckets views)

    assert answer["would_remove"]["view_include_buckets"]["count"] == 1
    assert answer["would_remove"]["view_exclude_buckets"] == %{"count" => 0, "ids" => []}

    assert conn |> delete(path) |> response(204)

    journaled = journal_deletes()
    assert ids(answer, "views") == journaled["view"]
    assert ids(answer, "target_plans") == journaled["target_plan"]
    assert ids(answer, "targets") == journaled["target"]
    assert ids(answer, "depot_snapshots") == journaled["snapshot"]
  end

  # User story (X1, #894):
  # As the operator's agent asking first,
  # I want a delete the server refuses refused by its dry run with the same
  # status and body,
  # so that a dry run never promises a delete that would not happen.
  #
  # Acceptance criteria:
  # - A built-in classification: 422, the same body as the delete's.
  # - A category and a view a policy rule reads: 409 naming the rules, the
  #   same body as the delete's.
  # - An unknown id: 404, the same body.
  # - Nothing is written by any of them.
  test "a refused delete's dry run answers the same status and body", %{conn: conn, t: t} do
    Classifications.ensure_builtins()
    asset = Classifications.get_classification_by_key("asset_class")

    {:ok, _} =
      PolicyRules.create_rule(owner(), %{
        portfolio_id: t.world.portfolio.id,
        name: "Offshore wind in band",
        version: %{
          "subject_type" => "category",
          "classification_id" => t.classification.id,
          "category_id" => t.child.id,
          "measure" => "drift",
          "kind" => "band",
          "lower" => "-3",
          "upper" => "3",
          "severity" => "warn"
        }
      })

    {:ok, _} =
      PolicyRules.create_rule(owner(), %{
        portfolio_id: t.world.portfolio.id,
        view_id: t.view.id,
        name: "Cash floor in the view",
        version: %{
          "subject_type" => "cash",
          "measure" => "weight",
          "kind" => "floor",
          "threshold" => "5",
          "severity" => "warn"
        }
      })

    for {path, status} <- [
          {"/api/v1/classifications/#{asset.id}", 422},
          {"/api/v1/classifications/#{t.classification.id}", 409},
          {"/api/v1/classifications/#{t.classification.id}/categories/#{t.root.id}", 409},
          {"/api/v1/views/#{t.view.id}", 409},
          {"/api/v1/views/999999999", 404},
          {"/api/v1/classifications/999999999", 404}
        ] do
      counts = table_counts()
      dry_run = conn |> delete(path <> "?dry_run=true") |> json_response(status)
      assert table_counts() == counts
      assert conn |> delete(path) |> json_response(status) == dry_run, path
      assert table_counts() == counts
    end
  end

  # User story (X1, #894):
  # As the operator's agent,
  # I want a dry_run that is not a boolean refused,
  # so that a typo never turns a question into a delete.
  #
  # Acceptance criteria:
  # - dry_run=yes (or 1) answers 422 errors.dry_run ["is invalid"] on each
  #   of the three routes, and nothing is written.
  # - dry_run=false is the real delete.
  test "a dry_run that is not a boolean answers 422 and deletes nothing", %{conn: conn, t: t} do
    paths = [
      "/api/v1/classifications/#{t.classification.id}/categories/#{t.root.id}",
      "/api/v1/classifications/#{t.classification.id}",
      "/api/v1/views/#{t.view.id}"
    ]

    counts = table_counts()

    for path <- paths, value <- ["yes", "1", "TRUE"] do
      assert conn |> delete(path <> "?dry_run=#{value}") |> json_response(422) ==
               %{"errors" => %{"dry_run" => ["is invalid"]}}
    end

    assert table_counts() == counts

    assert conn |> delete("/api/v1/views/#{t.view.id}?dry_run=false") |> response(204)
    refute Buckets.get_view(t.view.id)
  end

  # User story (Sprint 25 closing act, X1, #894):
  # As the operator's agent asking a cascading delete what it would remove,
  # I want a misspelled or empty dry_run refused,
  # so that a typo in the question never runs the real delete.
  #
  # Acceptance criteria:
  # - Any query parameter other than dry_run (dryRun, dry-run, dryrun, or
  #   one unrelated) answers 422 naming it, on each of the three routes.
  # - An empty dry_run= answers 422 errors.dry_run ["is invalid"]: only an
  #   absent dry_run, false or true is accepted.
  # - Nothing is deleted by any of them, every table counted before and
  #   after.
  test "a misspelled or empty dry_run answers 422 and deletes nothing", %{conn: conn, t: t} do
    paths = [
      "/api/v1/classifications/#{t.classification.id}/categories/#{t.root.id}",
      "/api/v1/classifications/#{t.classification.id}",
      "/api/v1/views/#{t.view.id}"
    ]

    counts = table_counts()

    for path <- paths, key <- ["dryRun", "dry-run", "dryrun", "confirm"] do
      assert conn |> delete(path <> "?#{key}=true") |> json_response(422) ==
               %{"errors" => %{key => ["is unknown: this delete takes only dry_run"]}},
             "#{path} #{key}"
    end

    for path <- paths do
      assert conn |> delete(path <> "?dry_run=") |> json_response(422) ==
               %{"errors" => %{"dry_run" => ["is invalid"]}},
             path

      assert conn |> delete(path <> "?dry_run=true&dryRun=true") |> json_response(422) ==
               %{"errors" => %{"dryRun" => ["is unknown: this delete takes only dry_run"]}},
             path
    end

    assert table_counts() == counts
    assert Classifications.get_classification(t.classification.id)
    assert Buckets.get_view(t.view.id)
  end
end
