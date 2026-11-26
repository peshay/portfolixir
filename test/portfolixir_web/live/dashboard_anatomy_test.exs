defmodule PortfolixirWeb.DashboardAnatomyTest do
  # The widget anatomy as shared components (Sprint 32 L1; board
  # ux-design-2026-11-25-sprint32/07 ②; D-12; DESIGN.md → "The widget
  # anatomy and the one surface"): the head on one line, the headline
  # figure, the list row, the bar under comparable figures, the warning
  # line and the one-line footer, each one function component in
  # `PortfolixirWeb.Dashboard.Widget` that every kind draws with. This
  # module checks the markup each component draws; what the browser makes
  # of it (one line, nothing cut, no box, the one surface) is measured by
  # test/browser/widget_anatomy_test.exs. Synthetic values only.
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest

  alias PortfolixirWeb.Dashboard.Widget

  # An item as the page hands it to a kind (`Widget.items/3`, then
  # `Widget.with_period/3`): „Tops und Flops“ at S on a stored dashboard.
  defp item(overrides \\ %{}) do
    Map.merge(
      %{
        kind: "movers",
        index: 0,
        size: "S",
        col: 1,
        row: 1,
        w: 3,
        h: 2,
        uid: "",
        takes_view: true,
        settings: %{},
        scope: nil,
        dangling: false,
        period: "1y",
        period_state: :follows,
        period_label: "1Y",
        dashboard_period: "1y",
        dashboard_period_label: "1Y",
        pin_note: nil,
        periods: ~w(1y),
        pinnable: true
      },
      overrides
    )
  end

  defp parse(html), do: Floki.parse_fragment!(html)

  defp classes(list), do: list |> Enum.join(" ") |> String.split()

  # The text a sighted reader sees: the visually hidden words left out.
  defp visible(node) do
    node
    |> Floki.filter_out(".visually-hidden")
    |> Floki.text()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp frame(item, extra \\ []) do
    assigns = Map.merge(%{item: item, warning: false}, Map.new(extra))

    rendered_to_string(~H"""
    <Widget.frame
      id="probe"
      item={@item}
      title="Tops und Flops"
      scope_label="View Everything"
      full_href="/portfolio"
      full_label="In Wealth →"
    >
      <:info>Basis</:info>
      <:switch>
        <span class="segmented-control">Price return · Contribution</span>
      </:switch>
      <:warning :if={@warning} href="/portfolio" link="Details →">3 not in the total</:warning>
      <p>Body</p>
    </Widget.frame>
    """)
    |> parse()
  end

  # User story (board 07 ②, 1: „Kopf, eine Zeile“):
  # As the operator scanning a dashboard,
  # I want each widget's head on one line — its title, ⓘ, the period as a
  # small mark, the widget's own switch and ⋯ —,
  # so that no widget spends a second line on its period and every body
  # starts at the same depth.
  #
  # Acceptance criteria:
  # - The head holds, in this order, the title (its full text in a
  #   tooltip, for a tile too narrow for it), the ⓘ, the period mark, the
  #   widget's switch and the ⋯ menu; nothing of the head stands outside
  #   it.
  # - The period mark shows the period alone („1Y“; pinned „📌 Max“); the
  #   words „follows ·“ and „own:“ stay for a screen reader and in its
  #   tooltip, so the mark reads as before to an agent or a test.
  test "the head holds title, ⓘ, the period mark, the switch and ⋯ on one line" do
    doc = frame(item())
    [head] = Floki.find(doc, "#probe > .widget__head")

    order =
      head
      |> Floki.find(
        "h2, [data-role='section-info'], [data-role='widget-period'], [data-anatomy='switch'], [data-role='widget-menu']"
      )
      |> Enum.map(fn {tag, attrs, _} ->
        Enum.find_value(attrs, tag, fn
          {"data-role", role} -> role
          {"data-anatomy", part} -> part
          _ -> nil
        end)
      end)

    assert order == ["h2", "section-info", "widget-period", "switch", "widget-menu"]
    assert Floki.attribute(head, "h2", "title") == ["Tops und Flops"]

    [mark] = Floki.find(head, "[data-role='widget-period']")
    assert visible(mark) == "1Y"
    assert Floki.text(mark) == "follows · 1Y"
    assert Floki.attribute(mark, "title") == ["follows · 1Y"]

    # A kind that reads the period itself, so no „→ …“ follows the mark.
    pinned =
      frame(
        item(%{kind: "performance", period: "max", period_state: :pinned, period_label: "Max"})
      )

    [mark] = Floki.find(pinned, "[data-role='widget-period']")
    assert visible(mark) == "📌 Max"
    assert Floki.text(mark) =~ "own: Max"
  end

  # User story (board 07 ②, 6 and 7: „Warnung als Zeile“, „Fuß, eine
  # Zeile“):
  # As the operator reading a widget whose total leaves something out,
  # I want the warning as one line in the footer with a link, and the
  # footer itself one line — the scope at the left, one link named for its
  # target at the right —,
  # so that a warning never takes the widget's room as a box.
  #
  # Acceptance criteria:
  # - The frame's warning slot draws one line in the footer: the ⚠ glyph
  #   hidden from a screen reader, the words, a link; before the scope and
  #   the link.
  # - The footer holds the scope and one link; no box (no data note).
  test "a warning is one line in the footer, and the footer holds the scope and one link" do
    doc = frame(item(), warning: true)
    [foot] = Floki.find(doc, "#probe > .widget__foot")

    [warning] = Floki.find(foot, "[data-anatomy='warning']")
    assert elem(warning, 0) == "p"
    assert Floki.attribute(warning, ".widget-warning__glyph", "aria-hidden") == ["true"]
    assert visible(warning) == "⚠ 3 not in the total Details →"
    assert Floki.attribute(warning, "a", "href") == ["/portfolio"]

    assert Floki.find(foot, ".data-note") == []
    assert Floki.text(Floki.find(foot, "[data-role='widget-scope']")) == "View Everything"
    assert foot |> Floki.children() |> Enum.count(&match?({"a", _, _}, &1)) == 1

    assert Floki.find(frame(item()), "[data-anatomy='warning']") == []
  end

  # User story (board 07 ②, 2: „Eine Hauptzahl-Form“):
  # As the operator comparing two widgets' headline figures,
  # I want one form for every headline figure — a small label over the
  # figure, 28 px at S, 34 px as the hero of M and up, 24 px for a
  # secondary figure, a short muted line under it — coloured only when it
  # is a plus or a minus,
  # so that five headline sizes become three and a colour always means a
  # sign.
  #
  # Acceptance criteria:
  # - The label stands before the figure, the sub line after it.
  # - Its size class is one of S, M (hero) and secondary.
  # - A positive Decimal colours the figure as a gain, a negative one as a
  #   loss; zero, a total without a sign and nil carry no colour.
  test "the headline figure is label over figure, in three sizes, coloured only by its sign" do
    figure = fn size, sign ->
      assigns = %{size: size, sign: sign}

      rendered_to_string(~H"""
      <Widget.figure label="Total" size={@size} sign={@sign} role="probe-figure">
        88.307,02<:unit>EUR</:unit>
        <:sub>+8.0 % TTWROR · 1Y</:sub>
      </Widget.figure>
      """)
      |> parse()
    end

    doc = figure.(:s, nil)
    [node] = Floki.find(doc, "[data-anatomy='figure']")
    parts = node |> Floki.children() |> Enum.map(&(&1 |> Floki.attribute("class") |> classes()))

    assert parts == [
             ["widget-figure__label"],
             ["widget-figure__value", "num"],
             ["widget-figure__sub"]
           ]

    assert Floki.attribute(node, "data-role") == ["probe-figure"]
    assert Floki.text(Floki.find(node, ".widget-figure__unit")) == "EUR"

    for {size, class} <- [
          s: "widget-figure--s",
          m: "widget-figure--m",
          secondary: "widget-figure--secondary"
        ] do
      assert [_] = Floki.find(figure.(size, nil), "." <> class)
    end

    value = fn sign ->
      figure.(:s, sign)
      |> Floki.find(".widget-figure__value")
      |> Floki.attribute("class")
      |> classes()
    end

    assert value.(Decimal.new("8.0")) == ["widget-figure__value", "num", "is-positive"]
    assert value.(Decimal.new("-0.6")) == ["widget-figure__value", "num", "is-negative"]
    assert value.(Decimal.new("0")) == ["widget-figure__value", "num"]
    assert value.(nil) == ["widget-figure__value", "num"]
  end

  # User story (board 07 ②, 3 and 4: „Listen wie der Verkaufsrückblick“,
  # „Balken bei vergleichbaren Zahlen“; the owner on 2026-11-25: „das war
  # hilfreich“):
  # As the operator reading a list of positions,
  # I want each row as the sales review draws it — the name on one line
  # with its full name in a tooltip, the figure at the right and never
  # cut, a muted second line — and, where the figures are of one kind,
  # the contribution table's bar under the row: centre 0, a plus to the
  # right, a minus to the left, the largest listed filling 45 %,
  # so that I see at a glance which figure is large, on the phone too.
  #
  # Acceptance criteria:
  # - The name sits in one label carrying the full name as its tooltip,
  #   kept to one line; a row without a tooltip (a sentence) wraps. The
  #   figure and its sub line in the figure part.
  # - With a bar the row draws it under itself, aria-hidden: the largest
  #   at 45.0 %, half of it at 22.5 %, a minus on the left (`is-under`),
  #   a figure that reads zero with no fill.
  test "the list row: one-line name with its tooltip, the figure, and the bar under it" do
    row = fn value ->
      assigns = %{value: value}

      rendered_to_string(~H"""
      <Widget.row title="Allianz SE vinkulierte Namens-Aktien" bar_value={@value} bar_largest={Decimal.new("400")}>
        <:name>Allianz SE vinkulierte Namens-Aktien</:name>
        <:sub>sold 18.10.2026</:sub>
        <:figure>+31.4 %</:figure>
      </Widget.row>
      """)
      |> parse()
    end

    doc = row.(Decimal.new("400"))

    assert Floki.attribute(doc, ".widget-row__label", "title") == [
             "Allianz SE vinkulierte Namens-Aktien"
           ]

    assert Floki.text(Floki.find(doc, ".widget-row__label")) =~
             "Allianz SE vinkulierte Namens-Aktien"

    assert Floki.text(Floki.find(doc, ".widget-row__figure")) =~ "+31.4 %"
    assert Floki.text(Floki.find(doc, ".widget-row__sub")) =~ "sold 18.10.2026"

    assert Floki.attribute(doc, "[data-anatomy='bar']", "aria-hidden") == ["true"]
    assert Floki.attribute(doc, ".widget-bar__fill", "style") == ["width: 45.0%"]

    assert doc |> Floki.attribute(".widget-bar__fill", "class") |> classes() == [
             "widget-bar__fill",
             "is-over"
           ]

    half = row.(Decimal.new("-200"))
    assert Floki.attribute(half, ".widget-bar__fill", "style") == ["width: 22.5%"]

    assert half |> Floki.attribute(".widget-bar__fill", "class") |> classes() == [
             "widget-bar__fill",
             "is-under"
           ]

    assert [_] = Floki.find(row.(Decimal.new("0.001")), "[data-anatomy='bar']")
    assert Floki.find(row.(Decimal.new("0.001")), ".widget-bar__fill") == []
    assert Floki.find(row.(nil), "[data-anatomy='bar']") == []

    assert doc |> Floki.attribute(".widget-row__label", "class") |> classes() == [
             "widget-row__label",
             "is-one-line"
           ]

    # A row without a tooltip, a sentence, wraps: nothing of it is lost.
    assigns = %{}

    sentence =
      rendered_to_string(~H"""
      <Widget.row><:name>3 held bonds priced on two scales</:name></Widget.row>
      """)
      |> parse()

    assert sentence |> Floki.attribute(".widget-row__label", "class") |> classes() == [
             "widget-row__label"
           ]

    assert Floki.attribute(sentence, ".widget-row__label", "title") == []
  end

  # User story (the bar on its own, as a column's cell draws it):
  # As the operator reading a drift column,
  # I want the same bar where a list is a table, scaled to the largest
  # figure listed,
  # so that one bar means one thing wherever it stands.
  #
  # Acceptance criteria:
  # - `Widget.bar/1` draws the track with its fill at the row's share of
  #   45 %; a largest of zero draws no fill rather than dividing by it.
  test "the bar scales to the largest listed and survives a list of zeros" do
    bar = fn value, largest ->
      assigns = %{value: value, largest: largest}
      rendered_to_string(~H"<Widget.bar value={@value} largest={@largest} />") |> parse()
    end

    assert Floki.attribute(
             bar.(Decimal.new("1.5"), Decimal.new("3")),
             ".widget-bar__fill",
             "style"
           ) ==
             ["width: 22.5%"]

    assert Floki.find(bar.(Decimal.new("0"), Decimal.new("0")), ".widget-bar__fill") == []
  end
end
