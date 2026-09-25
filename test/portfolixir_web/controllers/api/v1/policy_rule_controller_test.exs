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

  # User story (E25 S7, G30, the wording half; T-8):
  # As the operator whose agent's own token can store policy rules,
  # I want the rules and findings reads to call a rule a stored rule and to
  # point to the audit journal for who wrote it,
  # so that a rule the agent wrote is not presented as my own standard.
  #
  # Acceptance criteria:
  # - Neither the list's rules_note nor the findings' findings_note calls a
  #   rule the operator's.
  # - The rules_note names the audit journal as where a rule's author is read.
  test "the notes call a rule a stored rule and point to the journal for its author",
       %{conn: conn, world: world} do
    %{"data" => list} =
      conn |> get("/api/v1/portfolios/#{world.portfolio.id}/policy_rules") |> json_response(200)

    refute list["rules_note"] =~ "operator's"
    assert list["rules_note"] =~ "A rule is a stored standard"
    assert list["rules_note"] =~ "the audit journal"

    %{"data" => findings} =
      conn
      |> get("/api/v1/portfolios/#{world.portfolio.id}/policy_findings")
      |> json_response(200)

    refute findings["findings_note"] =~ "operator's"
    assert findings["findings_note"] =~ "A finding is a stored rule"
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

  # User story (ADR-0049 §8 — referenced objects are protected):
  # As the operator's agent cleaning up the catalog,
  # I want a delete that would leave a rule without its subject refused with
  # the rules named,
  # so that I learn which standard reads the object instead of meeting a
  # 500 or an unexplained "referenced by existing records".
  #
  # Acceptance criteria:
  # - Deleting a security, a category, a classification or a view a rule
  #   version (or a rule's context) references answers 409.
  # - The answer names the rules (id, name, status) and states the remedy:
  #   a rule that has been in force keeps its subject as part of its history;
  #   retiring stops its evaluation, and only a rule never in force is deleted.
  test "deleting what a rule reads is a 409 naming the rules",
       %{conn: conn, world: world, security: security} do
    {:ok, tree} =
      Portfolixir.Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    {:ok, fixed} =
      Portfolixir.Classifications.create_category(Actor.owner_ui(), %{
        classification_id: tree.id,
        name: "Fixed income"
      })

    # A child: deleting its parent would delete it too (closing act, both
    # hunters — the parent's delete answered 422 without the rules' names).
    {:ok, bonds} =
      Portfolixir.Classifications.create_category(Actor.owner_ui(), %{
        classification_id: tree.id,
        parent_id: fixed.id,
        name: "Bonds"
      })

    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Spekulativ"})

    {:ok, security_rule} =
      PolicyRules.create_rule(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        name: "Single name at most 10 %",
        version: weight_cap(security)
      })

    {:ok, category_rule} =
      PolicyRules.create_rule(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        name: "Bonds in band",
        version: %{
          "subject_type" => "category",
          "classification_id" => tree.id,
          "category_id" => bonds.id,
          "measure" => "drift",
          "kind" => "band",
          "lower" => "-3",
          "upper" => "3",
          "severity" => "warn"
        }
      })

    {:ok, view_rule} =
      PolicyRules.create_rule(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        view_id: view.id,
        name: "Cash floor in the view",
        version: %{
          "subject_type" => "cash",
          "measure" => "weight",
          "kind" => "floor",
          "threshold" => "5",
          "severity" => "warn"
        }
      })

    for {path, rule} <- [
          {"/api/v1/securities/#{security.id}", security_rule},
          {"/api/v1/classifications/#{tree.id}/categories/#{bonds.id}", category_rule},
          {"/api/v1/classifications/#{tree.id}/categories/#{fixed.id}", category_rule},
          {"/api/v1/classifications/#{tree.id}", category_rule},
          {"/api/v1/views/#{view.id}", view_rule}
        ] do
      %{"errors" => errors} = conn |> delete(path) |> json_response(409)

      assert [%{"id" => id, "name" => name, "status" => "in_force"}] = errors["policy_rules"],
             "expected #{path} to name the rule, got #{inspect(errors)}"

      assert id == rule.id
      assert name == rule.name
      assert errors["detail"] =~ "policy rule"
      assert errors["detail"] =~ "retire"
    end

    assert Portfolixir.Catalog.get_security(security.id)
    assert Buckets.get_view(view.id)
  end

  # Acceptance criteria (ADR-0049 §8; FR-38 row delta):
  # - Retiring on a named day ends the version in force that day; a malformed
  #   day, or one before yesterday, is a 422 on `valid_until` and nothing ends.
  # - `since=` returns a rule whose own row is older than the cut when one of
  #   its versions changed after it — a new version is a change to the rule.
  test "retires on a named day and reads a rule's new version as a change",
       %{conn: conn, world: world, security: security} do
    create = fn name ->
      {:ok, rule} =
        PolicyRules.create_rule(
          Actor.owner_ui(),
          %{
            portfolio_id: world.portfolio.id,
            name: name,
            version: Map.put(weight_cap(security), "valid_from", Date.add(today(), -30))
          },
          today: Date.add(today(), -30)
        )

      rule
    end

    ending = create.("Ends on a named day")

    for {bad, message} <- [
          {"soon", "is invalid"},
          {Date.to_iso8601(Date.add(today(), -5)), "cannot be before"}
        ] do
      %{"errors" => errors} =
        conn
        |> post("/api/v1/policy_rules/#{ending.id}/retire", %{"valid_until" => bad})
        |> json_response(422)

      assert Enum.any?(errors["valid_until"], &(&1 =~ message))
    end

    day = Date.add(today(), 5)

    %{"data" => retired} =
      conn
      |> post("/api/v1/policy_rules/#{ending.id}/retire", %{"valid_until" => Date.to_iso8601(day)})
      |> json_response(200)

    assert [%{"valid_until" => until}] = retired["versions"]
    assert until == Date.to_iso8601(day)

    edited = create.("Gets a new version")
    untouched = create.("Stays as it is")
    old = NaiveDateTime.add(NaiveDateTime.utc_now(), -3 * 86_400, :second)

    # Test-only clock control, as the delta-read tests do: backdate the rows
    # under a transaction-local journal actor so the cut falls between them.
    Portfolixir.Repo.query!(
      "SELECT set_config('portfolixir.journal_actor', 'test_backdate', true)"
    )

    Portfolixir.Repo.query!("UPDATE policy_rules SET updated_at = $1", [old])
    Portfolixir.Repo.query!("UPDATE policy_rule_versions SET updated_at = $1", [old])

    conn
    |> post("/api/v1/policy_rules/#{edited.id}/versions", %{
      "version" => Map.put(weight_cap(security), "threshold", "12")
    })
    |> json_response(201)

    cut = Date.to_iso8601(Date.add(today(), -1))

    %{"data" => %{"rules" => delta}} =
      conn
      |> get("/api/v1/portfolios/#{world.portfolio.id}/policy_rules?since=#{cut}")
      |> json_response(200)

    ids = Enum.map(delta, & &1["id"])
    assert edited.id in ids
    refute untouched.id in ids
  end

  # User story (#872, ADR-0049 §4 and §8 as amended by the Sprint 16 plan D-6):
  # As the operator's agent,
  # I want to rename a rule over the API,
  # so that a rule whose line was raised can say so without being retired —
  # retiring and re-creating it would split the history the rule exists to
  # keep.
  #
  # Acceptance criteria:
  # - PATCH /api/v1/policy_rules/:id with a name answers 200 with the rule and
  #   its versions, unchanged in number and content; the rename is journaled
  #   under the token with the previous name.
  # - Only the name is read, as on PATCH /api/v1/plans/:id. A predicate field,
  #   a version, or the context in the same body is refused 422 naming each
  #   such field and where it belongs, and nothing is written; any other key
  #   is ignored.
  # - A retired rule can be renamed. A blank, missing or non-text name is 422
  #   on name; an unknown or malformed id is 404.
  test "renames a rule outside the versioning", %{conn: conn, world: world, security: security} do
    {:ok, rule} =
      PolicyRules.create_rule(
        Actor.owner_ui(),
        %{
          portfolio_id: world.portfolio.id,
          name: "Single name at most 8 %",
          version: Map.put(weight_cap(security), "valid_from", Date.add(today(), -30))
        },
        today: Date.add(today(), -30)
      )

    %{"data" => before} = conn |> get("/api/v1/policy_rules/#{rule.id}") |> json_response(200)

    %{"data" => renamed} =
      conn
      |> patch("/api/v1/policy_rules/#{rule.id}", %{
        "name" => "Single name at most 10 %",
        "status" => "retired"
      })
      |> json_response(200)

    assert renamed["id"] == rule.id
    assert renamed["name"] == "Single name at most 10 %"
    assert renamed["status"] == "in_force"
    assert renamed["view_id"] == nil
    assert renamed["versions"] == before["versions"]

    assert [%{actor_type: :api_token_rw, operation: :update} = entry | _] =
             Journal.list_entries(resource_type: "policy_rule")

    assert entry.before["name"] == "Single name at most 8 %"
    assert entry.after["name"] == "Single name at most 10 %"

    # The predicate and the context are not a rename's: named, nothing written.
    %{"errors" => errors} =
      conn
      |> patch("/api/v1/policy_rules/#{rule.id}", %{
        "name" => "Changed twice",
        "threshold" => "12",
        "version" => %{"threshold" => "12"},
        "view_id" => 7
      })
      |> json_response(422)

    assert [threshold_error] = errors["threshold"]
    assert threshold_error =~ "POST /api/v1/policy_rules/#{rule.id}/versions"
    assert [_] = errors["version"]
    assert [view_error] = errors["view_id"]
    assert view_error =~ "context"
    refute Map.has_key?(errors, "name")

    %{"data" => unchanged} = conn |> get("/api/v1/policy_rules/#{rule.id}") |> json_response(200)
    assert unchanged["name"] == "Single name at most 10 %"
    assert unchanged["versions"] == before["versions"]

    # Retired, the rule is still renamable.
    conn |> post("/api/v1/policy_rules/#{rule.id}/retire", %{}) |> json_response(200)

    %{"data" => retired} =
      conn
      |> patch("/api/v1/policy_rules/#{rule.id}", %{"name" => "Old single-name cap"})
      |> json_response(200)

    assert retired["name"] == "Old single-name cap"
    assert retired["status"] == "retired"

    %{"errors" => %{"name" => [_ | _]}} =
      conn |> patch("/api/v1/policy_rules/#{rule.id}", %{"name" => "  "}) |> json_response(422)

    %{"errors" => %{"name" => [_ | _]}} =
      conn |> patch("/api/v1/policy_rules/#{rule.id}", %{}) |> json_response(422)

    %{"errors" => %{"name" => [_ | _]}} =
      conn |> patch("/api/v1/policy_rules/#{rule.id}", %{"name" => 42}) |> json_response(422)

    conn |> patch("/api/v1/policy_rules/999999999", %{"name" => "x"}) |> json_response(404)
    conn |> patch("/api/v1/policy_rules/abc", %{"name" => "x"}) |> json_response(404)

    # The S3/S4/D review round (LD-2): the rule's own read shape carries its
    # versions too; sent back with a new name, they are refused the same way
    # rather than silently dropped.
    %{"errors" => errors} =
      conn
      |> patch("/api/v1/policy_rules/#{rule.id}", %{
        "name" => "Read shape sent back",
        "version_in_force" => %{"threshold" => "12"},
        "next_version" => nil,
        "versions" => []
      })
      |> json_response(422)

    for key <- ["version_in_force", "next_version", "versions"] do
      assert [message] = errors[key], key
      assert message =~ "POST /api/v1/policy_rules/#{rule.id}/versions"
    end

    assert PolicyRules.get_rule(rule.id).name == "Old single-name cap"
  end
end
