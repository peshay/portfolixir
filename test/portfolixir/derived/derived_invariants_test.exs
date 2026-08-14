defmodule Portfolixir.Derived.DerivedInvariantsTest do
  @moduledoc """
  ADR-0039 §5 — the acceptance criteria as blocking invariants, tested as
  equations rather than examples. All comparisons are exact: structural
  equality for whole analyses (Decimals compare coefficient and exponent) or
  `Decimal.equal?` for hand-computed figures — never a tolerance.

  Covered here: I1 (rebuild equivalence, property-based), I2 (incremental ≡
  full across a correcting booking and a deletion), I3 (backdating, its own
  property), I5 (version bumps per write seam, non-bypassable), I6
  (drop-and-rebuild against historical exchange rates). I4's structural read
  shape is pinned in `derived_test.exs`, its payload half in the API/MCP
  serializer tests; I7 is static (`derived_never_a_write_source_test.exs`).
  """

  use Portfolixir.DataCase, async: false
  use ExUnitProperties

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Derived
  alias Portfolixir.Derived.DataVersion
  alias Portfolixir.Derived.Memo
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Performance

  @runs 15
  @today ~D[2024-12-31]

  setup do
    Memo.reset()

    Application.put_env(:portfolixir, Derived,
      enabled?: true,
      lifetimes: [performance_analysis: :durable]
    )

    on_exit(fn -> Application.put_env(:portfolixir, Derived, enabled?: false) end)
    :ok
  end

  # -- fixtures ---------------------------------------------------------------

  defp world!(currency \\ "EUR") do
    unique = System.unique_integer([:positive])

    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Inv #{unique}",
        base_currency_code: "EUR"
      })

    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Inv Cash #{unique}",
        currency_code: currency
      })

    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Inv Depot #{unique}"
      })

    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Inv AG #{unique}",
        currency_code: currency
      })

    %{portfolio: portfolio, cash: cash, depot: depot, security: security}
  end

  defp buy!(world, date, quantity, price) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        cash_account_id: world.cash.id,
        security_id: world.security.id,
        type: "buy",
        date: date,
        quantity: Decimal.new(quantity),
        price: Decimal.new(price),
        gross_amount: Decimal.mult(Decimal.new(quantity), Decimal.new(price)),
        currency_code: world.security.currency_code
      })

    tx
  end

  defp deposit!(world, date, amount) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        type: "deposit",
        date: date,
        gross_amount: Decimal.new(amount),
        currency_code: world.cash.currency_code
      })

    tx
  end

  defp quote!(world, date, close) do
    {:ok, _count} =
      Quotes.upsert_many(world.security.id, [
        %{date: date, close: Decimal.new(close), source: "manual"}
      ])
  end

  defp rate!(date, rate) do
    {:ok, _count} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: date,
          rate: Decimal.new(rate),
          source: "manual"
        }
      ])
  end

  # -- comparators ------------------------------------------------------------

  # The derived value as the mechanism serves it (durable lifetime).
  defp derived(world), do: Performance.analysis(world.portfolio.id, today: @today)

  # `rebuild_from_scratch(transactions)`: the same walk with the derived layer
  # off — nothing memoized, nothing stored, nothing versioned.
  defp rebuild_from_scratch(world) do
    saved = Application.get_env(:portfolixir, Derived)
    Application.put_env(:portfolixir, Derived, enabled?: false)

    try do
      Performance.analysis(world.portfolio.id, today: @today)
    after
      Application.put_env(:portfolixir, Derived, saved)
    end
  end

  # The compute instant is provenance, not value: it necessarily differs
  # between a stored analysis and a fresh rebuild. Everything else must be
  # structurally identical, Decimal exponents included.
  defp comparable(analysis), do: %{analysis | basis: Map.delete(analysis.basis, :computed_at)}

  defp value_on(analysis, %Date{} = date) do
    %{value: value} = Enum.find(analysis.daily, &(&1.date == date))
    value
  end

  # -- I1: rebuild equivalence ------------------------------------------------

  defp booking_op do
    gen all(
          kind <- member_of([:buy, :deposit]),
          offset <- integer(0..330),
          quantity <- integer(1..50),
          cents <- integer(100..500_000)
        ) do
      amount = cents |> Decimal.new() |> Decimal.div(100) |> Decimal.round(2)
      %{kind: kind, date: Date.add(~D[2024-01-02], offset), quantity: quantity, amount: amount}
    end
  end

  # User story (ADR-0039 §5 I1):
  # As a local portfolio maintainer,
  # I want every materialized series to equal the series rebuilt from the
  # transactions alone, for any ledger state,
  # so that the durable layer can never disagree with the single ledger truth.
  #
  # Acceptance criteria:
  # - derived == rebuild_from_scratch(transactions), structurally exact.
  # - The property holds with reads interleaved between writes, so every
  #   intermediate materialization is invalidated correctly — random booking
  #   dates make later inserts land before earlier ones (backdating included
  #   by construction; I3 pins the case deterministically below).
  property "I1: derived == rebuild_from_scratch(transactions) for any ledger state" do
    check all(ops <- list_of(booking_op(), min_length: 1, max_length: 6), max_runs: @runs) do
      world = world!()
      quote!(world, ~D[2024-02-01], "105.50")

      Enum.each(ops, fn op ->
        case op.kind do
          :buy -> buy!(world, op.date, op.quantity, op.amount)
          :deposit -> deposit!(world, op.date, op.amount)
        end

        # Materialize between writes: the invariant covers every version.
        derived(world)
      end)

      assert comparable(derived(world)) == comparable(rebuild_from_scratch(world))
    end
  end

  # -- I2: incremental ≡ full -------------------------------------------------

  # There deliberately IS no incremental application path (ADR-0032 rejected
  # one: the inputs are not append-only). "Incremental" here is what the
  # mechanism does instead — invalidate and recompute — and the invariant is
  # that after each of the killer writes (a correcting booking, a deletion)
  # the served value equals the full rebuild.
  test "I2: after a correcting booking the served value equals the full rebuild" do
    world = world!()
    tx = buy!(world, ~D[2024-01-10], "10", "100")
    quote!(world, ~D[2024-02-01], "120")
    before_correction = derived(world)

    {:ok, _} =
      Ledger.update_transaction(Actor.owner_ui(), tx, %{
        price: Decimal.new("90"),
        gross_amount: Decimal.new("900")
      })

    corrected = derived(world)
    assert comparable(corrected) == comparable(rebuild_from_scratch(world))
    refute comparable(corrected) == comparable(before_correction)
  end

  test "I2: after a deletion the served value equals the full rebuild" do
    world = world!()
    _keep = buy!(world, ~D[2024-01-10], "10", "100")
    doomed = buy!(world, ~D[2024-03-01], "5", "110")
    quote!(world, ~D[2024-02-01], "120")
    before_deletion = derived(world)

    {:ok, _} = Ledger.delete_transaction(Actor.owner_ui(), doomed)

    after_deletion = derived(world)
    assert comparable(after_deletion) == comparable(rebuild_from_scratch(world))
    refute comparable(after_deletion) == comparable(before_deletion)
  end

  # -- I3: backdating ---------------------------------------------------------

  # User story (ADR-0039 §5 I3):
  # As a local portfolio maintainer,
  # I want a transaction dated before the last materialized point to
  # invalidate everything downstream,
  # so that a late booking rewrites the series behind its own date instead of
  # leaving a stale prefix standing.
  #
  # Acceptance criteria:
  # - Its own property, always backdated — a generator would roll the case
  #   too rarely (ADR-0039 §5).
  # - The served series equals the full rebuild including the backdated
  #   booking, and differs from the pre-write materialization.
  property "I3: a backdated booking invalidates the materialized series behind its date" do
    check all(
            back_offset <- integer(1..30),
            quantity <- integer(1..20),
            max_runs: @runs
          ) do
      world = world!()
      buy!(world, ~D[2024-06-01], "10", "100")
      quote!(world, ~D[2024-07-01], "120")

      materialized = derived(world)

      # Strictly before every materialized point that carries the position.
      backdated_date = Date.add(~D[2024-06-01], -back_offset)
      buy!(world, backdated_date, quantity, "80")

      served = derived(world)

      assert comparable(served) == comparable(rebuild_from_scratch(world))
      refute comparable(served) == comparable(materialized)
      assert served.first_date == backdated_date
    end
  end

  # -- I5: version bumps per seam, non-bypassable ------------------------------

  test "I5: every write seam bumps the version of the bases it can affect" do
    world = world!()
    basis = Derived.portfolio_basis(world.portfolio.id)
    global = Derived.global_basis()

    v0 = {DataVersion.current(basis), DataVersion.current(global)}

    # Journal seam: a booking.
    buy!(world, ~D[2024-01-10], "10", "100")
    v1 = {DataVersion.current(basis), DataVersion.current(global)}
    assert elem(v1, 0) > elem(v0, 0)
    assert elem(v1, 1) > elem(v0, 1)

    # Quote seam (allowlisted out of the journal).
    quote!(world, ~D[2024-02-01], "120")
    v2 = {DataVersion.current(basis), DataVersion.current(global)}
    assert elem(v2, 0) > elem(v1, 0)
    assert elem(v2, 1) > elem(v1, 1)

    # FX seam (allowlisted out of the journal). This portfolio is
    # single-currency, so only the global basis must move.
    rate!(~D[2024-03-01], "1.10")
    v3 = {DataVersion.current(basis), DataVersion.current(global)}
    assert elem(v3, 0) == elem(v2, 0)
    assert elem(v3, 1) > elem(v2, 1)
  end

  test "I5: the journal seam carries the bump — same gate as the write-actor test" do
    # Non-bypassability is structural: every journaled financial write goes
    # through Journal.record/3 (write_actor_test.exs + the guard triggers),
    # and record/3 itself must announce the write to the derived layer inside
    # the writing transaction. This pins the announcement so a refactor
    # cannot drop it while the runtime tests above happen to stay green
    # through another path.
    source = File.read!("lib/portfolixir/journal.ex")
    ast = Code.string_to_quoted!(source)

    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {{:., _, [{:__aliases__, _, segments}, :after_write]}, _, _args} = node, _acc ->
          {node, List.last(segments) == :Invalidation}

        node, acc ->
          {node, acc}
      end)

    assert found?,
           "Journal.record/3 no longer announces writes to " <>
             "Portfolixir.Derived.Invalidation.after_write/3 (ADR-0039 I5)"
  end

  # -- I6: drop-and-rebuild against historical exchange rates ------------------

  # User story (ADR-0039 §5 I6):
  # As a local portfolio maintainer,
  # I want drop-and-rebuild to reproduce historical numbers, not today's,
  # so that the emergency procedure is a rebuild of the truth rather than a
  # re-pricing of the past at current rates.
  #
  # Acceptance criteria:
  # - The fixture carries HISTORICAL exchange rates: the rate changes midway,
  #   and the rebuilt series values each day at its own day's rate.
  # - Exact Decimal expectations on days before and after the rate change.
  # - The rebuilt analysis is structurally identical to the pre-drop one.
  test "I6: drop-and-rebuild reproduces historical numbers exactly" do
    world = world!("USD")
    rate!(~D[2024-01-04], "1.25")
    rate!(~D[2024-03-01], "1.60")
    deposit!(world, ~D[2024-01-05], "1000")
    buy!(world, ~D[2024-01-10], "10", "100")
    quote!(world, ~D[2024-02-01], "110")

    before_drop = derived(world)

    # Hand-computed, at each day's own historical rate (EUR hub, rate = USD
    # per EUR): 1000 USD cash / 1.25; 1100 USD position / 1.25; then / 1.60.
    assert Decimal.equal?(value_on(before_drop, ~D[2024-01-06]), Decimal.new("800"))
    assert Decimal.equal?(value_on(before_drop, ~D[2024-02-15]), Decimal.new("880"))
    assert Decimal.equal?(value_on(before_drop, ~D[2024-12-30]), Decimal.new("687.5"))

    {:ok, %{dropped: dropped, runtime_ms: runtime_ms}} =
      Derived.rebuild(fn -> derived(world) end)

    assert dropped >= 1
    assert is_integer(runtime_ms) and runtime_ms >= 0

    rebuilt = derived(world)
    assert comparable(rebuilt) == comparable(before_drop)
    assert Decimal.equal?(value_on(rebuilt, ~D[2024-01-06]), Decimal.new("800"))
    assert Decimal.equal?(value_on(rebuilt, ~D[2024-02-15]), Decimal.new("880"))
    assert Decimal.equal?(value_on(rebuilt, ~D[2024-12-30]), Decimal.new("687.5"))
  end
end
