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

    # The newest entry says what moved — an entry that names nothing is the
    # failure mode this read exists to prevent. Which KIND of thing moved is
    # the batch's business (Sprint 11 moved parameters, Sprint 13 endpoints
    # and tools), so the assertion is on the entry saying something, plus
    # this batch's own additions below.
    assert newest["endpoints"] != [] or newest["tools"] != [] or
             newest["parameters"] != []

    # Sprint 15 (version 7): the policy-rules family (ADR-0049) — its reads,
    # its writes and their MCP twins.
    assert newest["version"] == 7
    assert "GET /api/v1/portfolios/:portfolio_id/policy_rules" in newest["endpoints"]
    assert "POST /api/v1/policy_rules/:id/versions" in newest["endpoints"]
    assert "portfolixir.policy_rules.add_version" in newest["tools"]

    # Sprint 14 (version 6) moved parameters only: the portfolio metrics on
    # the risk read, `required` on both metric payloads (#838), since= on the
    # row collections (#830). Found by version, like every older entry.
    sprint14 = Enum.find(data["entries"], &(&1["version"] == 6))
    assert Enum.any?(sprint14["parameters"], &(&1 =~ "risk_free_rate"))
    assert Enum.any?(sprint14["parameters"], &(&1 =~ "required"))
    assert Enum.any?(sprint14["parameters"], &(&1 =~ "since="))

    sprint13 = Enum.find(data["entries"], &(&1["version"] == 5))
    assert "GET /api/v1/securities/:security_id/metrics" in sprint13["endpoints"]
    assert "portfolixir.securities.metrics" in sprint13["tools"]
    # Found by version, not by position: a newer entry must not move it.
    sprint9 = Enum.find(data["entries"], &(&1["version"] == 2))
    assert "GET /api/v1/securities/:security_id/notes" in sprint9["endpoints"]
    assert "GET /api/v1/contract" in sprint9["endpoints"]
    assert "portfolixir.notes.append" in sprint9["tools"]
    assert "portfolixir.contract.get" in sprint9["tools"]
    assert Enum.any?(sprint9["parameters"], &(&1 =~ "include_positions"))
    assert Enum.any?(sprint9["parameters"], &(&1 =~ "min_drift"))
    assert Enum.any?(sprint9["parameters"], &(&1 =~ "scope=latest|history"))

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

  test "a blank since means the full manifest and a non-string since is a 422", %{conn: conn} do
    assert get_json(conn, "/api/v1/contract?since=")["data"]["since"] == nil

    assert %{"errors" => %{"since" => ["is invalid"]}} =
             get_json(conn, "/api/v1/contract?since[]=x", 422)
  end
end
