defmodule PortfolixirWeb.Api.V1.MergedAwayReadsTest do
  # ADR-0050 §12 over every security-keyed route (the L3–L5 review round,
  # finding SF-1): "a read of a merged-away id answers 404 with
  # merged_into {kind, id}, following the chain to its live end". The three
  # single-record reads did; every read and write under
  # /api/v1/securities/:security_id/ answered a bare 404 instead, so an
  # agent holding an old id learned nothing. Every name and identifier is
  # synthetic.
  use PortfolixirWeb.ConnCase, async: true

  alias Portfolixir.Actor
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
  # - GET quotes, trades, metrics, notes, events and logo of the merged-away
  #   id, and PUT quotes, POST notes and events, answer 404 with
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

  defp routes(id) do
    [
      {:get, "/api/v1/securities/#{id}/quotes", nil},
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
       %{"event" => %{"kind" => "earnings", "date" => "2025-03-01"}}}
    ]
  end

  defp request(conn, :get, path, nil), do: get(conn, path)
  defp request(conn, :put, path, body), do: put(conn, path, body)
  defp request(conn, :post, path, body), do: post(conn, path, body)

  defp security!(name) do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{name: name, currency_code: "EUR"})

    security
  end
end
