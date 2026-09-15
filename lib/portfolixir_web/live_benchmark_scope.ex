defmodule PortfolixirWeb.LiveBenchmarkScope do
  @moduledoc """
  Reads the benchmark selection `PortfolixirWeb.BenchmarkScope` stored into
  every LiveView (ADR-0046 §4), as `:active_benchmark_selectors` — the raw
  selector strings, at most two. Resolving them against the catalog is the
  Wealth page's job; other pages carry the assign untouched.
  """

  import Phoenix.Component, only: [assign: 3]

  alias PortfolixirWeb.BenchmarkScope

  def on_mount(:default, _params, session, socket) do
    selectors =
      session
      |> Map.get(BenchmarkScope.session_key())
      |> BenchmarkScope.normalize_selectors()

    {:cont, assign(socket, :active_benchmark_selectors, selectors)}
  end
end
