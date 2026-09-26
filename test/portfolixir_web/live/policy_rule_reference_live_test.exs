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

  # User story (#871, pick G6-A, board ux-design-2026-09-24/06-view-rule-reach):
  # As the operator whose view delete was refused because rules read the view,
  # I want each rule the refusal names to take me to Wealth → Risk in the view
  # the rule applies in,
  # so that I find the rule where the message says it is — Risk shows only
  # the active view's rules and carries no view switcher.
  #
  # Acceptance criteria:
  # - The refusal band on /buckets names each rule with its status and the
  #   view it applies in (its context, not the view being deleted), and the
  #   rule's name — only the name — is a link.
  # - The link is a plain href to /risk?view=<the context's id>, or
  #   view=total for a portfolio-wide rule, so the view scope takes the
  #   choice on a full navigation; following it shows the rule on Risk.
  # - A rule's name is text, never markup. The band's second sentence stays.
  # - The same links reach the refusal on /classifications and the list in
  #   the securities delete-blocked dialog.
  test "a refusal links each rule to Risk in the view it applies in", %{conn: conn} do
    world = base_world(name: "Refs")
    {:ok, spekulativ} = Buckets.create_view(Actor.owner_ui(), %{name: "Spekulativ"})

    wide =
      rule!(world, "Spielgeld <b>klein</b> halten", %{
        subject_type: "view",
        subject_view_id: spekulativ.id,
        measure: "weight",
        kind: "cap",
        threshold: "5",
        severity: "hard"
      })

    inside =
      rule!(
        world,
        "Spekulativ breit streuen",
        %{
          subject_type: "basis",
          measure: "hhi",
          kind: "cap",
          threshold: "2500",
          severity: "warn"
        },
        view_id: spekulativ.id
      )

    {:ok, buckets, _html} = live(conn, "/buckets")

    buckets
    |> element(
      ~s(button.row-actions__kebab[phx-value-kind="view"][phx-value-id="#{spekulativ.id}"])
    )
    |> render_click()

    buckets
    |> element(~s([role="menu"] button[phx-click="delete_view"][phx-value-id="#{spekulativ.id}"]))
    |> render_click()

    band = buckets |> element(".alert-error") |> render()

    assert has_element?(
             buckets,
             ~s(.alert-error a[href="/risk?view=total"][data-rule-id="#{wide.id}"]),
             "Spielgeld <b>klein</b> halten"
           )

    assert has_element?(
             buckets,
             ~s(.alert-error a[href="/risk?view=#{spekulativ.id}"][data-rule-id="#{inside.id}"]),
             "Spekulativ breit streuen"
           )

    assert band =~ "&lt;b&gt;klein&lt;/b&gt;"
    refute band =~ "<b>klein</b>"
    assert band =~ "(in force, view “Everything”)"
    assert band =~ "(in force, view “Spekulativ”)"
    assert band =~ "retiring it on Wealth → Risk stops its evaluation."
    assert Buckets.get_view(spekulativ.id)

    # Following the link lands on Risk in that view, where the rule is.
    {:ok, risk, _html} = live(conn, "/risk?view=#{spekulativ.id}")
    assert has_element?(risk, "#policy-findings", "Spekulativ breit streuen")

    # The category refusal on /classifications and the securities dialog carry
    # the same links.
    {:ok, tree} = Classifications.create_classification(Actor.owner_ui(), %{name: "Strategie"})

    {:ok, bonds} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: tree.id,
        name: "Anleihen"
      })

    banded =
      rule!(
        world,
        "Anleihen im Band",
        %{
          subject_type: "category",
          classification_id: tree.id,
          category_id: bonds.id,
          measure: "drift",
          kind: "band",
          lower: "-3",
          upper: "3",
          severity: "warn"
        },
        view_id: spekulativ.id
      )

    {:ok, classifications, _html} = live(conn, "/classifications/#{tree.id}")
    render_hook(classifications, "delete_category", %{"id" => to_string(bonds.id)})

    assert has_element?(
             classifications,
             ~s(.alert-error a[href="/risk?view=#{spekulativ.id}"][data-rule-id="#{banded.id}"]),
             "Anleihen im Band"
           )

    security = create_security!(name: "Nordic Timber Holdings AB", ticker: "NTH")

    capped =
      rule!(
        world,
        "Einzeltitel höchstens 10 %",
        %{
          subject_type: "security",
          security_id: security.id,
          measure: "weight",
          kind: "cap",
          threshold: "10",
          severity: "hard"
        },
        view_id: spekulativ.id
      )

    {:ok, securities, _html} = live(conn, "/securities")
    render_hook(securities, "row_action", %{"action" => "delete", "id" => to_string(security.id)})

    assert has_element?(
             securities,
             ~s(#delete-blocked-dialog a[href="/risk?view=#{spekulativ.id}"][data-rule-id="#{capped.id}"]),
             "Einzeltitel höchstens 10 %"
           )

    assert securities |> element("#delete-blocked-dialog") |> render() =~
             "(in force, view “Spekulativ”)"
  end

  # Acceptance criteria (#871, G6-A): on a German page the band reads
  # „name“ (gilt, Ansicht „Alles“), the name still the only link.
  test "the refusal's links read in German on a German page", %{conn: conn} do
    world = base_world(name: "Refs")
    {:ok, spekulativ} = Buckets.create_view(Actor.owner_ui(), %{name: "Spekulativ"})

    wide =
      rule!(world, "Spielgeld klein halten", %{
        subject_type: "view",
        subject_view_id: spekulativ.id,
        measure: "weight",
        kind: "cap",
        threshold: "5",
        severity: "hard"
      })

    conn = Plug.Test.put_req_cookie(conn, "portfolixir_locale", "de")
    {:ok, buckets, _html} = live(conn, "/buckets")
    html = render_hook(buckets, "delete_view", %{"id" => to_string(spekulativ.id)})

    assert html =~ "Wird von eigenen Regeln gelesen: „"
    assert html =~ "“ (gilt, Ansicht „Alles“)"

    assert has_element?(
             buckets,
             ~s(.alert-error a[href="/risk?view=total"][data-rule-id="#{wide.id}"]),
             "Spielgeld klein halten"
           )
  end
end
