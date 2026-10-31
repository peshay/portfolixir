defmodule Portfolixir.ReviewSeedTest do
  # The review seed (priv/demo/finding_surfaces_seed.exs), run as the README
  # runs it, twice, on the test database. Synchronous: it writes names that
  # are unique instance-wide (views, buckets, classifications), which async
  # modules write too. It makes no outbound call: the test configuration
  # keeps logo discovery and the quote and FX sync off, as the seed demands.
  use Portfolixir.DataCase, async: false

  import Ecto.Query
  import ExUnit.CaptureIO

  alias Portfolixir.Catalog.Quote
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Lifecycle
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Income
  alias Portfolixir.Portfolios.Portfolio
  alias Portfolixir.Portfolios.PolicyRule
  alias Portfolixir.Portfolios.PolicyRules
  alias Portfolixir.Tax
  alias Portfolixir.Tax.StatementSnapshot

  @seed "priv/demo/finding_surfaces_seed.exs"

  # User story (#1126):
  # As the reviewer re-running the review seed on a seeded database, after
  # a migration, as its header advises,
  # I want the second run to leave the quotes alone,
  # so that the screenshots and walkthroughs show the figures a fresh
  # database shows.
  #
  # Acceptance criteria:
  # - A second run writes no quote: every security's quotes, date and
  #   close, are those of the first run, also for the securities the
  #   seed's later steps create after its quote step ran.
  # - It adds no security and no booking either, as the README says.
  test "a second run of the review seed leaves the quotes alone" do
    seed!()
    first = quotes()
    rows = row_counts()
    assert first != []

    seed!()
    second = quotes()

    assert row_counts() == rows
    # Written by the second run: none; changed or removed by it: none.
    assert {length(second -- first), length(first -- second)} == {0, 0}
  end

  # User story (#1127, Sprint 20 γ closing act, the correctness hunter):
  # As the reviewer walking the review instance's data-quality surfaces,
  # I want the README and the seed to name the held security that stores no
  # asset class,
  # so that the "Unclassified" surface is looked for where it is.
  #
  # Acceptance criteria:
  # - "Placeholder Anleihe 2031 3,25%", the delivered position with no
  #   price, keeps its name and stores bond (#1127 reads its bond word);
  #   "Ostsee Logistik 4,10% 2028/2033" stores no asset class.
  # - The README names Ostsee Logistik as the held security with no asset
  #   class and no longer says the delivered position has none; the seed's
  #   step 2 says the same.
  test "the README names the held security that stores no asset class" do
    seed!()

    assert stored_class("Placeholder Anleihe 2031 3,25%") == "bond"
    assert stored_class("Ostsee Logistik 4,10% 2028/2033") == nil

    for path <- ["priv/demo/README.md", @seed] do
      text = path |> File.read!() |> String.replace(~r/[\s#]+/, " ")

      assert text =~
               "the held security with no asset class is \"Ostsee Logistik 4,10% 2028/2033\"",
             path

      refute text =~ "a delivered position with no price and no asset class", path
      refute text =~ "no quote at all and no asset class", path
    end
  end

  # User story (Sprint 21 amendment D-12, the review seed):
  # As the reviewer walking the Sprint 21 security fixes on the review
  # instance,
  # I want the seed to carry the shape each fix draws on a page,
  # so that the walkthrough finds every mark and figure without booking it
  # by hand.
  #
  # Acceptance criteria:
  # - H14: a Demo Depot rule the operator created and the agent renamed
  #   carries name_author agent, its version author operator.
  # - K12: a statement the agent recorded carries author agent.
  # - K11: a security merge left ready to try whose two sides both closed
  #   trades states fifo_realized with a close year of both, and a change.
  # - K07: an income booking in USD, to which no rate leads from EUR, is
  #   excluded from the Demo Depot's income and named with its security.
  # - K09: a split of a security held in two portfolios booked one row in
  #   each and scaled both holdings.
  # - A second run adds no rule, statement, portfolio, security or booking
  #   (the first test pins the securities and the bookings).
  test "the review seed carries the Sprint 21 security shapes (D-12)" do
    seed!()
    demo = Enum.find(Portfolios.list_portfolios(), &(&1.name == "Demo Depot"))

    # H14: renamed by the agent, the version still the operator's.
    agent_named =
      demo.id
      |> PolicyRules.list_rules(include_retired: true)
      |> Enum.filter(&(&1.name_author == :agent))

    assert [%PolicyRule{versions: [%{author: :operator}]}] = agent_named,
           "no Demo Depot rule is named by the agent"

    # K12: recorded by the agent.
    assert Enum.any?(Tax.list_snapshots(), &(&1.author == :agent)),
           "no tax statement is recorded by the agent"

    # K11: both sides closed trades, and pooling them restates the result.
    [source, target] =
      for isin <- ["XS0000000165", "XS0000000173"],
          do: Repo.one!(from(s in Security, where: s.isin == ^isin))

    {:ok, preview} = Lifecycle.preview_security_merge(source.id, target.id)
    fifo = preview.outcomes[false].fifo_realized

    assert Enum.any?(fifo.years, &(&1.source && &1.target)),
           "no close year in which both sides closed a trade"

    assert fifo.unchanged == false

    # K07: a USD dividend in the EUR portfolio, excluded and named.
    excluded = Income.for_portfolio(demo.id).excluded

    assert %{currency_code: "USD", securities: ["Harborline Freight Inc"]} =
             Enum.find(excluded.currencies, &(&1.currency_code == "USD")),
           "no USD income booking is excluded from the Demo Depot's income"

    # K09: one split row per portfolio, both holdings scaled.
    fernhill = Repo.one!(from(s in Security, where: s.name == "Fernhill Instruments AG"))

    splits =
      fernhill.id
      |> Ledger.list_transactions_for_security()
      |> Enum.filter(&(&1.type == "split"))

    assert length(splits) == 2
    assert splits |> Enum.map(& &1.portfolio_id) |> Enum.uniq() |> length() == 2

    held =
      fernhill.id
      |> Ledger.holdings_for_security()
      |> Map.new(&{&1.portfolio.id, &1.quantity})

    assert map_size(held) == 2
    assert held |> Map.values() |> Enum.reduce(&Decimal.add/2) |> Decimal.equal?(32)

    rows = row_counts()
    seed!()
    assert row_counts() == rows
  end

  defp stored_class(name) do
    Repo.one!(from(s in Security, where: s.name == ^name, select: s.asset_class))
  end

  defp row_counts,
    do: %{
      securities: Repo.aggregate(Security, :count),
      bookings: Repo.aggregate(Transaction, :count),
      portfolios: Repo.aggregate(Portfolio, :count),
      rules: Repo.aggregate(PolicyRule, :count),
      statements: Repo.aggregate(StatementSnapshot, :count)
    }

  # The seed defines a module; a second run redefines it, as a second
  # `mix run` would in a fresh VM without the warning.
  defp seed! do
    conflicts = Code.get_compiler_option(:ignore_module_conflict)
    Code.put_compiler_option(:ignore_module_conflict, true)

    try do
      capture_io(fn -> Code.eval_file(@seed) end)
    after
      Code.put_compiler_option(:ignore_module_conflict, conflicts)
    end
  end

  defp quotes do
    Repo.all(
      from(q in Quote,
        select: {q.security_id, q.date, q.close},
        order_by: [q.security_id, q.date]
      )
    )
  end
end
