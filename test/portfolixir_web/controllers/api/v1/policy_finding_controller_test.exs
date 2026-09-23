defmodule PortfolixirWeb.Api.V1.PolicyFindingControllerTest do
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Portfolios.PolicyRules

  defp today, do: Portfolixir.Clock.today()

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    world = base_world(name: "Findings API")
    security = create_security!(name: "Nordic Timber Holdings AB", ticker: "NTH")
    start = Date.add(today(), -4)
    deposit!(world, "2000", start)
    buy!(world, security, quantity: "4", price: "100", date: start)
    put_quote!(security, start, "100")

    %{conn: conn, world: world, security: security}
  end

  defp rule!(world, name, version, opts \\ []) do
    {:ok, rule} =
      PolicyRules.create_rule(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        view_id: Keyword.get(opts, :view_id),
        name: name,
        version: version
      })

    rule
  end

  # User story (FR-43, ADR-0049 §5):
  # As the operator's agent on a scheduled run,
  # I want the operator's rules evaluated in one read,
  # so that "did anything cross a line?" is one call and not my own
  # arithmetic over three reads.
  #
  # Acceptance criteria:
  # - One finding per rule in force, sorted breached, undetermined, ok; each
  #   carries the rule's words, the thresholds and the measured value as
  #   Decimal strings, its state and its computation basis.
  # - A rule over a refused metric is in the default read as undetermined,
  #   with its reason and ADR-0047's required.
  # - The summary counts every state; the payload states its computation
  #   basis (input series, window, reference, gaps).
  test "evaluates the rules in force into findings", %{
    conn: conn,
    world: world,
    security: security
  } do
    rule!(world, "Single name at most 10 %", %{
      subject_type: "security",
      security_id: security.id,
      measure: "weight",
      kind: "cap",
      threshold: "10",
      severity: "hard"
    })

    rule!(world, "Volatility under 15 %", %{
      subject_type: "basis",
      measure: "volatility",
      window: "90d",
      kind: "cap",
      threshold: "15",
      severity: "warn"
    })

    rule!(world, "Cash at least 50 %", %{
      subject_type: "cash",
      measure: "weight",
      kind: "floor",
      threshold: "50",
      severity: "warn"
    })

    %{"data" => data} =
      conn
      |> get("/api/v1/portfolios/#{world.portfolio.id}/policy_findings")
      |> json_response(200)

    assert data["as_of"] == Date.to_iso8601(today())
    assert data["summary"] == %{"breached" => 1, "undetermined" => 1, "ok" => 1}

    assert [breached, undetermined, ok] = data["findings"]
    assert breached["state"] == "breached"
    assert breached["rule_name"] == "Single name at most 10 %"
    assert breached["value"] == "100"
    assert breached["threshold"] == "10"
    assert breached["distance"] == "90"
    assert breached["measure"] == "weight"
    assert breached["computation_basis"]["source"] =~ "risk lens"

    assert undetermined["state"] == "undetermined"
    assert undetermined["reason"] == "insufficient_data"
    assert undetermined["required"] == 20
    assert undetermined["value"] == nil
    assert undetermined["window"] == "90d"

    assert ok["state"] == "ok"
    assert ok["value"] == "80"

    basis = data["computation_basis"]
    assert Enum.all?(~w(input_series window reference gaps), &is_binary(basis[&1]))
    assert basis["gaps"] =~ "undetermined"
    assert data["findings_note"] =~ "no action"
  end

  # Acceptance criteria (ADR-0049 §5, the pull half of B3.7):
  # - status=breached is the retrievable alarm list; status takes a
  #   comma-separated set; an unknown state is a 422 naming status.
  # - view= evaluates the rules of that context only; a malformed view is a
  #   422, an unknown one a 404; an unknown portfolio a 404.
  test "status= and view= narrow; the error contract holds",
       %{conn: conn, world: world, security: security} do
    rule!(world, "Single name at most 10 %", %{
      subject_type: "security",
      security_id: security.id,
      measure: "weight",
      kind: "cap",
      threshold: "10",
      severity: "hard"
    })

    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Kern"})

    rule!(
      world,
      "HHI in the core",
      %{subject_type: "basis", measure: "hhi", kind: "cap", threshold: "10000", severity: "warn"},
      view_id: view.id
    )

    path = "/api/v1/portfolios/#{world.portfolio.id}/policy_findings"

    %{"data" => alarms} = conn |> get(path <> "?status=breached") |> json_response(200)
    assert [%{"state" => "breached"}] = alarms["findings"]
    assert alarms["status"] == ["breached"]

    %{"data" => both} = conn |> get(path <> "?status=ok,undetermined") |> json_response(200)
    assert both["findings"] == []

    %{"data" => core} = conn |> get(path <> "?view=#{view.id}") |> json_response(200)
    assert [%{"rule_name" => "HHI in the core", "state" => "ok"}] = core["findings"]
    assert core["view"]["id"] == view.id

    %{"errors" => %{"status" => _}} = conn |> get(path <> "?status=green") |> json_response(422)
    %{"errors" => %{"view" => _}} = conn |> get(path <> "?view=abc") |> json_response(422)
    conn |> get(path <> "?view=999999999") |> json_response(404)
    conn |> get("/api/v1/portfolios/999999999/policy_findings") |> json_response(404)
  end
end
