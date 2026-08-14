defmodule PortfolixirWeb.Api.V1.JsonFreshnessMetaTest do
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Performance
  alias PortfolixirWeb.Api.V1.JSON

  # User story (ADR-0039 §5 I4, payload half):
  # As the agent reading finished figures over API/MCP,
  # I want a meta-test asserting that no serialization of a derived
  # performance value drops the freshness fields,
  # so that freshness stays structural — the agent cannot look at a warning
  # triangle, it reads `as_of` and `stale` in every payload shape.
  #
  # Acceptance criteria:
  # - JSON.performance/2 and JSON.view_performance/2 carry :as_of, :stale and
  #   :computation_basis in every shape: empty and seeded, with and without
  #   the series.
  # - The MCP companion wraps the JSON API 1:1, so the same fields flow to
  #   the agent unmodified (the tools pass the response body through).

  @freshness_keys [:as_of, :stale, :computation_basis]

  test "no performance serialization drops the freshness fields" do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Meta Fresh",
        base_currency_code: "EUR"
      })

    {:ok, empty_summary} = Performance.for_portfolio(portfolio.id, today: ~D[2024-06-30])
    {:ok, view_summary} = Performance.for_view(nil, today: ~D[2024-06-30])

    payloads = [
      JSON.performance(empty_summary),
      JSON.performance(empty_summary, true),
      JSON.view_performance(view_summary),
      JSON.view_performance(view_summary, true)
    ]

    for payload <- payloads, key <- @freshness_keys do
      assert Map.has_key?(payload, key),
             "a performance payload dropped #{inspect(key)} — freshness must be " <>
               "structural in every serialization (ADR-0039 I4): #{inspect(Map.keys(payload))}"
    end

    for payload <- payloads do
      assert is_boolean(payload.stale)

      assert %{input_series: _, window: _, reference: _, gaps: _} = payload.computation_basis
    end
  end
end
