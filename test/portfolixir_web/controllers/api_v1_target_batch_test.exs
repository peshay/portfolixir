defmodule PortfolixirWeb.ApiV1TargetBatchTest do
  # E25 S4, G11 (#889): the target-set endpoint accepted an unbounded array and
  # repeated category rows, so one request ran an unbounded number of
  # journaled upserts in one transaction.
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.Journal
  alias Portfolixir.Portfolios.Target
  alias Portfolixir.Portfolios.Targets
  alias Portfolixir.Repo

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    world = base_world(name: "Target batch")

    {:ok, classification} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    {:ok, growth} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Growth"
      })

    {:ok, value} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Value"
      })

    security = create_security!(name: "Kestrel Industrial Group NV", ticker: "KIG")

    {:ok, _} =
      Classifications.assign_security(Actor.owner_ui(), security.id, classification.id, growth.id)

    %{
      conn: conn,
      path: "/api/v1/portfolios/#{world.portfolio.id}/targets",
      classification: classification,
      growth: growth,
      value: value,
      security: security
    }
  end

  defp row(category, weight), do: %{"category_id" => category.id, "target_weight" => weight}

  # User story:
  # As the operator's agent writing a plan's targets,
  # I want a batch that names one category twice, or that carries more rows
  # than the classification can hold, refused as a whole,
  # so that one request cannot run an unbounded number of journaled writes.
  #
  # Acceptance criteria:
  # - A batch with a repeated category row answers 422 naming the category and
  #   writes nothing.
  # - A batch with more rows than the classification's categories plus its
  #   assigned securities answers 422 on targets and writes nothing.
  # - A batch over the fixed maximum answers 422 before anything is read.
  # - A batch of one row per category and one per assigned security succeeds.
  test "a repeated category row or an over-cap batch answers 422 and writes nothing",
       %{conn: conn, path: path} = ctx do
    body =
      conn
      |> put(path, %{
        "classification_id" => ctx.classification.id,
        "targets" => [row(ctx.growth, "0.5"), row(ctx.value, "0.3"), row(ctx.growth, "0.2")]
      })
      |> json_response(422)

    assert inspect(body["errors"]) =~ "#{ctx.growth.id}"

    # Two categories plus one assigned security: at most three rows.
    over_cap =
      [row(ctx.growth, "0.1"), row(ctx.value, "0.1")] ++
        for _ <- 1..2,
            do: %{
              "category_id" => ctx.growth.id,
              "security_id" => ctx.security.id,
              "target_weight" => "0.1"
            }

    body =
      conn
      |> put(path, %{"classification_id" => ctx.classification.id, "targets" => over_cap})
      |> json_response(422)

    assert Map.has_key?(body["errors"], "targets")

    huge = for _ <- 1..(Targets.max_batch() + 1), do: row(ctx.growth, "0.1")

    body =
      conn
      |> put(path, %{"classification_id" => ctx.classification.id, "targets" => huge})
      |> json_response(422)

    assert Map.has_key?(body["errors"], "targets")
    assert Repo.aggregate(Target, :count) == 0
    assert Journal.list_entries(resource_type: "target") == []

    full = [
      row(ctx.growth, "0.6"),
      row(ctx.value, "0.4"),
      %{
        "category_id" => ctx.growth.id,
        "security_id" => ctx.security.id,
        "target_weight" => "0.6"
      }
    ]

    assert %{"data" => %{"targets" => [_, _, _]}} =
             conn
             |> put(path, %{"classification_id" => ctx.classification.id, "targets" => full})
             |> json_response(200)
  end

  # The MCP companion's schema mirrors the fixed maximum, so an agent reads
  # the bound where it builds the call.
  test "the MCP schema's maxItems is the API's fixed maximum" do
    source = File.read!("mcp-server/src/tools.ts")
    [schema] = Regex.run(~r/const targetsSetSchema = \{.*?\n\};/s, source)

    assert schema =~ "maxItems: #{Targets.max_batch()}"

    assert source =~
             ~r/target_weight: z\.string\(\)\s*\}\)\s*\)\s*\.min\(1\)\s*\.max\(#{Targets.max_batch()}\)/
  end
end
