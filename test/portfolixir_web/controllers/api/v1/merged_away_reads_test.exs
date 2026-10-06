defmodule PortfolixirWeb.Api.V1.MergedAwayReadsTest do
  # ADR-0050 §12 over every security-keyed route (the L3–L5 review round,
  # finding SF-1): "a read of a merged-away id answers 404 with
  # merged_into {kind, id}, following the chain to its live end". The three
  # single-record reads did; every read and write under
  # /api/v1/securities/:security_id/ answered a bare 404 instead, so an
  # agent holding an old id learned nothing. Every name and identifier is
  # synthetic.
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Lifecycle

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    target = security!("Synthetic Harbour Fund")
    source = security!("Synthetic Harbour Fund")

    {:ok, preview} = Lifecycle.preview_security_merge(source.id, target.id)

    {:ok, _record, :applied} =
      Lifecycle.merge_security(Actor.owner_ui(), source.id, target.id, %{
        plan_digest: preview.plan_digest
      })

    %{conn: conn, source: source, target: target}
  end

  # User story:
  # As the agent holding the id of a security the operator merged away,
  # I want every read and write under that id to name the survivor,
  # so that I follow it instead of concluding the history is gone.
  #
  # Acceptance criteria:
  # - GET quotes, the manual-quote summary (Sprint 17 V2), trades, metrics,
  #   notes, events and logo of the merged-away id, and PUT quotes, POST notes and events, POST quotes/release and
  #   sync_quotes, PUT, DELETE and discover of the logo, POST isin-change and
  #   DELETE of an identifier alias (closing act, CR-4) answer 404 with
  #   errors.merged_into {"kind": "security", "id": <survivor>}.
  # - The same routes for an id no merge names answer the plain 404.
  test "every security-keyed route of a merged-away id names the survivor", ctx do
    for {method, path, body} <- routes(ctx.source.id) do
      conn = request(ctx.conn, method, path, body)

      assert %{"errors" => %{"merged_into" => merged_into, "detail" => detail}} =
               json_response(conn, 404),
             "#{method} #{path}"

      assert merged_into == %{"kind" => "security", "id" => ctx.target.id}, "#{method} #{path}"
      assert detail =~ "was merged into security ##{ctx.target.id}"
    end

    for {method, path, body} <- routes(999_999_999) do
      conn = request(ctx.conn, method, path, body)

      assert %{"errors" => errors} = json_response(conn, 404), "#{method} #{path}"
      refute Map.has_key?(errors, "merged_into"), "#{method} #{path}"
    end
  end

  # User story (closing act, EH-4):
  # As the agent holding the id of a security merged into one the operator
  # deleted since (allowed once it held nothing),
  # I want the answer to say the chain ends at a deleted row,
  # so that I am never sent to an id that no longer exists (ADR-0050 §12's
  # "live end").
  #
  # Acceptance criteria:
  # - GET the merged-away security and a route under it answer 404 without
  #   merged_into, the detail naming the deleted survivor; a merge of it
  #   answers already_merged without merged_into.
  test "a chain whose survivor was deleted since names no merged_into", ctx do
    {:ok, _} = Catalog.delete_security(Actor.owner_ui(), ctx.target)

    for path <- [
          "/api/v1/securities/#{ctx.source.id}",
          "/api/v1/securities/#{ctx.source.id}/quotes"
        ] do
      assert %{"errors" => errors} = ctx.conn |> get(path) |> json_response(404), path
      refute Map.has_key?(errors, "merged_into"), path

      assert errors["detail"] ==
               "security ##{ctx.source.id} was merged into security ##{ctx.target.id}, " <>
                 "which has since been deleted",
             path
    end

    other = security!("Synthetic Harbour Fund")

    assert %{"errors" => errors} =
             ctx.conn
             |> post("/api/v1/securities/#{ctx.source.id}/merge", %{
               target_id: other.id,
               plan_digest: "sha256:whatever"
             })
             |> json_response(409)

    assert errors["code"] == "already_merged"
    refute Map.has_key?(errors, "merged_into")

    assert errors["detail"] =~
             "security ##{ctx.target.id}, where the chain ends, has since been deleted"
  end

  # User story (#959; ADR-0050 §12):
  # As the agent comparing against a benchmark security the operator merged
  # away,
  # I want the refusal to name the survivor when the survivor is itself a
  # benchmark, as the merged-away reads do,
  # so that I retry with the security its history lives on instead of
  # concluding the benchmark is gone.
  #
  # Acceptance criteria:
  # - benchmark=security:<merged-away id> on the portfolio, the view and the
  #   view-less benchmark read keeps refusing with errors.benchmark and adds
  #   errors.merged_into {"kind": "security", "id": <survivor>} when the
  #   survivor is a flagged benchmark security.
  # - A retry with the named survivor answers 200 on each read.
  test "the benchmark parameter names a survivor that is a benchmark", ctx do
    target = benchmark!("Synthetic Broad Index")
    source = benchmark!("Synthetic Broad Index")
    merge!(source, target)

    for path <- benchmark_paths() do
      body =
        ctx.conn
        |> get(path, %{"benchmark" => "security:#{source.id}"})
        |> json_response(422)

      assert body == %{
               "errors" => %{
                 "benchmark" => ["is not a benchmark security"],
                 "merged_into" => %{"kind" => "security", "id" => target.id}
               }
             },
             path

      retry =
        ctx.conn
        |> get(path, %{"benchmark" => "security:#{target.id}"})
        |> json_response(200)

      assert retry["data"]["benchmark"]["security_id"] == target.id, path
    end
  end

  # Acceptance criteria (#959):
  # - A survivor that is not flagged is no benchmark to retry with: the
  #   merged-away id answers today's body exactly, with no merged_into.
  # - So do a plain unflagged security and an id no merge names.
  test "the benchmark parameter names no survivor that is no benchmark", ctx do
    paths = benchmark_paths()
    plain = security!("Synthetic Plain Fund")

    for path <- paths, id <- [ctx.source.id, plain.id, 999_999_999] do
      body = ctx.conn |> get(path, %{"benchmark" => "security:#{id}"}) |> json_response(422)

      assert body == %{"errors" => %{"benchmark" => ["is not a benchmark security"]}},
             "#{path} security:#{id}"
    end
  end

  # Acceptance criteria (#959): a chain that ends at a row deleted since
  # answers today's body exactly, with no merged_into: there is no row to
  # point at.
  test "the benchmark parameter names no survivor when the chain ends deleted", ctx do
    {:ok, _} = Catalog.delete_security(Actor.owner_ui(), ctx.target)

    for path <- benchmark_paths() do
      body =
        ctx.conn
        |> get(path, %{"benchmark" => "security:#{ctx.source.id}"})
        |> json_response(422)

      assert body == %{"errors" => %{"benchmark" => ["is not a benchmark security"]}}, path
    end
  end

  # The three benchmark reads: one portfolio, one view, and every account.
  defp benchmark_paths do
    world =
      base_world(name: "Synthetic Bench", cash_name: "Bench Cash", depot_name: "Bench Depot")

    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Synthetic Everything"})

    [
      "/api/v1/portfolios/#{world.portfolio.id}/performance/benchmark",
      "/api/v1/views/#{view.id}/performance/benchmark",
      "/api/v1/performance/benchmark"
    ]
  end

  defp routes(id) do
    [
      {:get, "/api/v1/securities/#{id}/quotes", nil},
      {:get, "/api/v1/securities/#{id}/quotes/manual", nil},
      {:get, "/api/v1/securities/#{id}/trades", nil},
      {:get, "/api/v1/securities/#{id}/metrics", nil},
      {:get, "/api/v1/securities/#{id}/notes", nil},
      {:get, "/api/v1/securities/#{id}/events", nil},
      {:get, "/api/v1/securities/#{id}/logo", nil},
      {:put, "/api/v1/securities/#{id}/quotes",
       %{"quotes" => [%{"date" => "2025-01-02", "close" => "10.00"}]}},
      {:post, "/api/v1/securities/#{id}/notes",
       %{"note" => %{"kind" => "observation", "body" => "Synthetic note."}}},
      {:post, "/api/v1/securities/#{id}/events",
       %{"event" => %{"kind" => "earnings", "date" => "2025-03-01"}}},
      {:post, "/api/v1/securities/#{id}/quotes/release", %{}},
      {:post, "/api/v1/securities/#{id}/sync_quotes", %{}},
      {:put, "/api/v1/securities/#{id}/logo", %{}},
      {:delete, "/api/v1/securities/#{id}/logo", nil},
      {:post, "/api/v1/securities/#{id}/logo/discover", %{}},
      {:post, "/api/v1/securities/#{id}/isin-change",
       %{"isin_change" => %{"new_isin" => "XS00EXSRCE01"}}},
      {:delete, "/api/v1/securities/#{id}/identifier_aliases/1", nil}
    ]
  end

  defp request(conn, :get, path, nil), do: get(conn, path)
  defp request(conn, :delete, path, nil), do: delete(conn, path)
  defp request(conn, :put, path, body), do: put(conn, path, body)
  defp request(conn, :post, path, body), do: post(conn, path, body)

  defp security!(name) do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{name: name, currency_code: "EUR"})

    security
  end

  defp benchmark!(name) do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: name,
        currency_code: "EUR",
        is_benchmark: true
      })

    security
  end

  defp merge!(source, target) do
    {:ok, preview} = Lifecycle.preview_security_merge(source.id, target.id)

    {:ok, _record, :applied} =
      Lifecycle.merge_security(Actor.owner_ui(), source.id, target.id, %{
        plan_digest: preview.plan_digest
      })
  end
end
