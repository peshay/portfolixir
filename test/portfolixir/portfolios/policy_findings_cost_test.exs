defmodule Portfolixir.Portfolios.PolicyFindingsCostTest do
  # E25 S4, F74 (#889): the findings read valued the evaluation context again
  # for every rule subject that needed it, so its cost grew with the number
  # of subjects times two; and the rule list filtered and cut in memory after
  # loading every rule of the portfolio. The context is now valued once and
  # every total and membership is derived from it, and the rule list filters
  # and limits in the query.
  use Portfolixir.DataCase, async: false

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Classifications
  alias Portfolixir.Portfolios.PolicyFindings
  alias Portfolixir.Portfolios.PolicyRules
  alias Portfolixir.Portfolios.Valuation

  @subjects 4

  defp today, do: Portfolixir.Clock.today()

  setup do
    world = base_world(name: "Findings Cost")
    alpha = create_security!(name: "Alpha Timber AB", ticker: "ALP")
    beta = create_security!(name: "Beta Solar SE", ticker: "BET")
    start = Date.add(today(), -5)

    deposit!(world, "10000", start)
    buy!(world, alpha, quantity: "10", price: "100", date: start)
    buy!(world, beta, quantity: "40", price: "100", date: start)
    put_quote!(alpha, start, "100")
    put_quote!(beta, start, "100")

    %{world: world, alpha: alpha, beta: beta}
  end

  defp rule!(world, name, version, opts) do
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

  defp view_of(name, include) do
    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: name, include_all: false})
    :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, include, [])
    view
  end

  # Counts the portfolio valuations `fun` runs in this process, collected by
  # a separate tracer process (a process's own call trace does not reach it).
  defp valuations(fun) do
    mfa = {Valuation, :for_portfolio, 2}
    Code.ensure_loaded!(Valuation)
    collector = spawn_link(fn -> collect(0) end)
    :erlang.trace_pattern(mfa, true, [:global])
    :erlang.trace(self(), true, [:call, {:tracer, collector}])

    try do
      fun.()
    after
      :erlang.trace(self(), false, [:call])
      :erlang.trace_pattern(mfa, false, [:global])
    end

    send(collector, {:count, self()})

    receive do
      {:valuations, count} -> count
    after
      5_000 -> flunk("the tracer did not answer")
    end
  end

  defp collect(count) do
    receive do
      {:trace, _pid, :call, {Valuation, :for_portfolio, _args}} -> collect(count + 1)
      {:count, from} -> send(from, {:valuations, count})
    end
  end

  # User story:
  # As the operator whose agent reads the findings on a schedule,
  # I want the read's cost to grow by one valuation per rule subject that
  # needs its own, not by two,
  # so that many rules cost what they must and nothing more.
  #
  # Acceptance criteria:
  # - With security, category and view-weight rules in one view context, the
  #   read runs one valuation of the context plus one per subject view.
  # - The findings keep their values.
  test "findings over many subjects run one context valuation plus one per subject",
       %{world: world, alpha: alpha, beta: beta} do
    {:ok, a} = Buckets.create_bucket(Actor.owner_ui(), %{name: "A"})
    {:ok, b} = Buckets.create_bucket(Actor.owner_ui(), %{name: "B"})
    :ok = Buckets.set_position_override(Actor.owner_ui(), world.depot, alpha, [a.id])
    :ok = Buckets.set_position_override(Actor.owner_ui(), world.depot, beta, [b.id])

    context = view_of("Both", [a.id, b.id])

    {:ok, tree} = Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    {:ok, growth} =
      Classifications.create_category(Actor.owner_ui(), %{classification_id: tree.id, name: "G"})

    {:ok, _} = Classifications.assign_security(Actor.owner_ui(), alpha.id, tree.id, growth.id)

    rule!(
      world,
      "Alpha at most 30",
      %{
        subject_type: "security",
        security_id: alpha.id,
        measure: "weight",
        kind: "cap",
        threshold: "30",
        severity: "hard"
      },
      view_id: context.id
    )

    rule!(
      world,
      "Growth at most 30",
      %{
        subject_type: "category",
        classification_id: tree.id,
        category_id: growth.id,
        measure: "weight",
        kind: "cap",
        threshold: "30",
        severity: "hard"
      },
      view_id: context.id
    )

    subjects =
      for n <- 1..@subjects do
        subject = view_of("Subject #{n}", if(rem(n, 2) == 0, do: [a.id], else: [b.id]))

        rule!(
          world,
          "Subject #{n} at most 50",
          %{
            subject_type: "view",
            subject_view_id: subject.id,
            measure: "weight",
            kind: "cap",
            threshold: "50",
            severity: "hard"
          },
          view_id: context.id
        )
      end

    count =
      valuations(fn ->
        result = PolicyFindings.for_portfolio(world.portfolio.id, view: context.id)
        send(self(), {:result, result})
      end)

    assert_received {:result, result}
    assert count == 1 + @subjects

    values = Map.new(result.findings, &{&1.rule_id, &1.value})

    for {rule, n} <- Enum.with_index(subjects, 1) do
      expected = if rem(n, 2) == 0, do: "20", else: "80"
      assert Decimal.equal?(values[rule.id], Decimal.new(expected))
    end
  end

  # User story:
  # As the agent listing a portfolio's rules with a limit,
  # I want the limit and the retired filter applied by the database,
  # so that a long rule history is not loaded to answer a short list.
  #
  # Acceptance criteria:
  # - list_rules with limit: n loads at most n rules, retired ones excluded,
  #   and answers the oldest n rules that are not retired.
  test "list_rules filters retired rules and limits in the query", %{world: world, alpha: alpha} do
    version = fn threshold ->
      %{
        subject_type: "security",
        security_id: alpha.id,
        measure: "weight",
        kind: "cap",
        threshold: threshold,
        severity: "warn",
        valid_from: Date.add(today(), -3)
      }
    end

    rules =
      for n <- 1..5,
          do: rule!(world, "Rule #{n}", version.("#{n}0"), today: Date.add(today(), -3))

    for rule <- Enum.take(rules, 3) do
      {:ok, _} = PolicyRules.retire_rule(Actor.owner_ui(), rule, %{})
    end

    handler = "list-rules-rows-#{System.unique_integer([:positive])}"
    test_pid = self()

    :telemetry.attach(
      handler,
      [:portfolixir, :repo, :query],
      fn _event, _measurements, metadata, _config ->
        case metadata do
          %{source: "policy_rules", result: {:ok, result}} ->
            send(test_pid, {:rule_rows, result.num_rows})

          _other ->
            :ok
        end
      end,
      nil
    )

    try do
      assert [listed] = PolicyRules.list_rules(world.portfolio.id, limit: 1)
      assert listed.id == Enum.at(rules, 3).id
    after
      :telemetry.detach(handler)
    end

    assert_received {:rule_rows, rows}
    assert rows <= 1
  end
end
