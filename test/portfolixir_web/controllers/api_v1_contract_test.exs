defmodule PortfolixirWeb.ApiV1ContractTest do
  # ADR-0044 §8 (issue #752): the contract-version read over the API.
  use PortfolixirWeb.ConnCase

  alias PortfolixirWeb.Api.V1.Contract

  defp get_json(conn, path, status \\ 200) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
    |> get(path)
    |> json_response(status)
  end

  # User story (ADR-0044 §8, issue #752):
  # As the operating agent,
  # I want one cheap read that says what the surface offers and when it last
  # changed, pollable with since=,
  # so that a capability shipped for me is not invisible until my next
  # requirements edition asks for it again.
  #
  # Acceptance criteria:
  # - GET /api/v1/contract answers version, last_changed_at, the totals and
  #   the entries newest first, each naming endpoints, tools and parameters.
  # - since=<date> narrows to entries strictly after it and answers changed;
  #   a since at or after last_changed_at answers changed: false and no
  #   entries; an invalid since is a 422.
  # - The first entry records this batch's own additions, #740's parameters
  #   included.
  test "serves the manifest, newest first, and answers since=", %{conn: conn} do
    %{"data" => data} = get_json(conn, "/api/v1/contract")

    assert data["version"] == Contract.version()
    assert data["last_changed_at"] == Date.to_iso8601(Contract.last_changed_at())
    assert data["since"] == nil
    assert data["changed"] == true
    assert data["endpoints_total"] == MapSet.size(Contract.endpoints())
    assert data["tools_total"] == MapSet.size(Contract.tools())
    assert data["contract_note"] =~ "since="

    [newest | _] = data["entries"]
    assert newest["version"] == Contract.version()
    assert "GET /api/v1/securities/:security_id/notes" in newest["endpoints"]
    assert "GET /api/v1/contract" in newest["endpoints"]
    assert "portfolixir.notes.append" in newest["tools"]
    assert "portfolixir.contract.get" in newest["tools"]
    assert Enum.any?(newest["parameters"], &(&1 =~ "include_positions"))
    assert Enum.any?(newest["parameters"], &(&1 =~ "min_drift"))
    assert Enum.any?(newest["parameters"], &(&1 =~ "scope=latest|history"))

    # Strictly after the last change: nothing moved.
    last = Contract.last_changed_at()

    %{"data" => quiet} = get_json(conn, "/api/v1/contract?since=#{Date.to_iso8601(last)}")
    assert quiet["changed"] == false
    assert quiet["entries"] == []
    assert quiet["since"] == Date.to_iso8601(last)

    # The day before: everything dated on the last-changed day is new.
    day_before = Date.add(last, -1)
    %{"data" => moved} = get_json(conn, "/api/v1/contract?since=#{Date.to_iso8601(day_before)}")
    assert moved["changed"] == true
    assert Enum.all?(moved["entries"], &(&1["date"] > Date.to_iso8601(day_before)))

    assert %{"errors" => %{"since" => ["is invalid"]}} =
             get_json(conn, "/api/v1/contract?since=yesterday", 422)
  end
end
