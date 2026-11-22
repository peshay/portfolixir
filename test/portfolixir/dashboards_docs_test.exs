defmodule Portfolixir.DashboardsDocsTest do
  use ExUnit.Case, async: true

  # User story (Sprint 31 D2; FR-60, ADR-0062 §8; the coverage rule):
  # As the agent that reads the API reference, or the operator who reads it
  # in German,
  # I want the widget catalogue, the dashboard routes and the four tools
  # described with their payloads, every refusal and a worked example,
  # so that I can compose a dashboard without reading code, and know that a
  # dashboard holds no figure.
  #
  # Acceptance criteria:
  # - The API references (EN, DE) have a dashboards section, between the
  #   settings and the imports, naming the seven routes; the catalogue's
  #   keys (widgets, groups, grid, periods, title_key, source, period,
  #   scope, compact); the template read template:<key>; type, in_menu and
  #   read_only; lock_version and the 409 with errors.stored; dry_run and
  #   would_remove; errors.layout_item with index, field and reason, every
  #   reason named (no_view among them); too_many_dashboards; the 401, 404
  #   and 422.
  # - Both name the four tools, put's three routes, the profiles (read in
  #   every profile, book, admin) and a worked example: a put for short-term
  #   movements with a pinned period, and the 409's body.

  defp normalized(path), do: path |> File.read!() |> String.replace(~r/\s+/, " ")

  defp section(path, from, to) do
    text = normalized(path)
    assert text =~ from, "#{path} has no #{from}"
    [_, rest] = String.split(text, from, parts: 2)
    [body | _] = String.split(rest, to, parts: 2)
    body
  end

  @shared [
    "GET /api/v1/widgets",
    "GET /api/v1/dashboards",
    "GET /api/v1/dashboards/:id",
    "GET /api/v1/dashboards/template:<key>",
    "POST /api/v1/dashboards",
    "PUT /api/v1/dashboards/:id",
    "PATCH /api/v1/dashboards/:id",
    "DELETE /api/v1/dashboards/:id",
    "`widgets`",
    "`groups`",
    "`grid`",
    "`periods`",
    "`title_key`",
    "`source`",
    "`scope`",
    "`compact`",
    "`in_menu`",
    "`read_only`",
    "`lock_version`",
    "`409`",
    "\"stored\"",
    "`dry_run=true`",
    "\"would_remove\"",
    "\"layout_item\"",
    "`unknown_kind`",
    "`unsupported_size`",
    "`off_grid`",
    "`overlap`",
    "`unknown_view`",
    "`no_view`",
    "`no_period`",
    "`unsupported_period`",
    "`unknown_key`",
    "`too_many_items`",
    "\"too_many_dashboards\"",
    "`401`",
    "`404`",
    "`422`",
    "`portfolixir.dashboards.list`",
    "`portfolixir.dashboards.get`",
    "`portfolixir.dashboards.put`",
    "`portfolixir.dashboards.delete`",
    "`book`",
    "metrics_carry_no_verdict_test.exs",
    "ADR-0062",
    # The worked example: a put for short-term movements.
    "\"kind\": \"movers\"",
    "\"period\": \"1w\"",
    "\"code\": \"stale\""
  ]

  test "the API references describe the dashboards and widgets, in English and German" do
    en =
      section(
        "docs/integration/api-and-mcp.md",
        "## Dashboards and widgets (ADR-0062)",
        "## Imports"
      )

    de =
      section(
        "docs/de/integration/api-and-mcp.md",
        "## Dashboards und Widgets (ADR-0062)",
        "## Importe"
      )

    for {text, lang} <- [{en, "en"}, {de, "de"}], expected <- @shared do
      assert text =~ expected, "#{lang} dashboards section lacks #{expected}"
    end

    # An item's title and source are read-only and ignored on write, so a
    # layout goes back as read (Sprint 31 closing act, C3/A2).
    for expected <- [
          "a dashboard deletes nothing else",
          "never written",
          "in every profile",
          "a write ignores an item's `title` and `source`"
        ],
        do: assert(en =~ expected, expected)

    for expected <- [
          "Ein Dashboard löscht nichts anderes",
          "nie geschrieben",
          "in jedem Profil",
          "Ein Schreibzugriff übergeht `title` und `source`"
        ],
        do: assert(de =~ expected, expected)
  end

  # Acceptance criteria:
  # - The worked example's body, in each language, is a layout the server
  #   accepts as it stands (no view is named, so no table is read).
  test "the worked example is a layout the server accepts" do
    for path <- ["docs/integration/api-and-mcp.md", "docs/de/integration/api-and-mcp.md"] do
      [body] =
        Regex.run(
          ~r/POST \/api\/v1\/dashboards\n[^{]*(\{"dashboard".*?\]\}\})\n```/s,
          File.read!(path),
          capture: :all_but_first
        )

      %{"dashboard" => %{"layout" => layout}} = Jason.decode!(body)
      assert {:ok, [_, _, _]} = Portfolixir.Dashboards.validate_layout(layout), path
    end
  end
end
