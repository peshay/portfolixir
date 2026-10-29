defmodule PortfolixirWeb.Api.V1.PolicyRuleVersionHintsTest do
  # A policy rule's new version over the API, and how the MCP companion
  # publishes it (security review 2026-10-12, H13): the request the companion
  # sends for portfolixir.policy_rules.add_version deletes the scheduled
  # versions it replaces and closes the version in force, the effects for
  # which portfolixir.policy_rules.retire is hinted destructive and held with
  # the admin tools. The companion's hint sets and its admin set are read from
  # its source, since this suite runs without Node. Synthetic data only; no
  # network.
  use PortfolixirWeb.ConnCase, async: false

  import Ecto.Query
  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Portfolios.PolicyRules
  alias Portfolixir.Portfolios.PolicyRuleVersion
  alias Portfolixir.Repo

  @tools "mcp-server/src/tools.ts"
  @profiles "mcp-server/src/profiles.ts"
  @add_version "portfolixir.policy_rules.add_version"
  @retire "portfolixir.policy_rules.retire"

  defp today, do: Portfolixir.Clock.today()

  # The names a `const NAME = new Set([...])` or `new Map([...])` of the
  # companion's source lists.
  defp listed(path, constant) do
    source = File.read!(path)

    [_all, block] =
      Regex.run(~r/const #{constant}[^=]*= new (?:Set|Map)\(\[(.*?)\n\]\);/s, source)

    ~r/"(portfolixir\.[a-z_.]+)"/
    |> Regex.scan(block, capture: :all_but_first)
    |> List.flatten()
  end

  # Whether the companion hints `tool` destructive although it routes through
  # POST: it sits in one of the named POST exceptions that hintsFor reads as
  # destructive.
  defp hinted_destructive?(tool) do
    Enum.any?(
      ["REMOVING_POSTS", "MODIFYING_POSTS", "REPLACING_POSTS"],
      fn constant ->
        File.read!(@tools) =~ "const #{constant} " and tool in listed(@tools, constant)
      end
    )
  end

  defp admin?(tool), do: tool in listed(@profiles, "ADMIN_TOOLS")

  defp cap(security, threshold) do
    %{
      "subject_type" => "security",
      "security_id" => security.id,
      "measure" => "weight",
      "kind" => "cap",
      "threshold" => threshold,
      "severity" => "hard",
      "note" => "synthetic single-name line"
    }
  end

  defp rows(rule_id) do
    PolicyRuleVersion
    |> where([v], v.policy_rule_id == ^rule_id)
    |> Repo.all()
    |> Map.new(fn v ->
      {v.id,
       %{
         threshold: Decimal.to_string(v.threshold),
         valid_from: v.valid_from,
         valid_until: v.valid_until,
         author: v.author
       }}
    end)
  end

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    world = base_world(name: "Version hints")
    security = create_security!(name: "Synthetic Solar AG", ticker: "SYNS")
    %{conn: conn, world: world, security: security}
  end

  # User story (security review 2026-10-12, H13):
  # As the operator whose host asks before a destructive call, and who runs
  # the agent under the book profile,
  # I want a new rule version, which closes the version in force and
  # replaces the scheduled ones, published as destructive and held with the
  # admin tools, as the retirement is,
  # so that my standard never changes through a call I was not asked about.
  #
  # Acceptance criteria:
  # - retire is hinted destructive and admin (the control).
  # - The API write the companion sends for add_version closes the version
  #   in force and deletes the scheduled one, journaled under the token.
  # - add_version is hinted destructive and admin.
  test "a write that closes and replaces versions is hinted destructive and held as admin",
       %{conn: conn, world: world, security: security} do
    assert hinted_destructive?(@retire)
    assert admin?(@retire)

    {:ok, rule} =
      PolicyRules.create_rule(
        Actor.owner_ui(),
        %{
          portfolio_id: world.portfolio.id,
          name: "Single name cap",
          version: Map.put(cap(security, "10"), "valid_from", Date.add(today(), -30))
        },
        today: Date.add(today(), -30)
      )

    {:ok, _scheduled} =
      PolicyRules.add_version(
        Actor.owner_ui(),
        rule,
        Map.put(cap(security, "8"), "valid_from", Date.to_iso8601(Date.add(today(), 10)))
      )

    before = rows(rule.id)

    %{"data" => added} =
      conn
      |> post("/api/v1/policy_rules/#{rule.id}/versions", %{"version" => cap(security, "60")})
      |> json_response(201)

    after_write = rows(rule.id)
    removed = Map.keys(before) -- Map.keys(after_write)

    changed =
      for {id, row} <- before,
          Map.has_key?(after_write, id),
          after_write[id] != row,
          do: id

    journal =
      [resource_type: "policy_rule_version", actor_type: :api_token_rw]
      |> Journal.list_entries()
      |> Enum.map(& &1.operation)

    assert added["threshold"] == "60" and added["author"] == "agent"
    assert [_scheduled_id] = removed
    assert [_in_force_id] = changed
    assert "delete" in Enum.map(journal, &to_string/1)

    assert hinted_destructive?(@add_version),
           "#{@add_version} removed #{inspect(removed, charlists: :as_lists)} and closed #{inspect(changed, charlists: :as_lists)}, " <>
             "but the companion hints it as only adding"

    assert admin?(@add_version),
           "#{@add_version} removed #{inspect(removed, charlists: :as_lists)} and closed #{inspect(changed, charlists: :as_lists)}, " <>
             "but the book profile admits it"
  end
end
