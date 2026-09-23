defmodule Portfolixir.Portfolios.PolicyFindingsMemoTest do
  # The derived layer is off in config/test.exs, so every other findings test
  # reads through `compute` and none of them exercises the memo's key. This
  # file switches it on, as production runs it (the closing act's correctness
  # and edge-case hunters found the gap).
  use Portfolixir.DataCase, async: false

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Derived.Memo
  alias Portfolixir.DerivedConfig
  alias Portfolixir.Portfolios.PolicyFindings
  alias Portfolixir.Portfolios.PolicyRules

  defp today, do: Portfolixir.Clock.today()

  setup do
    Memo.reset()
    DerivedConfig.enable!()

    world = base_world(name: "Memo")
    alpha = create_security!(name: "Alpha Timber AB", ticker: "ALP")
    beta = create_security!(name: "Beta Solar SE", ticker: "BET")
    start = Date.add(today(), -5)

    deposit!(world, "10000", start)
    buy!(world, alpha, quantity: "10", price: "100", date: start)
    buy!(world, beta, quantity: "40", price: "100", date: start)
    put_quote!(alpha, start, "100")
    put_quote!(beta, start, "100")

    {:ok, only_alpha} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Only Alpha"})
    :ok = Buckets.set_position_override(Actor.owner_ui(), world.depot, alpha, [only_alpha.id])

    %{world: world, only_alpha: only_alpha}
  end

  # User story (ADR-0049 §5, ADR-0039):
  # As the operator's agent reading the findings on a schedule,
  # I want a changed view definition to change the findings read,
  # so that a memoised answer never says "ok" for a rule the new definition
  # breaches.
  #
  # Acceptance criteria:
  # - With the derived layer on, narrowing a view (include_all off, its
  #   buckets set) is visible on the next findings read — for a rule whose
  #   subject is the view and for a rule whose context is the view.
  test "a view's changed definition is read at once, never from the memo",
       %{world: world, only_alpha: only_alpha} do
    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Subject"})

    {:ok, subject_rule} =
      PolicyRules.create_rule(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        name: "The view at most 50 %",
        version: %{
          subject_type: "view",
          subject_view_id: view.id,
          measure: "weight",
          kind: "cap",
          threshold: "50",
          severity: "hard"
        }
      })

    before = PolicyFindings.for_portfolio(world.portfolio.id)
    assert %{state: :breached} = Enum.find(before.findings, &(&1.rule_id == subject_rule.id))

    {:ok, view} = Buckets.update_view(Actor.owner_ui(), view, %{include_all: false})
    :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, [only_alpha.id], [])

    after_edit = PolicyFindings.for_portfolio(world.portfolio.id)

    assert %{state: :ok, value: value} =
             Enum.find(after_edit.findings, &(&1.rule_id == subject_rule.id))

    assert Decimal.equal?(value, Decimal.new("20"))

    # The view as a context: Alpha is 20 % of the whole, 100 % of the view.
    {:ok, context_rule} =
      PolicyRules.create_rule(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        view_id: view.id,
        name: "Nothing above 50 % in the view",
        version: %{
          subject_type: "basis",
          measure: "hhi",
          kind: "cap",
          threshold: "9000",
          severity: "warn"
        }
      })

    in_view = PolicyFindings.for_portfolio(world.portfolio.id, view: view.id)
    assert %{state: :breached} = Enum.find(in_view.findings, &(&1.rule_id == context_rule.id))

    :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, [], [])
    {:ok, _view} = Buckets.update_view(Actor.owner_ui(), view, %{include_all: true})

    widened = PolicyFindings.for_portfolio(world.portfolio.id, view: view.id)
    assert %{state: :ok} = Enum.find(widened.findings, &(&1.rule_id == context_rule.id))
  end
end
