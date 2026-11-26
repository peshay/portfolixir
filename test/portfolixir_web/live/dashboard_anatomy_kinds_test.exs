defmodule PortfolixirWeb.DashboardAnatomyKindsTest do
  # Every kind on the widget anatomy (Sprint 32 L2 and L3; board
  # ux-design-2026-11-25-sprint32/07 ① findings 1 to 10 and ③; board 09;
  # D-12, D-13; DESIGN.md → "The widget anatomy and the one surface").
  # One test per finding, kind by kind, on the review seed
  # (priv/demo/finding_surfaces_seed.exs), which fills every kind: the
  # markup each kind draws in its wide form. What the browser makes of it
  # (one line, no box, no blank band, no row cut) is measured by
  # test/browser/widget_anatomy_test.exs. The figures each kind draws are
  # compared with their routes by the existing per-kind tests, unchanged.
  # Synthetic data only.
  #
  # async: false, group: :dashboards -- the review seed and the stored
  # dashboards share the count lock (LockTable row 30).
  use PortfolixirWeb.ConnCase, async: false, group: :dashboards

  import ExUnit.CaptureIO
  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Dashboards

  @seed "priv/demo/finding_surfaces_seed.exs"

  setup do
    conflicts = Code.get_compiler_option(:ignore_module_conflict)
    Code.put_compiler_option(:ignore_module_conflict, true)

    try do
      capture_io(fn -> Code.eval_file(@seed) end)
    after
      Code.put_compiler_option(:ignore_module_conflict, conflicts)
    end

    :ok
  end

  # The dashboard holding `items` ({kind, size}), one under the other,
  # rendered in German with every read landed.
  defp board(conn, items) do
    {layout, _row} =
      Enum.map_reduce(items, 1, fn {kind, size}, row ->
        {:ok, {_w, h}} = Dashboards.Widgets.dimensions(size)
        {%{"kind" => kind, "size" => size, "col" => 1, "row" => row}, row + h}
      end)

    {:ok, dashboard} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Anatomie", "layout" => layout})

    {:ok, view, _html} = live(conn, "/dashboards/#{dashboard.id}?locale=de")
    render_async(view)
    {view, view |> render() |> Floki.parse_document!()}
  end

  defp widget(doc, kind, size),
    do: Floki.find(doc, "section[data-widget-kind='#{kind}'][data-size='#{size}']")

  # The widget's body as the eye reads it: its wide form and what both
  # forms share, without the head, the ⓘ and the footer.
  defp body(widget) do
    widget
    |> Floki.filter_out(".widget__head")
    |> Floki.filter_out(".widget__foot")
    |> Floki.filter_out("[data-form='compact']")
  end

  defp text(nodes),
    do: nodes |> Floki.text(sep: " ") |> String.replace(~r/\s+/u, " ") |> String.trim()

  defp info(widget), do: text(Floki.find(widget, ".widget__head [data-role='section-info']"))

  # User story (board 07 ① 3, 4, 7; ③; board 01 ④):
  # As the operator reading „Gesamtwert“,
  # I want its figure in the anatomy's one form at every size — no value
  # card inside the widget — and what the total leaves out as one line in
  # its one footer,
  # so that the figure leads and the warning does not push it down.
  #
  # Acceptance criteria:
  # - S, M and L: no `.stat` card inside the widget; the excluded note
  #   (L) or line (S, M), with its status region, stands in the footer; one
  #   footer.
  # - S and L: the total is the anatomy's headline figure, 28 px at S, the
  #   34 px hero at L.
  test "„Gesamtwert“: no card in the card, its warning a line in its one footer", %{conn: conn} do
    {_view, doc} = board(conn, [{"total_value", "S"}, {"total_value", "M"}, {"total_value", "L"}])

    for size <- ~w(S M L) do
      w = widget(doc, "total_value", size)
      assert Floki.find(w, ".stat") == [], "#{size} draws a card inside the widget"
      assert length(Floki.find(w, ".widget__foot")) == 1, "#{size} draws more than one footer"

      assert [_status] = Floki.find(w, ".widget__foot [id^='dashboard-wealth-card-status']"),
             "#{size}: the status region is not in the footer"

      assert Floki.find(body(w), "[data-role^='wealth-card-excluded']") == [],
             "#{size}: the excluded note stands in the body"
    end

    assert [_] =
             Floki.find(
               widget(doc, "total_value", "S"),
               "#dashboard-wealth-card .widget-figure--s"
             )

    assert [_] =
             Floki.find(
               widget(doc, "total_value", "L"),
               "#dashboard-wealth-card-3 .widget-figure--m"
             )
  end

  # User story (board 07 ① 3; ③ „Datenqualität M: die Liste von S mit
  # Zählern und je einer erklärenden Zeile statt des roten Fließtexts“):
  # As the operator reading „Datenqualität“ at L,
  # I want each finding as a row — its counted sentence as the link, what
  # it does to the total under it — instead of one red paragraph of links,
  # so that I can read the findings one by one.
  #
  # Acceptance criteria:
  # - No data note in the widget; `#dashboard-dq-line` is a list, one row
  #   per finding, each with its link (`data-role`) and, where the finding
  #   has one, its effect line (`data-effect-of`).
  test "„Datenqualität“ at L: a list of findings, not a red paragraph", %{conn: conn} do
    {_view, doc} = board(conn, [{"data_quality", "L"}])
    w = widget(doc, "data_quality", "L")

    assert Floki.find(w, ".data-note") == []
    assert [{"ul", _, _} = list] = Floki.find(w, "#dashboard-dq-line")
    rows = Floki.find(list, "li.widget-findings__row")
    assert length(rows) >= 3

    for row <- rows do
      assert [_link] = Floki.find(row, "a[data-role^='dq-']")
    end
  end

  # User story (board 07 ① 2; I1's rule):
  # As the operator reading a widget,
  # I want its method and its scope sentences behind ⓘ, at most one short
  # line in the body,
  # so that the body holds the figures.
  #
  # Acceptance criteria:
  # - „Tops und Flops“: the basis line stands in the ⓘ, not in the body.
  # - „Abseits des Ziels“ L: the rule („±5 pp oder mehr …“) in the ⓘ, the
  #   body only the view and the plan.
  # - „Verkaufsrückblick“: its basis sentence in the ⓘ.
  # - „Bitcoin-Zyklus“: „… keine Prognose“ in the ⓘ, not as a paragraph.
  # - „Allokation und Drift“: its plan line in the footer.
  # - „Crash-Chart“: the title is the kind's alone; the benchmark is a line
  #   under it, so the head is never cut for a long fund name.
  test "the basis sentences stand behind ⓘ, the body keeps the figures", %{conn: conn} do
    {_view, doc} =
      board(conn, [
        {"movers", "L"},
        {"off_target", "L"},
        {"sale_review", "L"},
        {"bitcoin_cycle", "L"},
        {"allocation_drift", "L"},
        {"crash_chart", "L"}
      ])

    movers = widget(doc, "movers", "L")
    assert Floki.find(body(movers), "[data-role='movers-basis']") == []
    assert info(movers) =~ "Schlusskurs"

    off = widget(doc, "off_target", "L")
    refute text(body(off)) =~ "oder mehr"
    assert info(off) =~ "oder mehr"

    trades = widget(doc, "sale_review", "L")
    assert Floki.find(body(trades), "[data-role='trades-card-basis']") == []
    assert info(trades) =~ "FIFO"

    cycle = widget(doc, "bitcoin_cycle", "L")
    assert Floki.find(body(cycle), ".cycle-card__basis") == []
    assert info(cycle) =~ "keine Prognose"

    drift = widget(doc, "allocation_drift", "L")
    assert Floki.find(body(drift), "[data-role='allocation-drift-basis']") == []
    assert [_] = Floki.find(drift, ".widget__foot [data-role='allocation-drift-basis']")

    chart = widget(doc, "crash_chart", "L")
    assert text(Floki.find(chart, ".widget__head h2")) == "Crash-Chart"
    assert text(Floki.find(chart, "[data-role='crash-chart-benchmark']")) =~ "Vanguard"
  end

  # User story (board 07 ① 3; ③ „Verkaufsrückblick: der Warnkasten wird
  # eine Fußzeile“):
  # As the operator reading the sales review,
  # I want what it leaves out as one line in its footer,
  # so that the list stands where the widget starts.
  #
  # Acceptance criteria:
  # - The excluded note stands in the footer, none in the body.
  test "„Verkaufsrückblick“: its warning a line in the footer", %{conn: conn} do
    {_view, doc} = board(conn, [{"sale_review", "L"}, {"sale_review", "row"}])

    for size <- ~w(L row) do
      w = widget(doc, "sale_review", size)
      assert Floki.find(body(w), "[data-role='trades-card-excluded']") == []
      assert [_] = Floki.find(w, ".widget__foot [data-role='trades-card-excluded']")
    end
  end

  # User story (board 07 ① 5):
  # As the operator comparing headline figures across widgets,
  # I want each in the one form, at the size its family gives,
  # so that five sizes of headline become three.
  #
  # Acceptance criteria:
  # - „Wertentwicklung“ S and L, „Snapshots“ S and M and „Abseits des
  #   Ziels“ S draw their headline as the anatomy's figure: S 28 px, the
  #   hero of M and up 34 px.
  test "the headline figures are the anatomy's form, sized by family", %{conn: conn} do
    {_view, doc} =
      board(conn, [
        {"performance", "S"},
        {"performance", "L"},
        {"snapshots", "S"},
        {"snapshots", "M"},
        {"off_target", "S"}
      ])

    for {kind, size, class} <- [
          {"performance", "S", "widget-figure--s"},
          {"performance", "L", "widget-figure--m"},
          {"snapshots", "S", "widget-figure--s"},
          {"snapshots", "M", "widget-figure--m"},
          {"off_target", "S", "widget-figure--s"}
        ] do
      assert [_] = Floki.find(body(widget(doc, kind, size)), "[data-anatomy='figure']." <> class),
             "#{kind} #{size} draws no #{class}"
    end
  end

  # User story (board 07 ① 8; ③ „Allokation und Drift: ‚≈ zum Soll‘ als
  # Spalte“):
  # As the operator reading the drift table,
  # I want the amount that would close each gap in its own column beside
  # the drift,
  # so that I read it in the row it belongs to, not in a paragraph.
  #
  # Acceptance criteria:
  # - The table has a fifth column „≈ zum Soll“; each top-level row off
  #   target carries its amount there (`drift-arithmetic`); no paragraph
  #   lists them under the table.
  test "„Allokation und Drift“: „≈ zum Soll“ as a column", %{conn: conn} do
    {_view, doc} = board(conn, [{"allocation_drift", "L"}])
    w = widget(doc, "allocation_drift", "L")

    heads = w |> Floki.find("[data-role='allocation-drift-table'] thead th") |> Enum.map(&text/1)
    assert List.last(heads) == "≈ zum Soll"

    cells = Floki.find(w, "[data-role='allocation-drift-row'] td [data-role='drift-arithmetic']")
    assert cells != []
    assert Floki.find(w, "p[data-role='allocation-drift-arithmetic']") == []
  end

  # User story (board 07 ① 9, 10; ③ „Tops und Flops M: der Schalter im
  # Kopf, Balken in beiden Spalten und in beiden Ansichten“; the owner on
  # 2026-11-25: „das war hilfreich“):
  # As the operator reading a ranking,
  # I want the widget's own switch in its head, and the bar under every
  # row of both rankings,
  # so that the switch is where every widget has it and the bars show
  # which figure is large.
  #
  # Acceptance criteria:
  # - „Tops und Flops“, „Crashes im Vergleich“ and „Erholer nach Crashes“:
  #   the switch in the head (`[data-anatomy=switch]`), none in the body.
  # - „Tops und Flops“ L: every row of the price return and of the
  #   contribution, highest and lowest, carries the bar.
  test "the switches stand in the head, and every ranking row carries its bar", %{conn: conn} do
    {_view, doc} = board(conn, [{"movers", "L"}, {"crashes", "L"}, {"rebounders", "L"}])

    for {kind, role} <- [
          {"movers", "movers-switch"},
          {"crashes", "crashes-universe"},
          {"rebounders", "rebounders-universe"}
        ] do
      w = widget(doc, kind, "L")

      assert [_] = Floki.find(w, ".widget__head [data-anatomy='switch'] [data-role='#{role}']"),
             kind

      assert Floki.find(body(w), "[data-role='#{role}']") == [], kind
    end

    movers = widget(doc, "movers", "L")

    for side <- ~w(movers-return movers-contribution) do
      rows =
        Floki.find(movers, "[data-form='wide'] [data-role='#{side}'] [data-role='movers-row']")

      assert rows != [], side

      for row <- rows do
        assert [_] = Floki.find(row, "[data-anatomy='bar']"), side
      end
    end
  end

  # User story (board 07 ① 6; board 09; L3: „Tops und Flops S a list of
  # four that fits its tile“):
  # As the operator who put „Tops und Flops“ at S,
  # I want a list of four — the two highest and the two lowest price
  # returns — each with its bar, and no explanation or switch,
  # so that the small tile shows the ranking, not a cut paragraph.
  #
  # Acceptance criteria:
  # - At S the wide form draws four rows, each with its bar; no switch and
  #   no basis line in the widget's body or head.
  test "„Tops und Flops“ at S: a list of four with bars", %{conn: conn} do
    {_view, doc} = board(conn, [{"movers", "S"}])
    w = widget(doc, "movers", "S")

    rows = Floki.find(w, "[data-form='wide'] [data-role='movers-row']")
    assert length(rows) == 4
    for row <- rows, do: assert([_] = Floki.find(row, "[data-anatomy='bar']"))
    assert Floki.find(w, "[data-role='movers-switch']") == []
    assert Floki.find(body(w), "[data-role='movers-basis']") == []
  end

  # User story (board 07 ③; board 09 ③; L3: „Bitcoin-Zyklus XL draws the
  # existing cycle chart“):
  # As the operator who put „Bitcoin-Zyklus“ at XL,
  # I want the security's chart with its cycle bands, as its page draws it
  # on the range „Zyklus“,
  # so that the large tile shows what the cycles look like, not the L card
  # with space.
  #
  # Acceptance criteria:
  # - At XL the widget draws the shared chart (`svg.price-chart`) with the
  #   cycle timeline beside the card's events.
  test "„Bitcoin-Zyklus“ at XL draws the cycle chart", %{conn: conn} do
    {_view, doc} = board(conn, [{"bitcoin_cycle", "XL"}, {"bitcoin_cycle", "L"}])

    assert [_] =
             Floki.find(
               widget(doc, "bitcoin_cycle", "XL"),
               "[data-role='cycle-widget-chart'] svg"
             )

    assert Floki.find(widget(doc, "bitcoin_cycle", "L"), "[data-role='cycle-widget-chart']") == []
  end

  # User story (board 07 ① 1, 6; L3: each kind shows what fits its tile):
  # As the operator reading the small widgets on the desk,
  # I want each S title whole on its head's line and each S body showing
  # only what fits,
  # so that no S widget is cut — not its title, not its last row.
  #
  # Acceptance criteria:
  # - „Wertentwicklung“ at S is titled „Rendite“, the figure it draws
  #   (the TTWROR); L and XL keep their titles.
  # - „Fällig“ at S says its scope in the footer, so its two dated rows
  #   fit the tile.
  test "the S widgets keep their titles whole and their rows inside the tile", %{conn: conn} do
    {_view, doc} = board(conn, [{"performance", "S"}, {"performance", "L"}, {"due", "S"}])

    assert text(Floki.find(widget(doc, "performance", "S"), ".widget__head h2")) == "Rendite"

    assert text(Floki.find(widget(doc, "performance", "L"), ".widget__head h2")) ==
             "Wertentwicklung"

    due = widget(doc, "due", "S")
    assert Floki.find(body(due), "[data-role='upcoming-basis-short']") == []
    assert text(Floki.find(due, ".widget__foot [data-role='upcoming-basis-short']")) =~ "30 Tage"
  end

  # User story (board 07 ① 7: „Neun verschiedene Linktexte“):
  # As the operator following a widget's footer link,
  # I want one link per widget, named for the page it opens, the same at
  # every size,
  # so that the same target never reads three ways.
  #
  # Acceptance criteria:
  # - Every widget that leads to Wealth says „In Vermögen →“ („Gesamtwert“
  #   at S, M and L, „Abseits des Ziels“ at S and L, „Tops und Flops“ at
  #   S and L); „Datenqualität“ says „Wertpapiere prüfen →“ at S and L.
  test "one footer link per target, the same at every size", %{conn: conn} do
    {_view, doc} =
      board(conn, [
        {"total_value", "S"},
        {"total_value", "M"},
        {"total_value", "L"},
        {"off_target", "S"},
        {"off_target", "L"},
        {"movers", "S"},
        {"movers", "L"},
        {"data_quality", "S"},
        {"data_quality", "L"}
      ])

    link = fn kind, size -> text(Floki.find(widget(doc, kind, size), ".widget__foot > a")) end

    for {kind, size} <- [
          {"total_value", "S"},
          {"total_value", "M"},
          {"total_value", "L"},
          {"off_target", "S"},
          {"off_target", "L"},
          {"movers", "S"},
          {"movers", "L"}
        ] do
      assert link.(kind, size) == "In Vermögen →", "#{kind} #{size}"
    end

    assert link.("data_quality", "S") == "Wertpapiere prüfen →"
    assert link.("data_quality", "L") == "Wertpapiere prüfen →"
  end
end
