defmodule PortfolixirWeb.RiskPolicyRuleAuthorLiveTest do
  # E25 S7, G30 and T-8 on Wealth → Risk: the owner's pick G12.1 = A on
  # board 12-e25-new-marks — "Agent" as the last word of the words line of a
  # rule whose version in force the agent wrote (scheduled and retired rules
  # alike), and the author on every entry of the dialog's version list.
  use PortfolixirWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Portfolios.PolicyRules

  defp today, do: Portfolixir.Clock.today()

  defp world do
    world = base_world(name: "Autoren")
    nordic = create_security!(name: "Nordic Timber Holdings AB", ticker: "NTH")
    start = Date.add(today(), -5)
    deposit!(world, "10000", start)
    buy!(world, nordic, quantity: "10", price: "124", date: start)
    put_quote!(nordic, start, "124")
    Map.put(world, :nordic, nordic)
  end

  defp rule!(actor, world, name, version, opts \\ []) do
    {:ok, rule} =
      PolicyRules.create_rule(
        actor,
        %{portfolio_id: world.portfolio.id, name: name, version: version},
        today: Keyword.get(opts, :today, today())
      )

    rule
  end

  defp cash_floor(attrs \\ %{}) do
    Map.merge(
      %{subject_type: "cash", measure: "weight", kind: "floor", threshold: "5", severity: "warn"},
      attrs
    )
  end

  defp row(view, rule),
    do: element(view, "#policy-findings tr[data-rule-id='#{rule.id}'] .policy-rule__words")

  # User story (E25 S7, G30, T-8; pick G12.1 = A, board 12-e25-new-marks):
  # As the operator reading Wealth → Risk,
  # I want a rule whose line the agent drew to say so where I read what the
  # rule is,
  # so that the findings table does not present the agent's line as mine.
  #
  # Acceptance criteria:
  # - A finding whose version in force the agent wrote ends its words line
  #   with "Agent", preceded by the hidden "Version in force by:"; the
  #   operator's own rules carry no word, so a portfolio without agent rules
  #   reads as before.
  # - A scheduled rule whose coming version the agent wrote, and a retired
  #   rule whose last version the agent wrote, carry the same word at the end
  #   of their muted line.
  # - The dialog's version list names the author of every version,
  #   "Operator" or "Agent".
  # - On a German page the word stays "Agent", and the hidden text reads
  #   "Version in Kraft von:".
  test "the agent's rules end their words line with Agent, and every version names its author",
       %{conn: conn} do
    world = world()

    own = rule!(Actor.owner_ui(), world, "Barreserve", cash_floor())
    agents = rule!(Actor.api_token_rw("mcp"), world, "Liquiditätsreserve halten", cash_floor())

    {:ok, _} =
      PolicyRules.add_version(
        Actor.api_token_rw("mcp"),
        own,
        cash_floor(%{threshold: "4", valid_from: Date.add(today(), 3)})
      )

    scheduled =
      rule!(
        Actor.api_token_rw(),
        world,
        "Industrie-Anteil begrenzen",
        cash_floor(%{valid_from: Date.add(today(), 10)})
      )

    retired =
      rule!(
        Actor.api_token_rw(),
        world,
        "Alte Reserve",
        cash_floor(%{valid_from: Date.add(today(), -30)}),
        today: Date.add(today(), -30)
      )

    {:ok, _} = PolicyRules.retire_rule(Actor.owner_ui(), retired, %{})

    {:ok, view, _html} = live(conn, "/risk")

    words = view |> row(agents) |> render()
    assert words =~ ~r/Warning\s*<span[^>]*data-role="policy-rule-author"/
    assert words =~ ~r{<span class="visually-hidden">Version in force by: </span>Agent</span>}
    refute view |> row(own) |> render() =~ "policy-rule-author"

    assert has_element?(
             view,
             "#policy-rules-scheduled li [data-role='policy-rule-author']",
             "Agent"
           )

    assert view |> element("#policy-rules-scheduled li") |> render() =~ scheduled.name

    assert has_element?(
             view,
             "#policy-rules-retired li [data-role='policy-rule-author']",
             "Agent"
           )

    view |> element("#policy-findings button[phx-value-id='#{own.id}']") |> render_click()

    versions =
      view
      |> element("dialog#policy-rule-dialog #policy-rule-versions")
      |> render()

    assert [first, second] = Regex.scan(~r/<li[^>]*>.*?<\/li>/s, versions) |> Enum.map(&hd/1)
    assert first =~ "Version 1" and first =~ "· Operator"
    assert second =~ "Version 2" and second =~ "· Agent"

    conn = Plug.Test.put_req_cookie(conn, "portfolixir_locale", "de")
    {:ok, view, _html} = live(conn, "/risk")

    assert view |> row(agents) |> render() =~
             ~r{<span class="visually-hidden">Version in Kraft von: </span>Agent</span>}
  end
end
