defmodule PortfolixirWeb.PolicyRuleVersionsListTest do
  # Sprint 18 pick H8.1 (#910; board ux-design-2026-10-02/08-dialogs-copy,
  # before/after): the rule dialog's version list numbers each version once,
  # by its label ("Version 2"), which the version note above it and the
  # retire confirmation name. The browser's list marker goes.
  use PortfolixirWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures, only: [base_world: 1, deposit!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Portfolios.PolicyRules

  defp today, do: Portfolixir.Clock.today()

  defp cash_floor(attrs) do
    Map.merge(
      %{subject_type: "cash", measure: "weight", kind: "floor", threshold: "5", severity: "warn"},
      attrs
    )
  end

  # User story (#910; pick H8.1, board 08-dialogs-copy):
  # As the operator reading a rule's versions in its dialog,
  # I want each version numbered once, by the label the version note uses,
  # so that "1. Version 1" does not number the same entry twice.
  #
  # Acceptance criteria:
  # - The version list keeps its label "Version n" on every entry.
  # - The list is marked `role="list"`, so it keeps its list semantics once
  #   its markers are gone (Safari drops them from a list without markers).
  # - app.css takes the markers off `.policy-rule-versions` and its indent:
  #   `list-style: none` and `padding-left: 0`.
  test "the version list numbers each version once, by its label", %{conn: conn} do
    world = base_world(name: "Versionen")
    deposit!(world, "10000", Date.add(today(), -5))

    {:ok, rule} =
      PolicyRules.create_rule(
        Actor.owner_ui(),
        %{portfolio_id: world.portfolio.id, name: "Barreserve", version: cash_floor(%{})},
        today: today()
      )

    {:ok, _} =
      PolicyRules.add_version(
        Actor.owner_ui(),
        rule,
        cash_floor(%{threshold: "4", valid_from: Date.add(today(), 3)})
      )

    {:ok, view, _html} = live(conn, "/risk")
    view |> element("#policy-findings button[phx-value-id='#{rule.id}']") |> render_click()

    assert has_element?(view, "dialog#policy-rule-dialog ol.policy-rule-versions[role='list']")

    entries =
      view
      |> element("dialog#policy-rule-dialog ol.policy-rule-versions")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find("li")
      |> Enum.map(&(&1 |> Floki.text() |> String.trim()))

    assert [first, second] = entries
    assert first =~ ~r/^Version 1 ·/
    assert second =~ ~r/^Version 2 ·/

    css = File.read!("priv/static/app.css")

    assert css =~
             ~r/\.policy-rule-versions\s*\{[^}]*list-style:\s*none;[^}]*padding-left:\s*0;/
  end
end
