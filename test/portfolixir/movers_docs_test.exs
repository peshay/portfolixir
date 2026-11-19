defmodule Portfolixir.MoversDocsTest do
  use ExUnit.Case, async: true

  # User story (Sprint 30 T2; FR-59, ADR-0061 §9; the coverage rule):
  # As the agent that reads the API reference, or the operator who reads it
  # in German,
  # I want the tops and flops' two routes described with their parameters,
  # their payload and every refusal, and their tool with its profiles,
  # so that I read what moved most without reading code, and know that the
  # rankings are data, never advice.
  #
  # Acceptance criteria:
  # - The API references (EN, DE) have a tops and flops section, between the
  #   crash windows and the position dossier, naming both routes; the six
  #   windows and the default; limit (default 5, capped at 50) and
  #   include_unanswered; the payload's keys (price_return, contribution,
  #   highest, lowest, answered, unanswered, unanswered_entries,
  #   computation_basis, held_at_end); the reasons; the refusals (401, 404,
  #   422 naming it); and that the answer is data, never advice.
  # - Both name portfolixir.views.movers, its id, and that it is a read in
  #   every profile.

  defp normalized(path), do: path |> File.read!() |> String.replace(~r/\s+/, " ")

  defp section(path, from, to) do
    text = normalized(path)
    assert text =~ from, "#{path} has no #{from}"
    [_, rest] = String.split(text, from, parts: 2)
    [body | _] = String.split(rest, to, parts: 2)
    body
  end

  @shared [
    "GET /api/v1/views/:view_id/movers",
    "GET /api/v1/movers",
    "`day`",
    "`week`",
    "`month`",
    "`quarter`",
    "`ytd`",
    "`1y`",
    "`limit`",
    "`include_unanswered`",
    "`price_return`",
    "`contribution`",
    "`highest`",
    "`lowest`",
    "`answered`",
    "`unanswered`",
    "`unanswered_entries`",
    "`computation_basis`",
    "`held_at_end`",
    "`no_close_at_start`",
    "`no_close_at_end`",
    "`no_fx_rate`",
    "`one_close_only`",
    "`no_valuation`",
    "`401`",
    "`404`",
    "`422`",
    "`portfolixir.views.movers`",
    "`id`",
    "`read`, `book` und `full`",
    "metrics_carry_no_verdict_test.exs",
    "ADR-0061"
  ]

  test "the API references describe the tops and flops, in English and German" do
    en =
      section(
        "docs/integration/api-and-mcp.md",
        "### Tops and flops per calendar window (ADR-0061)",
        "### The position dossier"
      )

    de =
      section(
        "docs/de/integration/api-and-mcp.md",
        "### Tops und Flops je Kalenderfenster (ADR-0061)",
        "### Das Positionsdossier"
      )

    for part <- @shared -- ["`read`, `book` und `full`"],
        do: assert(en =~ part, "EN: #{part}")

    for part <- ["`read`, `book` and `full`", "data, never advice", "capped at 50"],
        do: assert(en =~ part, "EN: #{part}")

    for part <- @shared, do: assert(de =~ part, "DE: #{part}")

    for part <- ["Daten, nie ein Rat", "auf 50 begrenzt"],
        do: assert(de =~ part, "DE: #{part}")
  end
end
