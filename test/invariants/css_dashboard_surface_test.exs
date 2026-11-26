defmodule Portfolixir.Invariants.CssDashboardSurfaceTest do
  use ExUnit.Case, async: true

  # The dashboard as one surface and the widget anatomy's rules as the
  # stylesheet states them (Sprint 32 L1; D-14; boards
  # ux-design-2026-11-25-sprint32/07 ② and 10 D; DESIGN.md → "The widget
  # anatomy and the one surface"). What a browser draws of them is
  # measured by test/browser/widget_anatomy_test.exs; this module pins the
  # tokens the walk's figures come from and the two rules a walk on the
  # review seed cannot see broken.

  @css File.read!("priv/static/app.css")

  # User story (D-14, the owner's pick D „Eine Fläche“):
  # As the maintainer who builds the next widget,
  # I want the surface's measures as tokens in one place,
  # so that a widget is born on the surface instead of copying its px.
  #
  # Acceptance criteria:
  # - `:root` defines the frame's 16 px corner, the 1 px hairline, the
  #   16 × 18 px inside and the three figure sizes 28, 34 and 24 px.
  # - The grid and the widget read them: the grid's gap, frame and
  #   corner; the widget's padding and its hairline.
  test "the surface's measures are tokens the grid and the widget read" do
    [root] = Regex.run(~r/\A:root \{(.*?)\n\}/s, @css, capture: :all_but_first)

    for {token, value} <- [
          {"surface-radius", "16px"},
          {"surface-hairline", "1px"},
          {"widget-pad-y", "16px"},
          {"widget-pad-x", "18px"},
          {"widget-figure-s", "28px"},
          {"widget-figure-m", "34px"},
          {"widget-figure-secondary", "24px"}
        ] do
      assert root =~ ~r/--#{token}:\s*#{value};/, "--#{token} is not #{value} in :root"
    end

    grid = block(".dashboard-grid")
    assert grid =~ "gap: var(--surface-hairline);"
    assert grid =~ "border: var(--surface-hairline) solid var(--color-border);"
    assert grid =~ "border-radius: var(--surface-radius);"

    widget = block(".dashboard-widget")
    assert widget =~ "padding: var(--widget-pad-y) var(--widget-pad-x);"
    assert widget =~ "box-shadow: 0 0 0 var(--surface-hairline) var(--color-border);"
    assert widget =~ "border: 0;"
  end

  # User story (board 07 ②, 4; the owner on 2026-11-25: „das war
  # hilfreich“):
  # As the operator reading a ranking on the phone,
  # I want the bar under comparable figures kept in the compact forms,
  # so that the phone shows which figure is large, as the desk does.
  #
  # Acceptance criteria:
  # - No rule anywhere in the stylesheet hides `.widget-bar` (unlike
  #   `.drift-bar`, which gives way under 560 px).
  # - The check's own attack: a rule hiding the bar under 560 px, inside
  #   a media block, is named.
  test "the anatomy's bar is never hidden" do
    assert hiding(@css) == [], "a rule hides the anatomy's bar: #{inspect(hiding(@css))}"

    attack =
      "@media (max-width: 560px) {\n  .widget-row .widget-bar {\n    display: none;\n  }\n}\n"

    assert [[selector, _body]] = hiding(@css <> attack)
    assert selector =~ ".widget-row .widget-bar"
  end

  defp hiding(css) do
    ~r/([^{}]*)\{([^{}]*)\}/
    |> Regex.scan(css, capture: :all_but_first)
    |> Enum.filter(fn [selector, body] ->
      selector =~ "widget-bar" and body =~ ~r/display:\s*none/
    end)
  end

  # User story (the polish list #1358, line on the dead strip; Sprint 32
  # E4 removed the Overview's KPI strip from „Gesamtwert“):
  # As the maintainer reading the stylesheet,
  # I want no rule for a component no page draws,
  # so that a reader is not sent looking for the strip.
  #
  # Acceptance criteria:
  # - No `.kpi-strip` selector is left in app.css, and no template draws
  #   one.
  test "the removed KPI strip leaves no rule behind" do
    refute @css =~ ".kpi-strip", "app.css still styles the removed KPI strip"

    drawn =
      "lib/portfolixir_web/**/*.{ex,heex}"
      |> Path.wildcard()
      |> Enum.filter(&(File.read!(&1) =~ "kpi-strip"))

    assert drawn == []
  end

  defp block(selector) do
    pattern = ~r/(?:^|\n)#{Regex.escape(selector)} \{([^}]*)\}/

    case Regex.run(pattern, @css, capture: :all_but_first) do
      [body] -> body
      nil -> flunk("no rule for #{selector}")
    end
  end
end
