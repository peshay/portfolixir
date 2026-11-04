defmodule Portfolixir.Portfolios.Performance.BenchmarkCostsTest do
  # Sprint 24 Lane B, B1 (ADR-0046, amended 2026-11-04; idea I17): every
  # benchmark comparison carries costs_paid, the fees and taxes the real
  # portfolio booked in the comparison's own window and scope, by the cost
  # facet's series rule. Risk tier (ADR-0036): the amendment's four
  # identities come first, each with exact Decimals worked out by hand in
  # the comments, and each money identity again at a moving FX rate (the
  # Sprint 24 plan's D-9).
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures,
    only: [add_depot: 2, base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios.Costs
  alias Portfolixir.Portfolios.Performance.Benchmark

  @today ~D[2026-03-31]
  # February 2026: the window every identity below reads.
  @window {:range, ~D[2026-02-01], ~D[2026-02-28]}

  defp d(value), do: Decimal.new(value)

  defp standalone!(world, cash, type, amount, date) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: cash.id,
        type: type,
        date: date,
        gross_amount: amount,
        currency_code: cash.currency_code
      })

    tx
  end

  defp usd_rate!(date, rate) do
    {:ok, 1} =
      Fx.upsert_many([
        %{base_currency: "EUR", quote_currency: "USD", date: date, rate: rate, source: "manual"}
      ])
  end

  # A EUR portfolio with 2000 deposited on 2026-01-02 and a quoted ETF, so the
  # walk covers the whole window.
  defp world!(name) do
    world = base_world(name: name, cash_name: "#{name} Cash", depot_name: "#{name} Depot")
    ticker = name |> String.replace(~r/[^A-Za-z]/, "") |> String.upcase() |> String.slice(0, 6)
    security = create_security!(name: "#{name} ETF", ticker: ticker)
    put_quotes!(security, [{~D[2026-01-02], "100"}, {~D[2026-03-01], "110"}])
    deposit!(world, "2000", ~D[2026-01-02])
    {world, security}
  end

  defp portfolio_costs(world, period \\ @window, benchmark \\ {:rate, Decimal.new("0")}) do
    {:ok, cmp} =
      Benchmark.for_portfolio(world.portfolio.id, benchmark, period: period, today: @today)

    cmp.costs_paid
  end

  defp view_including!(bucket_ids, name) do
    {:ok, view} =
      Buckets.create_view(Actor.owner_ui(), %{
        name: "#{name} #{System.unique_integer([:positive])}",
        include_all: false
      })

    :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, bucket_ids, [])
    view
  end

  defp bucket!(name) do
    {:ok, bucket} =
      Buckets.create_bucket(Actor.owner_ui(), %{
        name: "#{name} #{System.unique_integer([:positive])}"
      })

    bucket
  end

  # -- the amendment's four identities -------------------------------------------

  # User story (I17; ADR-0046, amended 2026-11-04, identity 1):
  # As the owner reading "was it worth it" beside a frictionless benchmark,
  # I want the comparison to say what my portfolio paid in fees and taxes
  # in the same window,
  # so that a window with no cost reads 0 for both and I never guess.
  #
  # Acceptance criteria (exact Decimal expectations):
  # - A window with a deposit and a buy that carry no fee and no tax reads
  #   fees 0.00 and taxes 0.00, nothing excluded.
  # - costs_paid names the window it read, the comparison's requested one.
  test "identity 1: a window with no fee and no tax reads 0.00 for both" do
    {world, security} = world!("Free")
    buy!(world, security, quantity: "5", price: "100", date: ~D[2026-02-10])

    costs = portfolio_costs(world)

    assert Decimal.equal?(costs.fees, d("0.00"))
    assert Decimal.equal?(costs.taxes, d("0.00"))
    assert costs.excluded == %{count: 0, currencies: []}
    assert costs.window == %{start_date: ~D[2026-02-01], end_date: ~D[2026-02-28]}
  end

  # User story (I17; ADR-0046, amended 2026-11-04, identity 2):
  # As the owner whose only cost in the window is the fee on one buy,
  # I want exactly that fee beside the gap, and nothing when the buy lies
  # outside the window,
  # so that the figure reads the window's own bookings and no others.
  #
  # Acceptance criteria (exact Decimal expectations):
  # - A 5.00 EUR fee on a buy on the window's first day reads fees 5.00 and
  #   taxes 0.00.
  # - The same buy dated one day before the window reads 0.00 for both.
  test "identity 2: a 5.00 fee on a buy reads 5.00, and 0.00 one day before the window" do
    {inside, security} = world!("Inside")
    buy!(inside, security, quantity: "5", price: "100", fees: "5.00", date: ~D[2026-02-01])

    costs = portfolio_costs(inside)
    assert Decimal.equal?(costs.fees, d("5.00"))
    assert Decimal.equal?(costs.taxes, d("0.00"))

    {before, security} = world!("Before")
    buy!(before, security, quantity: "5", price: "100", fees: "5.00", date: ~D[2026-01-31])

    costs = portfolio_costs(before)
    assert Decimal.equal?(costs.fees, d("0.00"))
    assert Decimal.equal?(costs.taxes, d("0.00"))
  end

  # User story (I17; identity 2 at a moving rate, the plan's D-9):
  # As the owner who pays a fee from a USD account,
  # I want it converted at the rate stored on its own booking day,
  # so that a rate that moves later in the window does not move the fee.
  #
  # Acceptance criteria (exact Decimal expectations):
  # - 1 EUR = 1.25 USD on 2026-02-02 and 1.60 USD from 2026-02-20: a 5.00 USD
  #   fee booked on 2026-02-02 reads 5.00 / 1.25 = 4.00 EUR, never
  #   5.00 / 1.60 = 3.125.
  test "identity 2 at a moving rate: a USD fee converts at its own booking day's rate" do
    {world, _security} = world!("Dollar Fee")

    dollar =
      add_depot(world.portfolio,
        cash_currency: "USD",
        cash_name: "Fee USD",
        depot_name: "Fee USD Depot"
      )

    usd_rate!(~D[2026-01-02], "1.25")
    usd_rate!(~D[2026-02-02], "1.25")
    usd_rate!(~D[2026-02-20], "1.60")
    standalone!(world, dollar.cash, "deposit", "500", ~D[2026-01-05])
    standalone!(world, dollar.cash, "fee", "5.00", ~D[2026-02-02])

    costs = portfolio_costs(world)
    assert Decimal.equal?(costs.fees, d("4.00"))
    assert Decimal.equal?(costs.taxes, d("0.00"))
    assert costs.excluded.count == 0
  end

  # User story (I17; ADR-0046, amended 2026-11-04, identity 3):
  # As the owner who got part of a tax back,
  # I want the refund netted against the taxes,
  # so that the figure is what the window cost me, not what was withheld.
  #
  # Acceptance criteria (exact Decimal expectations):
  # - A 10.00 tax and a 2.00 tax_refund in the window read taxes 8.00 and
  #   fees 0.00.
  # - At a moving rate: a 10.00 USD tax at 1.25 (8.00 EUR) and a 2.00 USD
  #   refund at 1.60 (1.25 EUR) read taxes 6.75 EUR, each at its own day.
  test "identity 3: a 2.00 tax_refund against a 10.00 tax reads taxes 8.00" do
    {world, _security} = world!("Refund")
    standalone!(world, world.cash, "tax", "10.00", ~D[2026-02-05])
    standalone!(world, world.cash, "tax_refund", "2.00", ~D[2026-02-15])

    costs = portfolio_costs(world)
    assert Decimal.equal?(costs.taxes, d("8.00"))
    assert Decimal.equal?(costs.fees, d("0.00"))

    {moving, _security} = world!("Refund USD")

    dollar =
      add_depot(moving.portfolio,
        cash_currency: "USD",
        cash_name: "Tax USD",
        depot_name: "Tax USD Depot"
      )

    usd_rate!(~D[2026-01-02], "1.25")
    usd_rate!(~D[2026-02-05], "1.25")
    usd_rate!(~D[2026-02-15], "1.60")
    standalone!(moving, dollar.cash, "deposit", "500", ~D[2026-01-05])
    standalone!(moving, dollar.cash, "tax", "10.00", ~D[2026-02-05])
    standalone!(moving, dollar.cash, "tax_refund", "2.00", ~D[2026-02-15])

    costs = portfolio_costs(moving)
    assert Decimal.equal?(costs.taxes, d("6.75"))
    assert Decimal.equal?(costs.fees, d("0.00"))
  end

  # User story (I17; ADR-0046, amended 2026-11-04, identity 4):
  # As the owner whose USD fee has no stored rate on its day,
  # I want it left out of the totals and named,
  # so that a missing rate never reads as a cost of zero.
  #
  # Acceptance criteria (exact Decimal expectations):
  # - A 5.00 EUR fee and a 7.00 USD fee booked on a day with no USD rate:
  #   fees read 5.00, the USD fee is excluded and named (count 1, USD).
  # - computation_basis.gaps says such a cost is excluded and named.
  test "identity 4: a USD fee with no stored rate on its day is excluded and named" do
    {world, _security} = world!("No Rate")

    dollar =
      add_depot(world.portfolio,
        cash_currency: "USD",
        cash_name: "Norate USD",
        depot_name: "Norate USD Depot"
      )

    # A rate before and after, none on 2026-02-10 itself.
    usd_rate!(~D[2026-01-02], "1.25")
    usd_rate!(~D[2026-02-11], "1.25")
    standalone!(world, dollar.cash, "deposit", "500", ~D[2026-01-05])
    standalone!(world, world.cash, "fee", "5.00", ~D[2026-02-10])
    standalone!(world, dollar.cash, "fee", "7.00", ~D[2026-02-10])

    costs = portfolio_costs(world)
    assert Decimal.equal?(costs.fees, d("5.00"))
    assert Decimal.equal?(costs.taxes, d("0.00"))
    assert costs.excluded == %{count: 1, currencies: ["USD"]}
    assert costs.computation_basis.gaps =~ "excluded"
  end

  # -- the scope follows the paying cash account (point 3) -------------------------

  # User story (I17; ADR-0046, amended 2026-11-04, point 3):
  # As the owner comparing one portfolio, one view or everything,
  # I want a cost counted where the cash account that paid it counts,
  # so that the figure speaks about the same money as the gap beside it.
  #
  # Acceptance criteria (exact Decimal expectations):
  # - Portfolio A pays a 5.00 fee on a buy from its view's cash account and
  #   a 2.00 tax from a second account outside the view; portfolio B pays a
  #   3.00 fee whose buy's depot is in the view and whose cash account is
  #   not.
  # - Portfolio A reads fees 5.00, taxes 2.00; portfolio B reads fees 3.00.
  # - A scoped to the view reads fees 5.00, taxes 0.00; the view across
  #   portfolios reads fees 5.00, taxes 0.00: B's fee is outside, as the cash
  #   it moved is.
  # - The total reads fees 8.00, taxes 2.00, and over max it equals the
  #   facet's own sum of the same bookings (one rule, two windows).
  test "a cost counts where its paying cash account counts" do
    {a, sec_a} = world!("Scope A")
    {b, sec_b} = world!("Scope B")

    a_other =
      add_depot(a.portfolio, cash_name: "Scope A Other", depot_name: "Scope A Other Depot")

    standalone!(a, a_other.cash, "deposit", "100", ~D[2026-01-05])

    buy!(a, sec_a, quantity: "5", price: "100", fees: "5.00", date: ~D[2026-02-03])
    standalone!(a, a_other.cash, "tax", "2.00", ~D[2026-02-04])
    buy!(b, sec_b, quantity: "5", price: "100", fees: "3.00", date: ~D[2026-02-05])

    in_view = bucket!("Costs In")
    :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), a.cash, [in_view.id])
    :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), a.depot, [in_view.id])
    :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), b.depot, [in_view.id])
    view = view_including!([in_view.id], "Costs View")

    a_costs = portfolio_costs(a)
    assert Decimal.equal?(a_costs.fees, d("5.00"))
    assert Decimal.equal?(a_costs.taxes, d("2.00"))

    b_costs = portfolio_costs(b)
    assert Decimal.equal?(b_costs.fees, d("3.00"))
    assert Decimal.equal?(b_costs.taxes, d("0.00"))

    {:ok, scoped} =
      Benchmark.for_portfolio(a.portfolio.id, {:rate, d("0")},
        period: @window,
        view: view.id,
        today: @today
      )

    assert Decimal.equal?(scoped.costs_paid.fees, d("5.00"))
    assert Decimal.equal?(scoped.costs_paid.taxes, d("0.00"))

    {:ok, across} = Benchmark.for_view(view.id, {:rate, d("0")}, period: @window, today: @today)
    assert Decimal.equal?(across.costs_paid.fees, d("5.00"))
    assert Decimal.equal?(across.costs_paid.taxes, d("0.00"))

    {:ok, total} = Benchmark.for_view(nil, {:rate, d("0")}, period: @window, today: @today)
    assert Decimal.equal?(total.costs_paid.fees, d("8.00"))
    assert Decimal.equal?(total.costs_paid.taxes, d("2.00"))

    # Over max the total reads every booking, as the facet does: the two
    # sums agree because they are one rule.
    {:ok, all} = Benchmark.for_view(nil, {:rate, d("0")}, period: "max", today: @today)
    [year] = Costs.report(base_currency: "EUR").annual
    assert Decimal.equal?(all.costs_paid.fees, year.fees_total)
    assert Decimal.equal?(all.costs_paid.taxes, year.taxes_total)

    assert across.costs_paid.computation_basis.scope =~ "cash account"
  end

  # User story (I17; ADR-0046, amended 2026-11-04, points 1 and 4):
  # As the owner who compares against two benchmarks at once,
  # I want one costs figure for both, with a basis that says what it is
  # and what it is not,
  # so that the screen shows it once and nobody reads it as the gap's
  # explanation.
  #
  # Acceptance criteria:
  # - A fixed rate and a security whose quotes start inside the window (its
  #   covered window is shorter) read the same costs_paid over the
  #   requested window.
  # - computation_basis states the series rule, the conversion, the scope,
  #   the window, the reference and the gaps, and says the figure is not
  #   subtracted from the gap and names no residual; it never calls
  #   anything "selection and timing".
  test "costs_paid is the same for every benchmark of a request, and says what it leaves out" do
    {world, security} = world!("Two Bench")

    buy!(world, security,
      quantity: "5",
      price: "100",
      fees: "5.00",
      taxes: "1.00",
      date: ~D[2026-02-03]
    )

    late = create_security!(name: "Late Index", ticker: "LATE")
    {:ok, late} = Catalog.update_security(Actor.owner_ui(), late, %{is_benchmark: true})
    put_quotes!(late, [{~D[2026-02-10], "50"}, {~D[2026-02-20], "55"}])

    {:ok, rate_cmp} =
      Benchmark.for_portfolio(world.portfolio.id, {:rate, d("0.02")},
        period: @window,
        today: @today
      )

    {:ok, late_cmp} =
      Benchmark.for_portfolio(world.portfolio.id, {:security, late},
        period: @window,
        today: @today
      )

    assert late_cmp.window.start_date != rate_cmp.window.start_date
    assert late_cmp.costs_paid == rate_cmp.costs_paid
    assert Decimal.equal?(rate_cmp.costs_paid.fees, d("5.00"))
    assert Decimal.equal?(rate_cmp.costs_paid.taxes, d("1.00"))

    basis = rate_cmp.costs_paid.computation_basis
    assert basis.input_series =~ "tax_refund"
    assert basis.currency =~ "cash account's currency"
    assert basis.scope =~ "cash account"
    assert basis.window == %{start_date: ~D[2026-02-01], end_date: ~D[2026-02-28]}
    assert basis.reference =~ "booking date"
    assert basis.not_included =~ "not subtracted"
    assert basis.not_included =~ "compounded"

    refute basis
           |> Map.values()
           |> Enum.filter(&is_binary/1)
           |> Enum.any?(&(&1 =~ ~r/selection and timing/i))
  end
end
