defmodule Portfolixir.DashboardsDocsTest do
  use ExUnit.Case, async: true

  alias Portfolixir.Dashboards.Widgets

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

  # User story (Sprint 32 E3; ADR-0062's amendment of 2026-11-25, point 2):
  # As the agent that reads the API reference, or the operator who reads it
  # in German,
  # I want the arrangement on request described where the replace is,
  # so that I know how to make room for one widget and that the server
  # never moves one I did not ask it to.
  #
  # Acceptance criteria:
  # - Both references name `arrange` "push" and `arranged_index` on the
  #   replace and on the MCP put, say that without them an overlap is still
  #   refused, and name the refusal `no_room`.
  test "the API references describe arrange: push on the replace" do
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

    for {text, lang} <- [{en, "en"}, {de, "de"}],
        expected <- ["`\"arrange\": \"push\"`", "`arranged_index`", "`no_room`", "`arrange`"] do
      assert text =~ expected, "#{lang} dashboards section lacks #{expected}"
    end

    assert en =~ "without them an overlap is still refused with `422`"
    assert en =~ "`portfolixir.dashboards.put` takes `arrange` and `arranged_index`"
    assert de =~ "ohne sie wird eine Überlappung weiterhin mit `422` abgelehnt"
    assert de =~ "`portfolixir.dashboards.put` nimmt `arrange` und `arranged_index`"
  end

  # User story (Sprint 32 E4; ADR-0062's amendment of 2026-11-25, point 3):
  # As the agent that reads the API reference, or the operator who reads it
  # in German,
  # I want the sizes named as Apple's widget families with their columns
  # and rows, the fixed row and the rule each kind's sizes follow,
  # so that a layout I compose uses the sizes the server takes, and I know
  # a stored layout of Sprint 31 is read on them.
  #
  # Acceptance criteria:
  # - Both references name S 3 × 2, M 6 × 2, L 6 × 4 and XL 12 × 4 with
  #   their families, `row_height` and `size_rule`, that W and T are no
  #   size any more, and how a Sprint 31 layout is read (S → S, W → M,
  #   M → L, T → L, L → XL, the rows doubled).
  test "the API references name the families, the fixed row and the reading of Sprint 31's sizes" do
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

    for {text, lang} <- [{en, "en"}, {de, "de"}],
        expected <- [
          "`S` 3 × 2",
          "`M` 6 × 2",
          "`L` 6 × 4",
          "`XL` 12 × 4",
          "`row_height`",
          "`size_rule`",
          "S → S, W → M, M → L, T → L, L → XL"
        ] do
      assert text =~ expected, "#{lang} dashboards section lacks #{expected}"
    end

    assert en =~ "small, medium, large and extra large"
    assert de =~ "klein, mittel, groß und extra groß"
    refute en =~ "`W` 6 × 1"
    refute de =~ "`W` 6 × 1"
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

  # User story (Sprint 32 L4; plan D-13; the owner on 2026-11-25: „das
  # brauchen wir auch für die Doku“):
  # As the reader of the docs choosing widgets, in English or German,
  # I want one catalogue page naming every widget with its sizes, what it
  # draws and its source route, with its pictures,
  # so that no widget is missing from the docs when one is added.
  #
  # Acceptance criteria:
  # - docs/guides/widgets.md and docs/de/guides/widgets.md carry the docs
  #   layout and the language switcher's front matter, and the navigation
  #   lists the page.
  # - For every kind the registry holds (`Portfolixir.Dashboards.Widgets`),
  #   each page names its key, every source route, and, for every grid size
  #   it takes, its light and its dark picture, each a file under
  #   docs/assets/widgets/ (written by test/browser/widget_gallery_test.exs).
  # - The check's own attack: a page with one kind's section left out is
  #   named.
  test "the widget catalogue names every registered kind with its sizes, pictures and routes" do
    navigation = File.read!("docs/_data/navigation.yml")
    assert navigation =~ "url: /guides/widgets.html"

    for {path, lang} <- [{"docs/guides/widgets.md", "en"}, {"docs/de/guides/widgets.md", "de"}] do
      page = File.read!(path)
      assert page =~ ~r/\A---\nlayout: docs\n/
      assert page =~ "lang: #{lang}"
      assert page =~ "lang_en: /guides/widgets.html"
      assert page =~ "lang_de: /de/guides/widgets.html"
      assert catalogue_gaps(page) == [], "#{path}: #{inspect(catalogue_gaps(page))}"

      for [_, file] <- Regex.scan(~r{/assets/widgets/([\w-]+\.png)}, page) do
        assert File.exists?(Path.join("docs/assets/widgets", file)), "#{path}: #{file} is missing"
      end
    end

    page = File.read!("docs/guides/widgets.md")
    [first | _] = Widgets.kinds()
    attack = String.replace(page, "`#{first.key}`", "`gone`")
    assert {first.key, :key} in catalogue_gaps(attack)
  end

  # What a page leaves out of the registry: a kind's key, a route, a
  # picture of a grid size in a theme.
  defp catalogue_gaps(page) do
    for kind <- Widgets.kinds(),
        gap <-
          [{kind.key, :key} | Enum.map(kind.source.routes, &{kind.key, &1})] ++
            for(
              size <- kind.sizes,
              match?({:ok, _}, Widgets.dimensions(size)),
              theme <- ~w(light dark),
              do: {kind.key, "/assets/widgets/#{kind.key}-#{String.downcase(size)}-#{theme}.png"}
            ),
        missing?(page, gap),
        do: gap
  end

  defp missing?(page, {key, :key}), do: not String.contains?(page, "`#{key}`")
  defp missing?(page, {_key, text}), do: not String.contains?(page, text)
end
