defmodule Portfolixir.Portfolios.PortfolioCashTargetWriteTest do
  # E25 S6 (#891), G18: the deprecated portfolio update wrote the cash
  # target through to the Gesamt cash plan after its own transaction had
  # committed, from the virtual field of the row it had read, whether the
  # request carried a cash target or not, and matched the result. A rename
  # could therefore rewrite, or clear, a cash target another writer had just
  # set, and a failed write-through raised after the rename had committed.
  # The cash target is now written only when the request carries it, as a
  # step of the portfolio's own transaction, and a failure rolls the whole
  # write back.
  #
  # async: false — one test swaps a CHECK constraint on
  # portfolio_target_plans, which every concurrent plan test would wait on.
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Targets

  @check "portfolio_target_plans_cash_target_weight_scale_check"

  defp owner, do: Actor.owner_ui()

  defp plan_entries, do: Journal.list_entries(resource_type: "target_plan")

  setup do
    {:ok, portfolio} =
      Portfolios.create_portfolio(owner(), %{
        name: "Cash Target World",
        base_currency_code: "EUR",
        cash_target_weight: "0.1"
      })

    %{portfolio: Portfolios.get_portfolio(portfolio.id)}
  end

  # User story:
  # As the agent renaming a portfolio over the deprecated update while the
  # operator steers its cash quote,
  # I want a rename that says nothing about the cash target to leave it
  # alone,
  # so that my rename never rewrites or clears a cash target set meanwhile.
  #
  # Acceptance criteria:
  # - A rename without cash_target_weight leaves the stored cash target and
  #   the plan's journal untouched, even when the portfolio it was given
  #   carries a stale cash target.
  test "a rename without a cash target leaves the target and its journal untouched",
       %{portfolio: portfolio} do
    # Another writer changes the cash target after this caller's read.
    :ok = Targets.set_cash_target(owner(), portfolio.id, Decimal.new("0.2"))
    before = plan_entries()

    assert {:ok, renamed} = Portfolios.update_portfolio(owner(), portfolio, %{name: "Renamed"})
    assert renamed.name == "Renamed"

    assert Decimal.equal?(Targets.get_cash_target(portfolio.id), Decimal.new("0.2"))
    assert plan_entries() == before
  end

  # Acceptance criteria:
  # - A write that carries cash_target_weight stores it with the rename.
  # - When the cash-target write fails, the rename is rolled back and the
  #   caller gets the error, not a crash.
  test "a carried cash target is written with the rename, and its failure rolls both back",
       %{portfolio: portfolio} do
    assert {:ok, updated} =
             Portfolios.update_portfolio(owner(), portfolio, %{
               name: "Steered",
               cash_target_weight: "0.3"
             })

    assert Decimal.equal?(updated.cash_target_weight, Decimal.new("0.3"))
    assert Decimal.equal?(Targets.get_cash_target(portfolio.id), Decimal.new("0.3"))

    # A plan write the database refuses although the portfolio's own
    # changeset accepts it: the constraint the plan changeset maps is made
    # stricter for this test only (rolled back with the sandbox).
    Repo.query!("ALTER TABLE portfolio_target_plans DROP CONSTRAINT #{@check}")

    Repo.query!(
      "ALTER TABLE portfolio_target_plans ADD CONSTRAINT #{@check} " <>
        "CHECK (cash_target_weight IS NULL OR cash_target_weight < 0.5)"
    )

    stored = Portfolios.get_portfolio(portfolio.id)

    assert {:error, %Ecto.Changeset{} = changeset} =
             Portfolios.update_portfolio(owner(), stored, %{
               name: "Rolled back",
               cash_target_weight: "0.6"
             })

    assert errors_on(changeset)[:cash_target_weight]
    assert Portfolios.get_portfolio(portfolio.id).name == "Steered"
    assert Decimal.equal?(Targets.get_cash_target(portfolio.id), Decimal.new("0.3"))
  end

  # User story (E25 S6 review round, G18):
  # As the agent setting a portfolio's first cash target over the deprecated
  # update while the operator saves the portfolio's first plan,
  # I want the two writes to take turns creating the plan,
  # so that neither fails because the other created it first — a failure the
  # portfolio write's own transaction could not retry.
  #
  # Acceptance criteria:
  # - A write that creates a portfolio's active plan holds the portfolio row
  #   before it checks whether the plan exists, so concurrent first writers
  #   serialise and the later one finds the earlier one's plan.
  # - Activating a plan holds the portfolio row before it reads the scope's
  #   active plan.
  test "a first plan write and a plan activation hold the portfolio before they read the active plan" do
    {:ok, portfolio} =
      Portfolios.create_portfolio(owner(), %{name: "First Plan World", base_currency_code: "EUR"})

    # The portfolio write holds its row from its first step (the journal's
    # lock); the targets writer, over its own route, must hold it too, or the
    # two do not take turns.
    first_target =
      capture_queries(fn ->
        assert :ok = Targets.set_cash_target(owner(), portfolio.id, Decimal.new("0.2"))
      end)

    assert_portfolio_held_before_plan_check(first_target, "the first targets write")

    {:ok, second} =
      Portfolios.create_portfolio(owner(), %{name: "Second Plan World", base_currency_code: "EUR"})

    first_portfolio_write =
      capture_queries(fn ->
        assert {:ok, _} =
                 Portfolios.update_portfolio(owner(), second, %{cash_target_weight: "0.2"})
      end)

    assert_portfolio_held_before_plan_check(first_portfolio_write, "the first portfolio write")

    {:ok, active} = Targets.ensure_plan(owner(), portfolio.id, classification!().id)
    {:ok, draft} = Targets.duplicate_plan(owner(), active)

    activate = capture_queries(fn -> assert {:ok, _} = Targets.activate_plan(owner(), draft) end)
    assert_portfolio_held_before_plan_check(activate, "the activation")
  end

  defp classification! do
    {:ok, classification} =
      Portfolixir.Classifications.create_classification(owner(), %{
        name: "Plan Lock #{System.unique_integer([:positive])}"
      })

    classification
  end

  # The read that decides the write — the last read of the scope's active
  # plan before the plan row is inserted or updated — comes after the
  # portfolio is held. (A write may read the plan earlier, unlocked, to find
  # its fast path; that read decides nothing.)
  defp assert_portfolio_held_before_plan_check(queries, writer) do
    lock = Enum.find_index(queries, &(&1 =~ ~r/FROM "portfolios".*FOR (NO KEY )?UPDATE/s))
    write = Enum.find_index(queries, &(&1 =~ ~r/^(INSERT INTO|UPDATE) "portfolio_target_plans"/))

    check =
      queries
      |> Enum.with_index()
      |> Enum.filter(fn {query, index} ->
        index < (write || 0) and query =~ ~r/FROM "portfolio_target_plans".*"status" = 'active'/s
      end)
      |> List.last()

    assert lock, "#{writer} does not hold the portfolio"
    assert write, "#{writer} writes no plan row"
    assert check, "#{writer} reads no active plan before it writes"

    assert lock < elem(check, 1),
           "#{writer} decides on the active plan before it holds the portfolio"
  end

  defp capture_queries(fun) do
    test_pid = self()
    handler = "plan-create-lock-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler,
        [:portfolixir, :repo, :query],
        fn _event, _measurements, %{query: query}, _config ->
          if self() == test_pid, do: send(test_pid, {:query, query})
        end,
        nil
      )

    try do
      fun.()
    after
      :telemetry.detach(handler)
    end

    collect_queries([])
  end

  defp collect_queries(acc) do
    receive do
      {:query, query} -> collect_queries([query | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
