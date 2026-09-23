defmodule PortfolixirWeb.Api.V1.PolicyRuleControllerTest do
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Journal
  alias Portfolixir.Portfolios.PolicyRules

  defp today, do: Portfolixir.Clock.today()

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    world = base_world(name: "Rules API")
    security = create_security!(name: "Helios Solar Systems SE", ticker: "HSS")
    %{conn: conn, world: world, security: security}
  end

  defp weight_cap(security) do
    %{
      "subject_type" => "security",
      "security_id" => security.id,
      "measure" => "weight",
      "kind" => "cap",
      "threshold" => "10",
      "severity" => "hard",
      "note" => "one name never above a tenth"
    }
  end

  # User story (FR-43, ADR-0049 §8, §9):
  # As the operator's agent,
  # I want to write the operator's cap as a rule over the JSON API and read
  # it back,
  # so that the next scheduled run reads the standard from the instance
  # instead of from its prompt.
  #
  # Acceptance criteria:
  # - POST creates the rule with its first version and answers 201; the
  #   thresholds come back as Decimal strings and the closed sets as strings.
  # - The write is journaled under the API token.
  # - The list read returns the rule with its status and the version in
  #   force; the show read returns its whole version history.
  test "creates, lists and shows a rule", %{conn: conn, world: world, security: security} do
    %{"data" => created} =
      conn
      |> post("/api/v1/portfolios/#{world.portfolio.id}/policy_rules", %{
        "rule" => %{"name" => "Single name at most 10 %", "version" => weight_cap(security)}
      })
      |> json_response(201)

    assert created["name"] == "Single name at most 10 %"
    assert created["status"] == "in_force"
    assert created["view_id"] == nil
    version = created["version_in_force"]
    assert version["threshold"] == "10"
    assert version["measure"] == "weight"
    assert version["subject_type"] == "security"
    assert version["security_id"] == security.id
    assert version["severity"] == "hard"
    assert version["valid_from"] == Date.to_iso8601(today())
    assert version["valid_until"] == nil

    assert [%{actor_type: :api_token_rw} | _] = Journal.list_entries(resource_type: "policy_rule")

    %{"data" => list} =
      conn |> get("/api/v1/portfolios/#{world.portfolio.id}/policy_rules") |> json_response(200)

    assert [row] = list["rules"]
    assert row["id"] == created["id"]
    assert list["as_of"] == Date.to_iso8601(today())
    assert list["rules_note"] =~ "never an action"

    %{"data" => shown} =
      conn |> get("/api/v1/policy_rules/#{created["id"]}") |> json_response(200)

    assert [%{"threshold" => "10"}] = shown["versions"]
  end

  # Acceptance criteria (ADR-0049 §4, §8):
  # - POST .../versions is the edit: it adds a version from today and the
  #   previous one is closed the day before, both readable.
  # - POST .../retire ends the version in force — yesterday, or tonight when
  #   it only started today; the default list no longer shows a retired
  #   rule, include_retired=true does, and retiring it again is a 409.
  # - A rule whose version has been in force cannot be deleted: 409 naming
  #   the remedy.
  test "edits by version, retires, and refuses to delete a rule in force",
       %{conn: conn, world: world, security: security} do
    {:ok, rule} =
      PolicyRules.create_rule(
        Actor.owner_ui(),
        %{
          portfolio_id: world.portfolio.id,
          name: "Cap",
          version: Map.put(weight_cap(security), "valid_from", Date.add(today(), -30))
        },
        today: Date.add(today(), -30)
      )

    %{"data" => added} =
      conn
      |> post("/api/v1/policy_rules/#{rule.id}/versions", %{
        "version" => Map.put(weight_cap(security), "threshold", "12")
      })
      |> json_response(201)

    assert added["threshold"] == "12"

    %{"data" => shown} = conn |> get("/api/v1/policy_rules/#{rule.id}") |> json_response(200)
    assert [first, second] = shown["versions"]
    assert first["valid_until"] == Date.to_iso8601(Date.add(today(), -1))
    assert second["valid_from"] == Date.to_iso8601(today())

    %{"errors" => %{"detail" => detail}} =
      conn |> delete("/api/v1/policy_rules/#{rule.id}") |> json_response(409)

    assert detail =~ "retire"

    # The version in force started today, so retiring it ends it tonight: a
    # version that has been the standard is never shortened to nothing.
    %{"data" => same_day} =
      conn |> post("/api/v1/policy_rules/#{rule.id}/retire", %{}) |> json_response(200)

    assert List.last(same_day["versions"])["valid_until"] == Date.to_iso8601(today())

    {:ok, older} =
      PolicyRules.create_rule(
        Actor.owner_ui(),
        %{
          portfolio_id: world.portfolio.id,
          name: "Older cap",
          version: Map.put(weight_cap(security), "valid_from", Date.add(today(), -30))
        },
        today: Date.add(today(), -30)
      )

    conn |> post("/api/v1/policy_rules/#{older.id}/retire", %{}) |> json_response(200)

    %{"data" => %{"rules" => listed}} =
      conn |> get("/api/v1/portfolios/#{world.portfolio.id}/policy_rules") |> json_response(200)

    refute Enum.any?(listed, &(&1["id"] == older.id))

    %{"data" => %{"rules" => with_retired}} =
      conn
      |> get("/api/v1/portfolios/#{world.portfolio.id}/policy_rules?include_retired=true")
      |> json_response(200)

    assert %{"status" => "retired"} = Enum.find(with_retired, &(&1["id"] == older.id))

    %{"errors" => %{"detail" => again}} =
      conn |> post("/api/v1/policy_rules/#{older.id}/retire", %{}) |> json_response(409)

    assert again =~ "already retired"
  end

  # Acceptance criteria (ADR-0049 §4, §9):
  # - as_of= reads the standard in force on a past date.
  # - view= narrows the list to one evaluation context.
  test "reads the standard in force on a date, and per context",
       %{conn: conn, world: world, security: security} do
    {:ok, rule} =
      PolicyRules.create_rule(
        Actor.owner_ui(),
        %{
          portfolio_id: world.portfolio.id,
          name: "Cap",
          version: Map.put(weight_cap(security), "valid_from", Date.add(today(), -30))
        },
        today: Date.add(today(), -30)
      )

    {:ok, _} =
      PolicyRules.add_version(
        Actor.owner_ui(),
        rule,
        Map.put(weight_cap(security), "threshold", "12")
      )

    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Kern"})

    {:ok, _scoped} =
      PolicyRules.create_rule(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        view_id: view.id,
        name: "Cash floor in the core",
        version: %{
          "subject_type" => "cash",
          "measure" => "weight",
          "kind" => "floor",
          "threshold" => "5",
          "severity" => "warn"
        }
      })

    past = Date.to_iso8601(Date.add(today(), -10))

    %{"data" => %{"rules" => rules}} =
      conn
      |> get("/api/v1/portfolios/#{world.portfolio.id}/policy_rules?as_of=#{past}")
      |> json_response(200)

    assert [%{"version_in_force" => %{"threshold" => "10"}}] =
             Enum.filter(rules, &(&1["id"] == rule.id))

    %{"data" => %{"rules" => [scoped]}} =
      conn
      |> get("/api/v1/portfolios/#{world.portfolio.id}/policy_rules?view=#{view.id}")
      |> json_response(200)

    assert scoped["view_id"] == view.id
  end

  # Acceptance criteria (ADR-0049 §8, the error contract):
  # - A predicate that does not fit its measure is a 422 naming the field
  #   under "version".
  # - A malformed as_of, include_retired, view, limit or since is a 422
  #   naming the parameter; an unknown portfolio or rule is a 404.
  test "answers the error contract", %{conn: conn, world: world, security: security} do
    %{"errors" => %{"version" => %{"window" => [_ | _]}}} =
      conn
      |> post("/api/v1/portfolios/#{world.portfolio.id}/policy_rules", %{
        "rule" => %{
          "name" => "Vol",
          "version" => %{
            "subject_type" => "basis",
            "measure" => "volatility",
            "kind" => "cap",
            "threshold" => "15",
            "severity" => "warn"
          }
        }
      })
      |> json_response(422)

    %{"errors" => %{"name" => [_ | _]}} =
      conn
      |> post("/api/v1/portfolios/#{world.portfolio.id}/policy_rules", %{
        "rule" => %{"name" => "", "version" => weight_cap(security)}
      })
      |> json_response(422)

    for {param, value} <- [
          {"as_of", "yesterday"},
          {"include_retired", "maybe"},
          {"view", "abc"},
          {"limit", "-1"},
          {"since", "whenever"}
        ] do
      %{"errors" => errors} =
        conn
        |> get("/api/v1/portfolios/#{world.portfolio.id}/policy_rules?#{param}=#{value}")
        |> json_response(422)

      assert Map.has_key?(errors, param), "expected #{param} to be named, got #{inspect(errors)}"
    end

    conn |> get("/api/v1/portfolios/999999999/policy_rules") |> json_response(404)
    conn |> get("/api/v1/policy_rules/999999999") |> json_response(404)
    conn |> post("/api/v1/policy_rules/999999999/retire", %{}) |> json_response(404)

    conn
    |> post("/api/v1/portfolios/999999999/policy_rules", %{
      "rule" => %{"name" => "x", "version" => weight_cap(security)}
    })
    |> json_response(404)
  end
end
