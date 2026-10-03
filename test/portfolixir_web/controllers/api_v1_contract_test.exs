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

    # Sprint 18, PR γ (version 12, after PR β's 11): the screens a stranger
    # meets, one entry for the lane PR. U1 opened it: a split is deleted
    # whole, from any of its rows, in one journaled step (#912, ADR-0028 §1).
    assert newest["version"] == 12
    assert newest["summary"] =~ "U1"
    assert newest["endpoints"] == ["DELETE /api/v1/splits/:transaction_id"]

    # Its MCP twin, an admin tool (the full profile only).
    assert newest["tools"] == ["portfolixir.splits.delete"]

    assert Enum.any?(
             newest["parameters"],
             &(&1 =~ "DELETE /api/v1/splits/:transaction_id" and &1 =~ "#912")
           )

    # Sprint 18, PR β (version 11): the operator's money surface, one entry
    # for the lane PR. F4 opened it: the category result takes the view scope
    # in the performance family's two forms (#901). Found by version from
    # here on.
    sprint18_beta = Enum.find(data["entries"], &(&1["version"] == 11))
    assert sprint18_beta["summary"] =~ "F4"
    assert "GET /api/v1/views/:view_id/category-results" in sprint18_beta["endpoints"]

    assert Enum.any?(
             sprint18_beta["parameters"],
             &(&1 =~ "portfolixir.portfolios.category_results" and &1 =~ "view" and
                 &1 =~ "#901")
           )

    # F5 extends it: the total across every portfolio, a read with no view,
    # reached by the view valuation tool without an id (#1007, D-5).
    assert sprint18_beta["summary"] =~ "F5"
    assert "GET /api/v1/valuation" in sprint18_beta["endpoints"]

    assert Enum.any?(
             sprint18_beta["parameters"],
             &(&1 =~ "portfolixir.views.valuation" and &1 =~ "#1007")
           )

    # F2 extends it: which position made how much of a period's result, in
    # the performance family's two forms (FR-41, ADR-0051 §6 and §11).
    assert sprint18_beta["summary"] =~ "F2"

    for endpoint <- [
          "GET /api/v1/portfolios/:portfolio_id/performance/contribution",
          "GET /api/v1/views/:view_id/performance/contribution"
        ] do
      assert endpoint in sprint18_beta["endpoints"]
    end

    assert Enum.any?(
             sprint18_beta["parameters"],
             &(&1 =~ "computation_basis" and &1 =~ "FR-41")
           )

    # Their MCP twins, read tools in every profile.
    assert "portfolixir.portfolios.contribution" in sprint18_beta["tools"]
    assert "portfolixir.views.contribution" in sprint18_beta["tools"]

    # Sprint 17, PR γ (version 10, after PR β's 9): the operator's due
    # surfaces — the annualized return on both closed-trade reads and the
    # unmatched sells (#984), the merge list's removed bookings per reason
    # (ADR-0050 §12), and the new read of a security's manual quotes with its
    # MCP twin (T-9). Found by version from here on.
    sprint17_gamma = Enum.find(data["entries"], &(&1["version"] == 10))

    assert sprint17_gamma["endpoints"] == [
             "GET /api/v1/securities/:security_id/quotes/manual"
           ]

    assert sprint17_gamma["tools"] == ["portfolixir.quotes.manual"]
    assert Enum.any?(sprint17_gamma["parameters"], &(&1 =~ "annualized_return"))
    assert Enum.any?(sprint17_gamma["parameters"], &(&1 =~ "unmatched_sells"))
    assert Enum.any?(sprint17_gamma["parameters"], &(&1 =~ "deleted_by_reason"))

    # Sprint 17's PR β (version 9): the lane's one entry, opened by the MCP
    # companion's tool profiles (A1, #992). It moves no route. Found by
    # version from here on.
    sprint17_beta = Enum.find(data["entries"], &(&1["version"] == 9))
    assert sprint17_beta["endpoints"] == []
    assert Enum.any?(sprint17_beta["parameters"], &(&1 =~ "PORTFOLIXIR_MCP_PROFILE"))
    # A2 (#993): the twin scope tools name each other, extending the entry.
    assert Enum.any?(sprint17_beta["parameters"], &(&1 =~ "Scope twin"))
    # A4 (#983): the two prompts, and why they are MCP only.
    assert Enum.any?(
             sprint17_beta["parameters"],
             &(&1 =~ "first_setup" and &1 =~ "import_converter")
           )

    assert sprint17_beta["summary"] =~ "MCP only"

    # Sprint 16 (version 8): the batch's one entry, opened by the error
    # envelope of the errors the server answers itself (E25 S2, F68). Found by
    # version from here on.
    sprint16 = Enum.find(data["entries"], &(&1["version"] == 8))
    assert Enum.any?(sprint16["parameters"], &(&1 =~ ~s({"errors": {"detail")))
    # ADR-0050 §11 L1: the identity-field freezes answer 422 on the PATCHes
    # that expose a currency, extending the same entry.
    assert Enum.any?(sprint16["parameters"], &(&1 =~ "is frozen once referenced"))

    # Sprint 15 (version 7): the policy-rules family (ADR-0049) — its reads,
    # its writes and their MCP twins. Found by version from here on.
    sprint15 = Enum.find(data["entries"], &(&1["version"] == 7))
    assert "GET /api/v1/portfolios/:portfolio_id/policy_rules" in sprint15["endpoints"]
    assert "POST /api/v1/policy_rules/:id/versions" in sprint15["endpoints"]
    assert "portfolixir.policy_rules.add_version" in sprint15["tools"]

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
