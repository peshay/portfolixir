defmodule PortfolixirWeb.BucketsLiveViewSaveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, add_depot: 2, buy!: 3, create_security!: 1, deposit!: 3, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Journal
  alias Portfolixir.Portfolios.PolicyFindings
  alias Portfolixir.Portfolios.PolicyRules

  defp owner, do: Actor.owner_ui()
  defp unique(name), do: "#{name} #{System.unique_integer([:positive])}"

  defp bucket!(name) do
    {:ok, bucket} = Buckets.create_bucket(owner(), %{name: unique(name)})
    bucket
  end

  defp view_entries(view_id),
    do: Journal.list_entries(resource_type: "view", resource_id: to_string(view_id))

  # Open the row menu of the view, then click the menu item (as in
  # buckets_live_test.exs).
  defp menu_click(view, kind, id, event) do
    view
    |> element(~s(button.row-actions__kebab[phx-value-kind="#{kind}"][phx-value-id="#{id}"]))
    |> render_click()

    view
    |> element(~s([role="menu"] button[phx-click="#{event}"][phx-value-id="#{id}"]))
    |> render_click()
  end

  defp observe(view_id) do
    {:ok, filter} = Buckets.view_filter(view_id)

    %{
      include_all: Buckets.get_view(view_id).include_all,
      include: filter.include,
      exclude: filter.exclude,
      view_journal_entries: length(view_entries(view_id))
    }
  end

  # User story (security review 2026-10-12, H44):
  # As the operator saving a view's bucket picker,
  # I want a save the page refuses to change nothing about the view,
  # so that the message "That bucket no longer exists" is true and the view
  # my rules read keeps the scope it had.
  #
  # Acceptance criteria:
  # - A refused save of an include-all view leaves include_all on, both
  #   bucket sets unchanged and writes no view journal entry.
  test "a refused save of an include-all view leaves include_all on and journals nothing",
       %{conn: conn} do
    core = bucket!("Core")
    {:ok, v} = Buckets.create_view(owner(), %{name: unique("Income")})

    before = observe(v.id)
    assert before == %{include_all: true, include: :all, exclude: [], view_journal_entries: 0}

    {:ok, view, _html} = live(conn, "/buckets")
    menu_click(view, "view", v.id, "edit_view_buckets")
    view |> form("#view-bucket-form", %{"include_all" => "false"}) |> render_change()

    # Another tab, or the agent through the API/MCP, deletes the bucket.
    {:ok, _} = Buckets.delete_bucket(owner(), core)

    html =
      view
      |> form("#view-bucket-form", %{"include_all" => "false", "include" => ["#{core.id}"]})
      |> render_submit()

    # The operator is told the save did not happen ...
    assert html =~ "That bucket no longer exists"

    # ... so nothing about the view may have changed.
    assert observe(v.id) == before
  end

  # User story (security review 2026-10-12, H44):
  # As the operator whose policy rules read a view,
  # I want a refused save of that view's buckets to leave its scope alone,
  # so that a rule in force reads the same finding it read before.
  #
  # Acceptance criteria:
  # - A refused save of a scoped view leaves it scoped, writes no view
  #   journal entry, and the in-force rule's finding does not move.
  test "a refused save does not widen a scoped view or move an in-force rule's finding",
       %{conn: conn} do
    start = Date.add(Portfolixir.Clock.today(), -5)

    world = base_world(name: unique("Scoped"))

    second =
      add_depot(world.portfolio, cash_name: unique("Second Cash"), depot_name: unique("Second"))

    second_world = %{portfolio: world.portfolio, depot: second.depot, cash: second.cash}

    alpha = create_security!(name: "Alpha Synthetic AG", ticker: "ALS")
    beta = create_security!(name: "Beta Synthetic SE", ticker: "BTS")

    deposit!(world, "5000", start)
    deposit!(second_world, "5000", start)
    buy!(world, alpha, quantity: "10", price: "100", date: start)
    buy!(second_world, beta, quantity: "40", price: "100", date: start)
    put_quote!(alpha, start, "100")
    put_quote!(beta, start, "100")

    core = bucket!("Core")
    doomed = bucket!("Doomed")
    :ok = Buckets.set_depot_default_buckets(owner(), world.depot, [core.id])

    # A view scoped to the Core depot only.
    {:ok, v} = Buckets.create_view(owner(), %{name: unique("Core only"), include_all: false})
    :ok = Buckets.set_view_buckets(owner(), v, [core.id], [])

    {:ok, rule} =
      PolicyRules.create_rule(
        owner(),
        %{
          portfolio_id: world.portfolio.id,
          view_id: v.id,
          name: unique("Alpha at most 50 %"),
          version: %{
            subject_type: "security",
            security_id: alpha.id,
            measure: "weight",
            kind: "cap",
            threshold: "50",
            severity: "hard"
          }
        },
        today: Portfolixir.Clock.today()
      )

    finding_state = fn ->
      result = PolicyFindings.for_portfolio(world.portfolio.id, view: v.id)
      f = Enum.find(result.findings, &(&1.rule_id == rule.id))
      {f.state, f.value && Decimal.to_string(Decimal.normalize(f.value))}
    end

    before = Map.put(observe(v.id), :finding, finding_state.())

    # Precondition: inside the Core-only view Alpha is the whole basis, so the
    # hard cap is breached.
    assert before.include_all == false
    assert before.include == [core.id]
    assert before.finding == {:breached, "1E+2"} or before.finding == {:breached, "100"}

    {:ok, view, _html} = live(conn, "/buckets")
    menu_click(view, "view", v.id, "edit_view_buckets")
    view |> form("#view-bucket-form", %{"include_all" => "true"}) |> render_change()

    {:ok, _} = Buckets.delete_bucket(owner(), doomed)

    html =
      view
      |> form("#view-bucket-form", %{"include_all" => "true", "exclude" => ["#{doomed.id}"]})
      |> render_submit()

    assert html =~ "That bucket no longer exists"

    after_refusal = Map.put(observe(v.id), :finding, finding_state.())

    # Secure behaviour: the refused save changed nothing — the view still
    # scopes Core only, no view journal entry was written, and the rule in
    # force reads the same breach it read before.
    assert after_refusal == before
  end
end
