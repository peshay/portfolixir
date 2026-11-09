defmodule Portfolixir.Invariants.StatusNamedOnceTest do
  @moduledoc """
  ADR-0059: a lifecycle is **named once**. Each status module in the registry
  below names its closed sets (`statuses/0`, `actions/0`) and its basis; the
  screen's label module has a clause and a German translation for every
  status; the companion's tool text names every status and every action;
  and the API payload carries `status`, `permits` and the basis from the
  same module. The registry is the coupling: a lifecycle is added here when
  its status module lands, and the build then checks all four surfaces.
  """
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Portfolios.PolicyRules

  @po "priv/gettext/de/LC_MESSAGES/default.po"
  @tools "mcp-server/src/tools.ts"

  # One row per lifecycle: the status module, the web label function for its
  # statuses, the MCP tool whose text names the statuses and the permits,
  # and the API reads (paths, after the fixtures they need) that carry them.
  @registry [
    %{
      status: Portfolixir.Portfolios.PolicyRuleStatus,
      label: &PortfolixirWeb.PolicyRuleLabel.status/1,
      mcp_tool: "portfolixir.policy_rules.list",
      reads: &__MODULE__.policy_rule_reads/0
    }
  ]

  def policy_rule_reads do
    world = base_world(name: "Named once")
    security = create_security!(name: "Nordic Timber Holdings AB", ticker: "NTH")

    {:ok, rule} =
      PolicyRules.create_rule(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        name: "Single name at most 10 %",
        version: %{
          subject_type: "security",
          security_id: security.id,
          measure: "weight",
          kind: "cap",
          threshold: "10",
          severity: "hard"
        }
      })

    [
      {"/api/v1/portfolios/#{world.portfolio.id}/policy_rules", ["rules"]},
      {"/api/v1/policy_rules/#{rule.id}", []}
    ]
  end

  # -- the checks, each returning the offenders it found ----------------------

  defp unlabelled(status_module, label) do
    Enum.reject(status_module.statuses(), fn status ->
      try do
        text = label.(status)
        is_binary(text) and String.trim(text) != ""
      rescue
        FunctionClauseError -> false
      end
    end)
  end

  defp untranslated(status_module, label, po) do
    Enum.reject(status_module.statuses(), fn status ->
      msgid = label.(status)
      translated?(po, msgid)
    end)
  end

  defp translated?(po, msgid) do
    case Regex.run(~r/^msgid "#{Regex.escape(msgid)}"\nmsgstr "([^"]*)"/m, po) do
      [_line, msgstr] -> String.trim(msgstr) != ""
      nil -> false
    end
  end

  # The text between the tool's name and the next `tool(` call.
  defp tool_text(tools, name) do
    case String.split(tools, ~s("#{name}"), parts: 2) do
      [_before, rest] -> rest |> String.split("\n  tool(", parts: 2) |> hd()
      _missing -> ""
    end
  end

  defp unnamed_in_mcp(status_module, tool_text) do
    words =
      Enum.map(status_module.statuses(), &to_string/1) ++
        Enum.map(status_module.actions(), &to_string/1) ++ ["permits"]

    Enum.reject(words, &String.contains?(tool_text, &1))
  end

  defp payload_offenders(data, status_module) do
    statuses = Enum.map(status_module.statuses(), &to_string/1)
    actions = Enum.map(status_module.actions(), &to_string/1)

    Enum.flat_map(List.wrap(data), fn row ->
      [
        if(row["status"] in statuses, do: nil, else: {:status, row["status"]}),
        if(is_list(row["permits"]) and Enum.all?(row["permits"], &(&1 in actions)),
          do: nil,
          else: {:permits, row["permits"]}
        )
      ]
    end)
    |> Enum.reject(&is_nil/1)
  end

  # User story (ADR-0059 §1–§5):
  # As the maintainer who wants the screen, the API and the agent to read the
  # same status,
  # I want every registered lifecycle checked on all four surfaces by the
  # build,
  # so that a status added to the module without its label, its translation,
  # its line in the companion's text or its payload key cannot land.
  #
  # Acceptance criteria:
  # - Each status module names non-empty, unique closed sets and a basis.
  # - The label function has a non-blank clause for every status, and the
  #   German catalogue translates each label.
  # - The named MCP tool's text contains every status, every action and the
  #   word `permits`.
  # - Each API read carries `status` in the statuses, `permits` within the
  #   actions and `status_basis` equal to the module's basis.
  for entry <- @registry do
    @entry entry

    test "#{inspect(entry.status)} is named once on every surface", %{conn: conn} do
      %{status: status_module, label: label, mcp_tool: mcp_tool, reads: reads} = @entry

      statuses = status_module.statuses()
      actions = status_module.actions()
      assert statuses != [] and Enum.uniq(statuses) == statuses
      assert actions != [] and Enum.uniq(actions) == actions
      assert Enum.all?(statuses ++ actions, &is_atom/1)
      assert String.trim(status_module.basis()) != ""

      assert unlabelled(status_module, label) == [],
             "statuses without a label: #{inspect(unlabelled(status_module, label))}"

      po = File.read!(@po)

      assert untranslated(status_module, label, po) == [],
             "labels without a German translation: " <>
               inspect(untranslated(status_module, label, po))

      text = tool_text(File.read!(@tools), mcp_tool)
      assert text != "", "#{mcp_tool} is not in #{@tools}"

      assert unnamed_in_mcp(status_module, text) == [],
             "#{mcp_tool} does not name: #{inspect(unnamed_in_mcp(status_module, text))}"

      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer test-api-token")

      for {path, keys} <- reads.() do
        %{"data" => data} = conn |> get(path) |> json_response(200)
        rows = if keys == [], do: data, else: get_in(data, keys)

        assert payload_offenders(rows, status_module) == [],
               "#{path}: #{inspect(payload_offenders(rows, status_module))}"

        assert data["status_basis"] == status_module.basis(), "#{path} lacks status_basis"
      end
    end
  end

  # The gate's attack case (story workflow): a module whose status has no
  # label, no translation and no line in the companion's text is caught by
  # each check, so a clean tree cannot pass vacuously.
  defmodule Ghost do
    def statuses, do: [:in_force, :ghost]
    def actions, do: [:haunt]
  end

  test "a status missing from a surface is caught by each check" do
    label = fn
      :in_force -> "in force"
    end

    assert unlabelled(Ghost, label) == [:ghost]

    assert untranslated(Ghost, fn _status -> "in force" end, ~s(msgid "in force"\nmsgstr "")) == [
             :in_force,
             :ghost
           ]

    assert unnamed_in_mcp(Ghost, "status in_force, permits") == ["ghost", "haunt"]

    assert payload_offenders([%{"status" => "phantom", "permits" => ["haunt", "sing"]}], Ghost) ==
             [{:status, "phantom"}, {:permits, ["haunt", "sing"]}]

    assert tool_text(~s|tool(\n    "a.tool",\n    "text"\n  ),\n  tool(\n    "b.tool"|, "a.tool") =~
             "text"
  end
end
