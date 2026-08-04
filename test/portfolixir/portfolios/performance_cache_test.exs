defmodule Portfolixir.Portfolios.PerformanceCacheTest do
  use ExUnit.Case, async: false

  alias Portfolixir.Portfolios.Performance.Cache

  # User story (2026-07-29, ADR-0032, issue #562):
  # As a local portfolio maintainer,
  # I want a computed performance series remembered until its inputs change,
  # so that a page reload does not pay for the whole daily walk again.
  #
  # Acceptance criteria:
  # - A memo, not a store: it is volatile, and switching it off changes latency
  #   and nothing else.
  # - Keyed per portfolio, view scope, walk end date and that portfolio's data
  #   version.
  # - Invalidating one portfolio leaves every other memo readable.
  # - Exactly one previous generation survives per key, so §6 has something to
  #   render while a fresh series computes.

  setup do
    Cache.reset()
    Application.put_env(:portfolixir, Cache, enabled?: true)
    on_exit(fn -> Application.put_env(:portfolixir, Cache, enabled?: false) end)
    :ok
  end

  defp compute(value), do: fn -> value end

  test "computes on a miss and remembers on the next read" do
    calls = :counters.new(1, [])

    counting = fn ->
      :counters.add(calls, 1, 1)
      %{daily: [:computed]}
    end

    assert Cache.fetch(1, :unscoped, ~D[2026-07-29], counting) == %{daily: [:computed]}
    assert Cache.fetch(1, :unscoped, ~D[2026-07-29], counting) == %{daily: [:computed]}

    assert :counters.get(calls, 1) == 1
  end

  test "the view scope, the portfolio and the end date are all part of the identity" do
    Cache.fetch(1, :unscoped, ~D[2026-07-29], compute(:a))

    assert Cache.fetch(1, 7, ~D[2026-07-29], compute(:scoped)) == :scoped

    assert Cache.fetch(2, :unscoped, ~D[2026-07-29], compute(:other_portfolio)) ==
             :other_portfolio

    assert Cache.fetch(1, :unscoped, ~D[2026-07-30], compute(:tomorrow)) == :tomorrow

    # The original entry is untouched by any of them.
    assert Cache.fetch(1, :unscoped, ~D[2026-07-29], compute(:recomputed)) == :a
  end

  # ADR-0032 §3.3, #577 fix round: a write whose provable blast radius is
  # empty (e.g. an FX rate when every portfolio is single-currency in its own
  # base) still changes the cross-portfolio view walk, which converts every
  # slice into one common base. Even an empty targeted invalidation must
  # therefore bump the :global scope — a stale view series must never be
  # served as current after a financial write.
  test "an empty targeted invalidation still drops the global view memo" do
    global = Cache.global_scope_id()
    Cache.fetch(global, {:unscoped, "EUR"}, ~D[2026-07-29], compute(:view))
    Cache.fetch(1, :unscoped, ~D[2026-07-29], compute(:portfolio))

    Cache.invalidate([])

    assert Cache.fetch(global, {:unscoped, "EUR"}, ~D[2026-07-29], compute(:view_again)) ==
             :view_again

    # Portfolio memos are untouched — the radius said none of them changed.
    assert Cache.fetch(1, :unscoped, ~D[2026-07-29], compute(:portfolio_again)) == :portfolio
  end

  # The whole point of the owner's targeted-invalidation decision.
  test "invalidating one portfolio leaves the others readable" do
    Cache.fetch(1, :unscoped, ~D[2026-07-29], compute(:one))
    Cache.fetch(2, :unscoped, ~D[2026-07-29], compute(:two))

    Cache.invalidate([1])

    assert Cache.fetch(1, :unscoped, ~D[2026-07-29], compute(:one_again)) == :one_again
    assert Cache.fetch(2, :unscoped, ~D[2026-07-29], compute(:two_again)) == :two
  end

  test "invalidating everything drops every portfolio" do
    Cache.fetch(1, :unscoped, ~D[2026-07-29], compute(:one))
    Cache.fetch(2, :unscoped, ~D[2026-07-29], compute(:two))

    Cache.invalidate(:all)

    assert Cache.fetch(1, :unscoped, ~D[2026-07-29], compute(:one_again)) == :one_again
    assert Cache.fetch(2, :unscoped, ~D[2026-07-29], compute(:two_again)) == :two_again
  end

  # ADR-0032 §6 needs exactly one superseded generation to render.
  test "the previous generation survives one invalidation and no more" do
    Cache.fetch(1, :unscoped, ~D[2026-07-29], compute(:first))
    assert Cache.previous(1, :unscoped, ~D[2026-07-29]) == nil

    Cache.invalidate([1])
    assert Cache.previous(1, :unscoped, ~D[2026-07-29]) == :first

    Cache.fetch(1, :unscoped, ~D[2026-07-29], compute(:second))
    Cache.invalidate([1])
    assert Cache.previous(1, :unscoped, ~D[2026-07-29]) == :second

    # Two invalidations without an intervening computation leave nothing to show
    # rather than reaching further back.
    Cache.invalidate([1])
    assert Cache.previous(1, :unscoped, ~D[2026-07-29]) == nil
  end

  test "a previous generation is scoped to its own key" do
    Cache.fetch(1, :unscoped, ~D[2026-07-29], compute(:everything))
    Cache.fetch(1, 7, ~D[2026-07-29], compute(:scoped))
    Cache.invalidate([1])

    assert Cache.previous(1, :unscoped, ~D[2026-07-29]) == :everything
    assert Cache.previous(1, 7, ~D[2026-07-29]) == :scoped
    assert Cache.previous(2, :unscoped, ~D[2026-07-29]) == nil
  end

  # "Dropping it changes latency and nothing else" has to be a checked claim.
  test "with the cache disabled every read recomputes and nothing is remembered" do
    Application.put_env(:portfolixir, Cache, enabled?: false)
    calls = :counters.new(1, [])

    counting = fn ->
      :counters.add(calls, 1, 1)
      :computed
    end

    assert Cache.fetch(1, :unscoped, ~D[2026-07-29], counting) == :computed
    assert Cache.fetch(1, :unscoped, ~D[2026-07-29], counting) == :computed

    assert :counters.get(calls, 1) == 2
    assert Cache.previous(1, :unscoped, ~D[2026-07-29]) == nil
  end

  test "invalidating an unknown portfolio is a no-op, not an error" do
    assert Cache.invalidate([999]) == :ok
    assert Cache.previous(999, :unscoped, ~D[2026-07-29]) == nil
  end
end
