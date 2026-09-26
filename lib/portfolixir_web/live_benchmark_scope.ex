defmodule PortfolixirWeb.LiveBenchmarkScope do
  @moduledoc """
  Reads the benchmark selection `PortfolixirWeb.BenchmarkScope` stored into
  every LiveView (ADR-0046 §4), as `:active_benchmark_selectors` — the raw
  selector strings, at most two. Resolving them against the catalog is the
  Wealth page's job; other pages carry the assign untouched.

  A `?benchmark[]=` / `?benchmark_rate=` in the page's own address wins over
  the session (E25 S7 review round, S7E-4): a choice from another site is
  kept out of the session, so the page it opened reads it from there.
  """

  import Phoenix.Component, only: [assign: 3]

  alias PortfolixirWeb.BenchmarkScope

  def on_mount(:default, params, session, socket) do
    selectors =
      case BenchmarkScope.choice(params) do
        {:ok, selectors} ->
          selectors

        :none ->
          session
          |> Map.get(BenchmarkScope.session_key())
          |> BenchmarkScope.normalize_selectors()
      end

    {:cont, assign(socket, :active_benchmark_selectors, selectors)}
  end
end
