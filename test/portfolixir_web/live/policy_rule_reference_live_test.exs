defmodule PortfolixirWeb.PolicyRuleReferenceLiveTest do
  use PortfolixirWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias Portfolixir.Portfolios.PolicyRules

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

  # User story (ADR-0049 §8, board 06-rule-reference-409):
  # As the operator deleting a security from the catalog,
  # I want the refusal to name the rule that reads it,
  # so that the dialog does not claim a booking or a quote that is not there.
  #
  # Acceptance criteria:
  # - The delete-blocked dialog names each rule with its status and says a
  #   rule that has been in force keeps its subject; "Retire instead" stays.
  # - The security is not deleted.
  test "the securities delete-blocked dialog names the rules", %{conn: conn} do
    world = base_world(name: "Refs")
    security = create_security!(name: "Nordic Timber Holdings AB", ticker: "NTH")

    rule!(world, "Einzeltitel höchstens 10 %", %{
      subject_type: "security",
      security_id: security.id,
      measure: "weight",
      kind: "cap",
      threshold: "10",
      severity: "hard"
    })

    {:ok, view, _html} = live(conn, "/securities")

    render_hook(view, "row_action", %{"action" => "delete", "id" => to_string(security.id)})

    dialog = view |> element("#delete-blocked-dialog") |> render()
    assert dialog =~ "Einzeltitel höchstens 10 %"
    assert dialog =~ "keeps its subject"
    assert dialog =~ "Retire instead"
    refute dialog =~ "existing transactions or quote history"
    assert Catalog.get_security(security.id)
  end

  # Acceptance criteria (ADR-0049 §8, board 06):
  # - Deleting a category or a classification a rule reads shows the page's
  #   error message naming the rules, and nothing is deleted.
  # - Deleting a view a rule reads (as context or as subject) does the same
  #   on /buckets, where it used to fail with no message at all.
  test "category, classification and view deletes name the rules", %{conn: conn} do
    world = base_world(name: "Refs")

    {:ok, tree} = Classifications.create_classification(Actor.owner_ui(), %{name: "Strategie"})

    {:ok, bonds} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: tree.id,
        name: "Anleihen"
      })

    rule!(world, "Anleihen im Band", %{
      subject_type: "category",
      classification_id: tree.id,
      category_id: bonds.id,
      measure: "drift",
      kind: "band",
      lower: "-3",
      upper: "3",
      severity: "warn"
    })

    {:ok, view, _html} = live(conn, "/classifications/#{tree.id}")

    html = render_hook(view, "delete_category", %{"id" => to_string(bonds.id)})
    assert html =~ "Anleihen im Band"
    assert Classifications.get_category(bonds.id)

    html = render_hook(view, "delete_classification", %{})
    assert html =~ "Anleihen im Band"
    assert Classifications.get_classification(tree.id)

    {:ok, spekulativ} = Buckets.create_view(Actor.owner_ui(), %{name: "Spekulativ"})

    rule!(world, "Spielgeld klein halten", %{
      subject_type: "view",
      subject_view_id: spekulativ.id,
      measure: "weight",
      kind: "cap",
      threshold: "5",
      severity: "hard"
    })

    {:ok, buckets, _html} = live(conn, "/buckets")

    buckets
    |> element(
      ~s(button.row-actions__kebab[phx-value-kind="view"][phx-value-id="#{spekulativ.id}"])
    )
    |> render_click()

    html =
      buckets
      |> element(
        ~s([role="menu"] button[phx-click="delete_view"][phx-value-id="#{spekulativ.id}"])
      )
      |> render_click()

    assert html =~ "Spielgeld klein halten"
    assert Buckets.get_view(spekulativ.id)
  end
end
