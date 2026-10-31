defmodule Portfolixir.ReviewSeedTest do
  # The review seed (priv/demo/finding_surfaces_seed.exs), run as the README
  # runs it, twice, on the test database. Synchronous: it writes names that
  # are unique instance-wide (views, buckets, classifications), which async
  # modules write too. It makes no outbound call: the test configuration
  # keeps logo discovery and the quote and FX sync off, as the seed demands.
  use Portfolixir.DataCase, async: false

  import Ecto.Query
  import ExUnit.CaptureIO

  alias Portfolixir.Actor
  alias Portfolixir.Catalog.Quote
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Classifications
  alias Portfolixir.Imports
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Lifecycle
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Income
  alias Portfolixir.Portfolios.Performance.Contribution
  alias Portfolixir.Portfolios.PolicyRule
  alias Portfolixir.Portfolios.PolicyRules
  alias Portfolixir.Portfolios.Portfolio
  alias Portfolixir.Portfolios.RealizedGains
  alias Portfolixir.Portfolios.Targets
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
    wexmoor = Repo.one!(from(s in Security, where: s.name == "Wexmoor Instruments AG"))

    splits =
      wexmoor.id
      |> Ledger.list_transactions_for_security()
      |> Enum.filter(&(&1.type == "split"))

    assert length(splits) == 2
    assert splits |> Enum.map(& &1.portfolio_id) |> Enum.uniq() |> length() == 2

    held =
      wexmoor.id
      |> Ledger.holdings_for_security()
      |> Map.new(&{&1.portfolio.id, &1.quantity})

    assert map_size(held) == 2
    assert held |> Map.values() |> Enum.reduce(&Decimal.add/2) |> Decimal.equal?(32)

    rows = row_counts()
    seed!()
    assert row_counts() == rows
  end

  # User story (#928, Sprint 21 α4; plan D-1 round trip 2, D-14):
  # As the UAT persona walking round trip 2, the coupon, on the review
  # instance in the German UI,
  # I want the seed to carry a bond whose coupon was imported with it, and
  # the file and its re-export beside the seed,
  # so that Wealth's contribution table shows the coupon as the bond's
  # income and a second drop of either file books nothing.
  #
  # Acceptance criteria:
  # - The portfolio "Anleihen" holds ADR-0051's I12 history, imported from
  #   priv/demo/pp_json_bond_coupon_demo.json: over 2026-01-01 to
  #   2026-06-30 the bond "Larkspur Rail AG 4,00 % Anleihe 2031" contributes
  #   525.00 with income 400.00, the interest line is 1.10, and the result
  #   526.10.
  # - Dropping the same file again books nothing (every row a hash hit), and
  #   neither does its re-export with the coupon's time moved
  #   (priv/demo/pp_json_bond_coupon_reexport_demo.json; the coupon is found
  #   by its figures, under economics).
  # - A second run of the seed adds nothing.
  test "the review seed carries round trip 2, a bond with a coupon (D-14)" do
    seed!()
    anleihen = Enum.find(Portfolios.list_portfolios(), &(&1.name == "Anleihen"))
    assert anleihen, "no portfolio Anleihen"

    bond =
      Repo.one!(from(s in Security, where: s.name == "Larkspur Rail AG 4,00 % Anleihe 2031"))

    {:ok, contribution} =
      Contribution.for_portfolio(anleihen.id,
        period: {:range, ~D[2026-01-01], ~D[2026-06-30]},
        today: ~D[2026-06-30]
      )

    row = Enum.find(contribution.positions, &(&1.security_id == bond.id))
    assert Decimal.equal?(row.income, Decimal.new("400.00"))
    assert Decimal.equal?(row.contribution, Decimal.new("525.00"))
    assert Decimal.equal?(contribution.remainder.interest, Decimal.new("1.10"))
    assert Decimal.equal?(contribution.totals.result, Decimal.new("526.10"))

    rows = row_counts()

    for {file, layers} <- [
          {"priv/demo/pp_json_bond_coupon_demo.json", %{hash: 4, retired: 0, economics: 0}},
          {"priv/demo/pp_json_bond_coupon_reexport_demo.json",
           %{hash: 3, retired: 0, economics: 1}}
        ] do
      {:ok, preview} =
        Imports.parse_portfolio_performance(File.read!(file), filename: Path.basename(file))

      assert {:ok, result} = Imports.apply(preview, %{portfolio_id: anleihen.id})
      assert result.created_transactions == 0, file
      assert result.already_imported == layers, file
    end

    seed!()
    assert row_counts() == rows
  end

  # User story (#1198, Sprint 21 α3; the plan's D-14 and D-1 round trip 1):
  # As the UAT persona and the design critic walking α's closing act,
  # I want the review seed to carry a dollar security imported from a EUR
  # account and sold by hand, and one whose lot has no leg in its sale's
  # currency,
  # so that round trip 1 and board 09's unavailable trade are on the
  # instance without a hand-made fixture.
  #
  # Acceptance criteria:
  # - "Kestrel Bay Resources Inc." (CAD, because the seed never stores a USD
  #   rate) reads one closed trade of 188.75 CAD and 151.00 EUR on the
  #   realized-gains read, the 957.00 − 806.00 its two bookings moved.
  # - "Arbolia Inc." (USD, imported with no rate, so no legs) reads one
  #   closed trade unavailable, missing_settlement_leg, named in excluded.
  # - A second run adds no security, booking or portfolio.
  test "the seed carries round trip 1 and an unavailable trade" do
    seed!()

    kestrel = Repo.one!(from(s in Security, where: s.name == "Kestrel Bay Resources Inc."))
    arbolia = Repo.one!(from(s in Security, where: s.name == "Arbolia Inc."))

    assert [trade] = Ledger.list_trades_for_security(kestrel.id).closed_trades
    assert trade.currency_code == "CAD"
    assert Decimal.equal?(trade.realized_pnl_abs, Decimal.new("188.75"))

    report = RealizedGains.report(base_currency: "EUR")
    row = Enum.find(report.trades, &(&1.security_id == kestrel.id))
    assert Decimal.equal?(row.realized_base, Decimal.new("151.00"))

    assert [unavailable] = Ledger.list_trades_for_security(arbolia.id).closed_trades
    assert unavailable.unavailable_reason == :missing_settlement_leg
    assert "Arbolia Inc." in report.excluded.by_reason.missing_settlement_leg.securities

    rows = row_counts()
    seed!()
    assert row_counts() == rows
  end

  # User story (#1188, Sprint 21 α5; the plan's D-14 and round trip 4):
  # As the reviewer walking the α round trips on the review instance,
  # I want the seed to name a Portfolio Performance file with a delivery
  # that carries a negative tax,
  # so that I can drop it and see the delivery named as not imported while
  # the rest books, without writing the file by hand.
  #
  # Acceptance criteria:
  # - The seed's header and the README name
  #   priv/demo/pp_json_delivery_negative_tax_demo.json.
  # - The file previews with one row error, the delivery's, naming its
  #   remedy; the deposit and the purchase preview.
  # - Applied, "Girokonto Lieferung" reads 499.00 and "Depot Lieferung"
  #   holds 5 "Arbolia Inc.".
  # - The seed does not import it, so a second run adds nothing for it (the
  #   first test pins the bookings across two runs).
  test "the seed names a delivery with a negative tax that previews with one row error" do
    file = "priv/demo/pp_json_delivery_negative_tax_demo.json"

    for path <- ["priv/demo/README.md", @seed] do
      assert File.read!(path) =~ Path.basename(file), path
    end

    {:ok, preview} = Imports.parse_portfolio_performance(File.read!(file), filename: file)

    assert [%{row: 2, message: "inbound delivery with a tax refund of 0.40: " <> _}] =
             preview.errors

    assert Enum.map(preview.entries, & &1.kind) == ["deposit", "buy"]

    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Round trip 4",
        base_currency_code: "EUR"
      })

    assert {:ok, _result} = Imports.apply(preview, %{portfolio_id: portfolio.id})

    %{id: giro} =
      portfolio.id
      |> Portfolios.list_cash_accounts_for_portfolio()
      |> Enum.find(&(&1.name == "Girokonto Lieferung"))

    balance = [portfolio_id: portfolio.id] |> Ledger.cash_balances() |> Map.fetch!(giro)
    assert Decimal.equal?(balance, Decimal.new("499.00"))

    assert [%{security_name: "Arbolia Inc.", quantity: quantity}] =
             Ledger.holdings_for_portfolio(portfolio.id)

    assert Decimal.equal?(quantity, 5)
  end

  # User story (#1185, Sprint 21 β2; plan D-14):
  # As the reviewer walking an agent's plan reads on the review instance,
  # I want the seed to carry an archived plan version beside the active one,
  # so that the walkthrough reads it back, sees the reads refuse it by
  # plan_id as the writes do, and finds it in the SOLL editor's versions.
  #
  # Acceptance criteria:
  # - The Demo Depot's Gesamt plan of the Strategies tree has exactly one
  #   archived version beside its active one, and its targets differ from
  #   the active plan's.
  # - A second run adds no plan version and keeps the active plan.
  test "the review seed carries an archived plan version (D-14)" do
    seed!()
    demo = Enum.find(Portfolios.list_portfolios(), &(&1.name == "Demo Depot"))
    strategies = Enum.find(Classifications.list_classifications(), &(&1.name == "Strategies"))
    plans = fn -> Targets.list_plans(demo.id, classification_id: strategies.id, view: nil) end
    weights = fn plan -> plan.id |> plan_rows(demo.id) end

    first = plans.()
    assert [active] = Enum.filter(first, &(&1.status == "active"))
    assert [archived] = Enum.filter(first, &(&1.status == "archived"))
    assert weights.(archived) != [] and weights.(archived) != weights.(active)

    seed!()
    assert Enum.map(plans.(), &{&1.id, &1.status}) == Enum.map(first, &{&1.id, &1.status})
  end

  defp plan_rows(plan_id, portfolio_id) do
    portfolio_id
    |> Targets.list_targets(plan: plan_id)
    |> Enum.concat(Targets.list_position_targets(portfolio_id, plan: plan_id))
    |> Enum.map(&{&1.category_id, &1.security_id, Decimal.to_string(&1.target_weight)})
    |> Enum.sort()
  end

  # User story (#1195, Sprint 21 α8; plan D-14):
  # As the reviewer walking the import preview's rename probe,
  # I want the review seed to hold twin account names, imported history
  # under one of them,
  # so that a drop naming the other twin shows the row the probe withholds.
  #
  # Acceptance criteria:
  # - The Demo Depot holds "Rücklage" and "RÜCKLAGE", two cash accounts
  #   whose names differ only in letter case; "Rücklage" and "Rücklage
  #   Giro" carry the imported bookings (an import hash each), "RÜCKLAGE"
  #   none.
  # - A second run adds no account and no booking.
  test "the review seed holds twin account names" do
    seed!()

    twins =
      Portfolios.list_cash_accounts()
      |> Enum.filter(&(&1.name in ["Rücklage", "RÜCKLAGE", "Rücklage Giro"]))
      |> Map.new(&{&1.name, &1})

    assert Map.keys(twins) |> Enum.sort() == ["RÜCKLAGE", "Rücklage", "Rücklage Giro"]
    assert twins["Rücklage"].portfolio_id == twins["RÜCKLAGE"].portfolio_id

    imported = fn account ->
      Repo.aggregate(
        from(t in Transaction,
          where:
            (t.cash_account_id == ^account.id or t.counter_cash_account_id == ^account.id) and
              not is_nil(t.import_hash)
        ),
        :count
      )
    end

    assert {imported.(twins["Rücklage"]), imported.(twins["Rücklage Giro"]),
            imported.(twins["RÜCKLAGE"])} == {2, 2, 0}

    rows = Map.put(row_counts(), :cash_accounts, length(Portfolios.list_cash_accounts()))
    seed!()
    assert Map.put(row_counts(), :cash_accounts, length(Portfolios.list_cash_accounts())) == rows
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
