defmodule Portfolixir.DerivedTest do
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Derived
  alias Portfolixir.Derived.DataVersion
  alias Portfolixir.Derived.Memo
  alias Portfolixir.Portfolios

  # User story (2026-08-12, ADR-0039, gate B3.2):
  # As a local portfolio maintainer,
  # I want every derived value served through ONE mechanism with a lifetime
  # parameter (:none / :request / :durable) over a versioned, named basis,
  # so that the repeat wait disappears for activated analytics without any
  # figure becoming less true or less rebuildable.
  #
  # Acceptance criteria (ADR-0039 §1, §4):
  # - One axis, three lifetimes: :none recomputes on every call; :request is
  #   the ADR-0032 volatile memo, absorbed; :durable is a row carrying `as_of`
  #   and `data_version` that survives a restart.
  # - Every read composes the current data version of the basis into the key —
  #   no return path claims freshness without checking the counter (I4 shape:
  #   `{:fresh, value}`; `peek/3` additionally returns `{:stale, value, as_of}`).
  # - A durable value round-trips its Decimals exactly.
  # - The computation version is part of the key: a formula change makes every
  #   stored value of the old formula unreachable.
  # - Disabled configuration degrades every lifetime to :none — one "off"
  #   state, and dropping the whole layer changes latency and nothing else.

  # The registry entries used below are the real ones: :performance_analysis
  # (configured :durable in this suite, mirroring the C3 activation) and
  # :performance_view_analysis (default :request). The mechanism is uniform,
  # so proving it on the registered analytics proves it for any activation.

  setup do
    Memo.reset()

    Application.put_env(:portfolixir, Derived,
      enabled?: true,
      lifetimes: [performance_analysis: :durable]
    )

    on_exit(fn -> Application.put_env(:portfolixir, Derived, enabled?: false) end)
    :ok
  end

  defp portfolio! do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Derived #{System.unique_integer([:positive])}",
        base_currency_code: "EUR"
      })

    portfolio
  end

  defp counting(value) do
    calls = :counters.new(1, [])

    fun = fn ->
      :counters.add(calls, 1, 1)
      value
    end

    {fun, fn -> :counters.get(calls, 1) end}
  end

  defp basis(portfolio), do: Derived.portfolio_basis(portfolio.id)

  test "the :request lifetime computes on a miss and remembers on the next read" do
    {compute, calls} = counting(%{daily: [:computed]})

    assert Derived.fetch(:performance_view_analysis, "global", "k=1", compute) ==
             {:fresh, %{daily: [:computed]}}

    assert Derived.fetch(:performance_view_analysis, "global", "k=1", compute) ==
             {:fresh, %{daily: [:computed]}}

    assert calls.() == 1
  end

  test "the entry key separates walks: a different key misses" do
    {compute_a, _} = counting(:a)
    {compute_b, calls_b} = counting(:b)

    assert {:fresh, :a} = Derived.fetch(:performance_view_analysis, "global", "k=a", compute_a)
    assert {:fresh, :b} = Derived.fetch(:performance_view_analysis, "global", "k=b", compute_b)
    assert calls_b.() == 1

    # The original entry is untouched.
    assert {:fresh, :a} =
             Derived.fetch(:performance_view_analysis, "global", "k=a", fn -> :recomputed end)
  end

  test "a :durable value survives a restart (memo wiped) without recomputing" do
    portfolio = portfolio!()
    {compute, calls} = counting(%{value: Decimal.new("42.10")})

    assert {:fresh, %{value: _}} =
             Derived.fetch(:performance_analysis, basis(portfolio), "k=1", compute)

    # A restart empties the volatile memo and nothing else.
    Memo.reset()

    assert {:fresh, %{value: value}} =
             Derived.fetch(:performance_analysis, basis(portfolio), "k=1", compute)

    assert calls.() == 1
    assert Decimal.equal?(value, Decimal.new("42.10"))
  end

  test "a durable payload round-trips its Decimals exactly, coefficient and exponent" do
    portfolio = portfolio!()
    exact = %{price: Decimal.new("97.2500"), qty: Decimal.new("10"), date: ~D[2024-06-28]}

    {:fresh, _} = Derived.fetch(:performance_analysis, basis(portfolio), "k=1", fn -> exact end)
    Memo.reset()

    {:fresh, read} =
      Derived.fetch(:performance_analysis, basis(portfolio), "k=1", fn ->
        flunk("must be served from the durable row")
      end)

    # Structural equality: "97.2500" stays "97.2500", never "97.25".
    assert read == exact
  end

  test "bumping the basis version makes both tiers unreachable" do
    portfolio = portfolio!()
    {compute, calls} = counting(:v1)

    {:fresh, :v1} = Derived.fetch(:performance_analysis, basis(portfolio), "k=1", compute)

    DataVersion.bump([portfolio.id])

    assert {:fresh, :recomputed} =
             Derived.fetch(:performance_analysis, basis(portfolio), "k=1", fn -> :recomputed end)

    assert calls.() == 1
  end

  test "a targeted bump leaves every other basis readable" do
    a = portfolio!()
    b = portfolio!()

    {:fresh, :a} = Derived.fetch(:performance_analysis, basis(a), "k=1", fn -> :a end)
    {:fresh, :b} = Derived.fetch(:performance_analysis, basis(b), "k=1", fn -> :b end)

    DataVersion.bump([a.id])

    assert {:fresh, :a2} = Derived.fetch(:performance_analysis, basis(a), "k=1", fn -> :a2 end)
    assert {:fresh, :b} = Derived.fetch(:performance_analysis, basis(b), "k=1", fn -> :b end)
  end

  test "every targeted bump also bumps the global basis (ADR-0032 §3.3, carried forward)" do
    {:fresh, :view} =
      Derived.fetch(:performance_view_analysis, "global", "k=1", fn -> :view end)

    DataVersion.bump([])

    assert {:fresh, :view2} =
             Derived.fetch(:performance_view_analysis, "global", "k=1", fn -> :view2 end)
  end

  test "bump(:all) reaches every portfolio basis, rows or no rows yet" do
    a = portfolio!()
    b = portfolio!()

    {:fresh, :a} = Derived.fetch(:performance_analysis, basis(a), "k=1", fn -> :a end)
    {:fresh, :b} = Derived.fetch(:performance_analysis, basis(b), "k=1", fn -> :b end)

    DataVersion.bump(:all)

    assert {:fresh, :a2} = Derived.fetch(:performance_analysis, basis(a), "k=1", fn -> :a2 end)
    assert {:fresh, :b2} = Derived.fetch(:performance_analysis, basis(b), "k=1", fn -> :b2 end)
  end

  test "the version counter is strictly monotonic under bumps" do
    portfolio = portfolio!()
    key = basis(portfolio)

    v0 = DataVersion.current(key)
    DataVersion.bump([portfolio.id])
    v1 = DataVersion.current(key)
    DataVersion.bump([portfolio.id])
    v2 = DataVersion.current(key)

    # Strictly increasing; not gapless — the event id sequence is shared
    # across bases, and only inequality carries meaning in the key.
    assert v1 > v0
    assert v2 > v1
  end

  # ADR-0032 §6, carried forward: one superseded generation stays readable
  # for the request tier — labelled, never as current — until a fresh
  # computation replaces it (the same until-replaced shape as the durable
  # tier's stale row).
  test "the request tier keeps the superseded generation readable until replaced" do
    {:fresh, :first} =
      Derived.fetch(:performance_view_analysis, "global", "k=1", fn -> :first end)

    assert Derived.peek(:performance_view_analysis, "global", "k=1") == {:fresh, :first}

    DataVersion.bump([])

    assert {:stale, :first, %DateTime{}} =
             Derived.peek(:performance_view_analysis, "global", "k=1")

    {:fresh, :second} =
      Derived.fetch(:performance_view_analysis, "global", "k=1", fn -> :second end)

    DataVersion.bump([])

    assert {:stale, :second, %DateTime{}} =
             Derived.peek(:performance_view_analysis, "global", "k=1")

    # Only ONE superseded generation: :first is archaeology and unreachable.
    {:fresh, :third} =
      Derived.fetch(:performance_view_analysis, "global", "k=1", fn -> :third end)

    assert Derived.peek(:performance_view_analysis, "global", "k=1") == {:fresh, :third}
  end

  test "a superseded durable value stays peekable with its as_of until replaced" do
    portfolio = portfolio!()

    {:fresh, :v1} = Derived.fetch(:performance_analysis, basis(portfolio), "k=1", fn -> :v1 end)
    assert Derived.peek(:performance_analysis, basis(portfolio), "k=1") == {:fresh, :v1}

    DataVersion.bump([portfolio.id])

    assert {:stale, :v1, %DateTime{}} =
             Derived.peek(:performance_analysis, basis(portfolio), "k=1")

    # Surviving a restart too: the stale render source is durable (§6 shape).
    Memo.reset()

    assert {:stale, :v1, %DateTime{}} =
             Derived.peek(:performance_analysis, basis(portfolio), "k=1")

    {:fresh, :v2} = Derived.fetch(:performance_analysis, basis(portfolio), "k=1", fn -> :v2 end)
    assert Derived.peek(:performance_analysis, basis(portfolio), "k=1") == {:fresh, :v2}
  end

  test "a stored value of an older computation version is never served" do
    portfolio = portfolio!()

    {:fresh, :old_formula} =
      Derived.fetch(:performance_analysis, basis(portfolio), "k=1", fn -> :old_formula end)

    # Simulate a formula change: the stored row predates the registry's
    # computation version. The data-version counter alone would not catch this
    # (ADR-0039 §5, "computation version in the key").
    Repo.update_all(Portfolixir.Derived.Value, set: [computation_version: 0])
    Memo.reset()

    assert {:fresh, :new_formula} =
             Derived.fetch(:performance_analysis, basis(portfolio), "k=1", fn -> :new_formula end)
  end

  test "disabled configuration degrades every lifetime to :none and stores nothing" do
    Application.put_env(:portfolixir, Derived, enabled?: false)
    portfolio = portfolio!()
    {compute, calls} = counting(:computed)

    assert {:fresh, :computed} =
             Derived.fetch(:performance_analysis, basis(portfolio), "k=1", compute)

    assert {:fresh, :computed} =
             Derived.fetch(:performance_analysis, basis(portfolio), "k=1", compute)

    assert calls.() == 2
    assert Derived.peek(:performance_analysis, basis(portfolio), "k=1") == :none
    assert Repo.aggregate(Portfolixir.Derived.Value, :count) == 0
  end

  test "an unregistered analytic is rejected, never silently computed" do
    assert_raise ArgumentError, fn ->
      Derived.fetch(:unregistered_metric, "global", "k=1", fn -> :nope end)
    end
  end
end
