defmodule PortfolixirWeb.RiskPolicyRulesLiveTest do
  use PortfolixirWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Journal
  alias Portfolixir.Portfolios.PolicyRules

  defp today, do: Portfolixir.Clock.today()

  # A young portfolio: 10 000 deposited, Nordic 1 240 and Helios 2 000 bought
  # five days ago — every portfolio metric refuses (fewer than 20 returns).
  # Risk basis 3 240 → Nordic ≈ 38.3 %, Helios ≈ 61.7 %; cash ≈ 67.6 % of
  # the allocation basis.
  defp rules_world do
    world = base_world(name: "Regeln")

    nordic =
      create_security!(name: "Nordic Timber Holdings AB", ticker: "NTH", asset_class: "equity")

    helios =
      create_security!(name: "Helios Solar Systems SE", ticker: "HSS", asset_class: "equity")

    start = Date.add(today(), -5)
    deposit!(world, "10000", start)
    buy!(world, nordic, quantity: "10", price: "124", date: start)
    buy!(world, helios, quantity: "20", price: "100", date: start)
    put_quote!(nordic, start, "124")
    put_quote!(helios, start, "100")
    Map.merge(world, %{nordic: nordic, helios: helios})
  end

  defp rule!(world, name, version, opts \\ []) do
    {:ok, rule} =
      PolicyRules.create_rule(
        Actor.owner_ui(),
        %{
          portfolio_id: world.portfolio.id,
          view_id: Keyword.get(opts, :view_id),
          name: name,
          version: version
        },
        today: Keyword.get(opts, :today, today())
      )

    rule
  end

  defp single_cap(world, attrs \\ %{}) do
    Map.merge(
      %{
        subject_type: "security",
        security_id: world.nordic.id,
        measure: "weight",
        kind: "cap",
        threshold: "10",
        severity: "hard"
      },
      attrs
    )
  end

  # User story (FR-43, ADR-0049 §9, pick F1-A, board 01-policy-rules-surface):
  # As the operator,
  # I want my own rules and their findings at the top of Wealth → Risk,
  # so that "am I inside my limits?" is answered where the figures are, and
  # without the API.
  #
  # Acceptance criteria:
  # - An "Own rules" section sits above the portfolio metrics, with a count
  #   per state.
  # - Findings sort breached, undetermined, met; each row shows the rule's
  #   name and its words (measure · subject · kind · severity), the measured
  #   value, the line and the state — a breach with its distance, an
  #   undetermined rule with its reason and, for a refused metric, "n of
  #   required observations".
  # - The lens's Top-N is retitled so its generic thresholds never read as
  #   the operator's rules.
  test "shows the operator's rules above the lens, breached and undetermined first", %{conn: conn} do
    world = rules_world()

    rule!(world, "Barreserve", %{
      subject_type: "cash",
      measure: "weight",
      kind: "floor",
      threshold: "5",
      severity: "warn"
    })

    rule!(world, "Schwankung begrenzen", %{
      subject_type: "basis",
      measure: "volatility",
      window: "90d",
      kind: "cap",
      threshold: "15",
      severity: "warn"
    })

    rule!(world, "Einzeltitel höchstens 10 %", single_cap(world))

    {:ok, view, html} = live(conn, "/risk")

    # Above the metrics.
    {rules_at, _} = :binary.match(html, ~s(id="policy-rules"))
    {metrics_at, _} = :binary.match(html, ~s(id="risk-metrics"))
    assert rules_at < metrics_at

    assert has_element?(view, "#policy-rules [data-role='policy-rules-summary']", "1 breached")

    assert has_element?(
             view,
             "#policy-rules [data-role='policy-rules-summary']",
             "1 undetermined"
           )

    assert has_element?(view, "#policy-rules [data-role='policy-rules-summary']", "1 met")

    states =
      view
      |> element("#policy-findings")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find("tbody tr")
      |> Enum.map(&(Floki.attribute(&1, "data-state") |> hd()))

    assert states == ["breached", "undetermined", "ok"]

    breached = view |> element("#policy-findings tr[data-state='breached']") |> render()
    assert breached =~ "Einzeltitel höchstens 10 %"
    assert breached =~ "Weight · Nordic Timber Holdings AB · Cap · Hard"
    assert breached =~ "38.3 %"
    assert breached =~ "10.0 %"
    assert breached =~ "+28.3 pp"

    undetermined = view |> element("#policy-findings tr[data-state='undetermined']") |> render()
    assert undetermined =~ "Volatility · 90 days"
    assert undetermined =~ "of 20 observations"

    assert has_element?(view, "#risk-top-title", "generic thresholds, not policy rules")
  end

  # Acceptance criteria (ADR-0049 §8, §9):
  # - "New rule" opens a native dialog; saving creates the rule, journaled,
  #   in the context of the active view, and its finding appears at once.
  # - A predicate that does not fit its measure is refused with the field
  #   named, and nothing is written.
  test "creates a rule from the dialog", %{conn: conn} do
    world = rules_world()
    {:ok, view, _html} = live(conn, "/risk")

    view |> element("#policy-rules button", "New rule") |> render_click()
    assert has_element?(view, "dialog#policy-rule-dialog")

    view
    |> form("#policy-rule-form", rule: %{measure: "weight"})
    |> render_change()

    view
    |> form("#policy-rule-form",
      rule: %{
        name: "Helios höchstens 50 %",
        measure: "weight",
        subject: "security:#{world.helios.id}",
        kind: "cap",
        threshold: "50",
        severity: "hard"
      }
    )
    |> render_submit()

    refute has_element?(view, "dialog#policy-rule-dialog")

    assert has_element?(
             view,
             "#policy-findings tr[data-state='breached']",
             "Helios höchstens 50 %"
           )

    assert [%{actor_type: :owner_ui} | _] = Journal.list_entries(resource_type: "policy_rule")

    view |> element("#policy-rules button", "New rule") |> render_click()
    view |> form("#policy-rule-form", rule: %{measure: "hhi"}) |> render_change()

    html =
      view
      |> form("#policy-rule-form",
        rule: %{
          name: "Leer",
          measure: "hhi",
          subject: "basis",
          kind: "cap",
          threshold: "",
          severity: "warn"
        }
      )
      |> render_submit()

    assert html =~ "can&#39;t be blank"
    assert has_element?(view, "dialog#policy-rule-dialog")
    assert length(PolicyRules.list_rules(world.portfolio.id)) == 1
  end

  # Acceptance criteria (ADR-0049 §4, board 01's edit dialog):
  # - Editing states that saving creates a new version and names the version
  #   in force; the version list is reachable from the dialog.
  # - Saving adds the version and the new line is evaluated at once.
  # - Retiring (a confirmed action) removes the rule from the findings; it
  #   stays readable behind the "retired rules" disclosure.
  test "edits by version, retires, and keeps a retired rule readable", %{conn: conn} do
    world = rules_world()

    rule =
      rule!(
        world,
        "Einzeltitel höchstens 10 %",
        single_cap(world, %{valid_from: Date.add(today(), -30)}),
        today: Date.add(today(), -30)
      )

    {:ok, view, _html} = live(conn, "/risk")

    view |> element("#policy-findings button[phx-value-id='#{rule.id}']") |> render_click()
    dialog = view |> element("dialog#policy-rule-dialog") |> render()
    assert dialog =~ "Saving creates version 2"
    assert dialog =~ "Version 1"
    assert dialog =~ "10.0 %"

    view
    |> form("#policy-rule-form", rule: %{threshold: "40"})
    |> render_submit()

    assert has_element?(
             view,
             "#policy-findings tr[data-state='ok']",
             "Einzeltitel höchstens 10 %"
           )

    assert length(PolicyRules.get_rule(rule.id).versions) == 2

    # The version in force started today: retiring it now would end it
    # tonight, and the dialog says so rather than pretending it is gone.
    view |> element("#policy-findings button[phx-value-id='#{rule.id}']") |> render_click()
    assert has_element?(view, "dialog#policy-rule-dialog", "ends tonight")
    view |> element("dialog#policy-rule-dialog button", "Cancel") |> render_click()

    older =
      rule!(
        world,
        "Barreserve",
        %{
          subject_type: "cash",
          measure: "weight",
          kind: "floor",
          threshold: "5",
          severity: "warn",
          valid_from: Date.add(today(), -30)
        },
        today: Date.add(today(), -30)
      )

    {:ok, view, _html} = live(conn, "/risk")
    view |> element("#policy-findings button[phx-value-id='#{older.id}']") |> render_click()
    assert has_element?(view, "dialog#policy-rule-dialog button[data-confirm]", "Retire rule")

    view |> element("dialog#policy-rule-dialog button", "Retire rule") |> render_click()

    refute has_element?(view, "#policy-findings tr", "Barreserve")
    assert has_element?(view, "#policy-rules-retired", "Barreserve")
  end

  # Acceptance criteria (closing act: correctness, edge-case and UAT roles):
  # - A rule created today can be edited at once: the dialog's start date
  #   defaults to the first day the context accepts (tomorrow, since the
  #   version in force began today), and saving creates the version.
  # - Reopened, the dialog starts from the version just planned — its line and
  #   its date — not from the one it replaces, so the edit reads as saved.
  # - A scheduled rule, and the scheduled change of a rule in force, are shown
  #   on the page with their start date; a scheduled rule opens its dialog.
  test "a rule edited on the day it starts, and scheduled rules, are visible", %{conn: conn} do
    world = rules_world()
    rule = rule!(world, "Heute angelegt", single_cap(world, %{threshold: "40"}))
    tomorrow = Date.add(today(), 1)

    {:ok, view, _html} = live(conn, "/risk")
    view |> element("#policy-findings button[phx-value-id='#{rule.id}']") |> render_click()

    assert has_element?(
             view,
             ~s(#policy-rule-form input[name="rule[valid_from]"][value="#{Date.to_iso8601(tomorrow)}"])
           )

    view |> form("#policy-rule-form", rule: %{threshold: "45"}) |> render_submit()
    refute has_element?(view, "dialog#policy-rule-dialog")
    assert length(PolicyRules.get_rule(rule.id).versions) == 2

    # The change is listed beside the rule, with its start.
    assert has_element?(view, "#policy-findings [data-role='policy-rule-next']", "45.0 %")

    view |> element("#policy-findings button[phx-value-id='#{rule.id}']") |> render_click()
    assert has_element?(view, ~s(#policy-rule-form input[name="rule[threshold]"][value="45"]))

    assert has_element?(
             view,
             ~s(#policy-rule-form input[name="rule[valid_from]"][value="#{Date.to_iso8601(tomorrow)}"])
           )

    view |> element("dialog#policy-rule-dialog button", "Cancel") |> render_click()

    # A rule that only starts next week is listed, and opens.
    later =
      rule!(world, "Ab nächster Woche", single_cap(world, %{valid_from: Date.add(today(), 7)}))

    {:ok, view, _html} = live(conn, "/risk")
    assert has_element?(view, "#policy-rules-scheduled", "Ab nächster Woche")

    view
    |> element("#policy-rules-scheduled button[phx-value-id='#{later.id}']")
    |> render_click()

    assert has_element?(view, "dialog#policy-rule-dialog button", "Delete rule")
  end

  # Acceptance criteria (closing act, UAT persona): the dialog's validation
  # speaks the page's language — Ecto's messages and the policy rule's own,
  # with their values filled in.
  test "the dialog's errors are in German on a German page", %{conn: conn} do
    world = rules_world()

    rule =
      rule!(world, "Einzeltitel", single_cap(world, %{valid_from: Date.add(today(), -3)}),
        today: Date.add(today(), -3)
      )

    conn = Plug.Test.put_req_cookie(conn, "portfolixir_locale", "de")
    {:ok, view, _html} = live(conn, "/risk")

    view |> element("#policy-findings button[phx-value-id='#{rule.id}']") |> render_click()

    html =
      view
      |> form("#policy-rule-form", rule: %{threshold: "abc"})
      |> render_submit()

    assert html =~ "ist ungültig"
    refute html =~ "is invalid"

    html =
      view
      |> form("#policy-rule-form",
        rule: %{threshold: "12", valid_from: Date.to_iso8601(Date.add(today(), -3))}
      )
      |> render_submit()

    assert html =~ "muss nach dem #{Date.to_iso8601(Date.add(today(), -3))} liegen" or
             html =~ "darf nicht vor heute liegen"

    refute html =~ "must be after"
  end

  # Acceptance criteria (ADR-0049 §1, §2; the dialog's field set per measure):
  # - The subject control carries every subject the matrix admits — the
  #   basis, a category of a tree, a view — and the extra fields appear with
  #   the measure that needs them: the window for a portfolio metric, the
  #   plan's tree for the drift of a security, From/To for a band.
  # - A band whose From lies above its To is refused on the field, and
  #   nothing is written.
  # - A rule scheduled for a later day has never been in force, so its
  #   dialog offers Delete, not Retire, and deleting removes it.
  test "the dialog carries every subject and measure shape", %{conn: conn} do
    world = rules_world()
    alias Portfolixir.Classifications

    {:ok, tree} = Classifications.create_classification(Actor.owner_ui(), %{name: "Stil"})

    {:ok, growth} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: tree.id,
        name: "Wachstum"
      })

    {:ok, kern} = Buckets.create_view(Actor.owner_ui(), %{name: "Kern"})
    {:ok, view, _html} = live(conn, "/risk")

    submit = fn attrs ->
      view |> element("#policy-rules button", "New rule") |> render_click()

      view |> form("#policy-rule-form", rule: Map.take(attrs, [:measure])) |> render_change()

      view
      |> form("#policy-rule-form", rule: Map.take(attrs, [:measure, :subject, :kind]))
      |> render_change()

      view |> form("#policy-rule-form", rule: attrs) |> render_submit()
    end

    # A metric rule shows the window.
    view |> element("#policy-rules button", "New rule") |> render_click()
    view |> form("#policy-rule-form", rule: %{measure: "volatility"}) |> render_change()
    assert has_element?(view, ~s(#policy-rule-form select[name="rule[window]"]))
    view |> element("dialog#policy-rule-dialog button", "Cancel") |> render_click()

    submit.(%{
      name: "Schwankung 30 Tage",
      measure: "volatility",
      subject: "basis",
      window: "30d",
      kind: "cap",
      threshold: "25",
      severity: "warn"
    })

    # A category drift band.
    submit.(%{
      name: "Wachstum im Band",
      measure: "drift",
      subject: "category:#{tree.id}:#{growth.id}",
      kind: "band",
      lower: "-3",
      upper: "3",
      severity: "warn"
    })

    # The drift of a security asks for the plan's tree.
    view |> element("#policy-rules button", "New rule") |> render_click()

    view
    |> form("#policy-rule-form",
      rule: %{measure: "drift", subject: "security:#{world.helios.id}"}
    )
    |> render_change()

    assert has_element?(view, ~s(#policy-rule-form select[name="rule[classification_id]"]))

    view
    |> form("#policy-rule-form",
      rule: %{
        name: "Helios am Ziel",
        measure: "drift",
        subject: "security:#{world.helios.id}",
        classification_id: tree.id,
        kind: "band",
        lower: "-2",
        upper: "2",
        severity: "hard"
      }
    )
    |> render_submit()

    # A view's weight.
    submit.(%{
      name: "Kern mindestens 20 %",
      measure: "weight",
      subject: "view:#{kern.id}",
      kind: "floor",
      threshold: "20",
      severity: "warn"
    })

    by_name =
      world.portfolio.id
      |> PolicyRules.list_rules(view: :any)
      |> Map.new(&{&1.name, PolicyRules.get_rule(&1.id).versions |> hd()})

    assert %{subject_type: :basis, window: :"30d"} = by_name["Schwankung 30 Tage"]

    assert %{subject_type: :category, category_id: category_id, lower: lower} =
             by_name["Wachstum im Band"]

    assert category_id == growth.id
    assert Decimal.equal?(lower, Decimal.new("-3"))

    assert %{subject_type: :security, classification_id: classification_id} =
             by_name["Helios am Ziel"]

    assert classification_id == tree.id

    assert %{subject_type: :view, subject_view_id: subject_view_id} =
             by_name["Kern mindestens 20 %"]

    assert subject_view_id == kern.id

    # An inverted band is refused on its field.
    html =
      submit.(%{
        name: "Verkehrt",
        measure: "drift",
        subject: "category:#{tree.id}:#{growth.id}",
        kind: "band",
        lower: "5",
        upper: "1",
        severity: "warn"
      })

    assert html =~ "must be at least lower"
    refute Map.has_key?(by_name, "Verkehrt")
    assert length(PolicyRules.list_rules(world.portfolio.id, view: :any)) == 4
    view |> element("dialog#policy-rule-dialog button", "Cancel") |> render_click()

    # A rule that starts tomorrow was never in force: Delete, not Retire.
    scheduled =
      rule!(world, "Ab morgen", single_cap(world, %{valid_from: Date.add(today(), 1)}))

    {:ok, view, _html} = live(conn, "/risk")

    view
    |> element("#policy-rules-scheduled button[phx-value-id='#{scheduled.id}']")
    |> render_click()

    refute has_element?(view, "dialog#policy-rule-dialog button", "Retire rule")
    view |> element("dialog#policy-rule-dialog button", "Delete rule") |> render_click()
    refute PolicyRules.get_rule(scheduled.id)
  end

  # Acceptance criteria (UX-DR26, ADR-0049 §1):
  # - The section is scoped by the active view: a rule of another context is
  #   not shown, and the section says which view it evaluates.
  test "is scoped by the active view", %{conn: conn} do
    world = rules_world()
    {:ok, kern} = Buckets.create_view(Actor.owner_ui(), %{name: "Kern"})

    rule!(world, "Portfolioweit", single_cap(world))
    rule!(world, "Nur im Kern", single_cap(world), view_id: kern.id)

    {:ok, view, _html} = live(conn, "/risk?view=#{kern.id}")

    assert has_element?(view, "#policy-findings", "Nur im Kern")
    refute has_element?(view, "#policy-findings", "Portfolioweit")
  end
end
