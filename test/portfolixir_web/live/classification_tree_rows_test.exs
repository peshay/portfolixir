defmodule PortfolixirWeb.ClassificationTreeRowsTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures

  alias Portfolixir.Actor
  alias Portfolixir.Classifications

  # User story (#805, review C8 — variant A, picked 2026-09-14):
  # As a local portfolio maintainer reading a classification tree,
  # I want the figures of a category row to stand in named, right-aligned
  # columns under one head — Positions · Value · Cost · Result — with an
  # empty category showing "—" and the hidden-positions count as a muted
  # suffix of the name,
  # so that a row reads as a table line instead of a string of unlabelled
  # numbers, on the desktop and on the phone.
  #
  # Acceptance criteria:
  # - A column head above the tree names the figure columns; each row carries
  #   its count once (the duplicated count is gone) and its figures under the
  #   head.
  # - An empty category renders "—" in every figure column, never "0 0 0.00".
  #   Amended 2026-10-07 (the closing act of PR γ, the design critic's #5):
  #   its "Positions" count reads 0, because a count is always computable;
  #   "Value", "Cost" and "Result" keep the value slot's quiet dash.
  # - "+N without holdings" is a suffix inside the name cell.
  # - The result's basis is a basis line with an ⓘ; the unassigned notice
  #   stays a data note linking to the Unsorted node.

  defp tree do
    world = base_world()
    active = create_security!(name: "Active ETF", ticker: "ACT", currency: "EUR")
    sold = create_security!(name: "Sold ETF", ticker: "SLD", currency: "EUR")

    deposit!(world, "10000", ~D[2026-01-01])
    buy!(world, active, quantity: "10", price: "100", date: ~D[2026-01-02])
    buy!(world, sold, quantity: "5", price: "50", date: ~D[2026-01-02])
    sell!(world, sold, quantity: "5", price: "60", date: ~D[2026-01-03])
    put_quote!(active, ~D[2026-01-05], "110")

    {:ok, classification} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    {:ok, core} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Core"
      })

    {:ok, _empty} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Empty"
      })

    for security <- [active, sold] do
      {:ok, _} =
        Classifications.assign_security(Actor.owner_ui(), security.id, classification.id, core.id)
    end

    %{classification: classification}
  end

  defp text(nodes),
    do: nodes |> Floki.text(sep: " ") |> String.replace(~r/\s+/, " ") |> String.trim()

  defp row_for(doc, name) do
    doc
    |> Floki.find("summary.cat-summary")
    |> Enum.find(&(text(Floki.find(&1, ".cat-name")) =~ name)) ||
      flunk("no category row for #{name}")
  end

  test "the tree carries a column head and each row its figures under it", %{conn: conn} do
    %{classification: classification} = tree()

    {:ok, view, _html} = live(conn, "/classifications/#{classification.id}")
    render_async(view)
    doc = view |> render() |> Floki.parse_document!()

    assert text(Floki.find(doc, ~s([data-role="tree-head"]))) ==
             "Category Positions Value Cost Result"

    core = row_for(doc, "Core")
    # One count, under its head — the second, unlabelled copy is gone.
    assert Floki.find(core, ".cat-count") == []
    assert text(Floki.find(core, ~s([data-role="category-positions"]))) == "1"
    assert text(Floki.find(core, ~s([data-role="category-value"]))) == "1,100.00"
    assert text(Floki.find(core, ~s([data-role="category-invested"]))) == "1,000.00"
    result = text(Floki.find(core, ~s([data-role="category-result"])))
    assert result =~ "+100.00"
    assert result =~ "+10.0"
    # The hidden-positions count is a suffix of the name, not a seventh figure.
    assert text(Floki.find(core, ~s(.cat-name [data-role="without-holdings"]))) ==
             "+1 without holdings"

    empty = row_for(doc, "Empty")

    assert text(Floki.find(empty, ~s([data-role="category-positions"]))) == "0"

    for role <- ~w(category-value category-invested category-result) do
      assert text(Floki.find(empty, ~s([data-role="#{role}"] .cat-na))) == "—",
             "#{role} of an empty category is not the quiet em dash"
    end

    # The basis is a basis line with its ⓘ, not a paragraph.
    basis = Floki.find(doc, ~s([data-role="category-result-basis"]))
    assert text(basis) =~ "today's composition"
    assert [_] = Floki.find(basis, "details.metric-tooltip")
    assert text(basis) =~ "not a period return"

    # #1048 (pick J10.2 A): the line states the currency of every figure
    # under it, after the scope they read (#1091, pick J10 A: the view's
    # name, "Everything" with none picked), each "·" held to the word before
    # it by a no-break space; `text/1` joins the name's <bdi> with a space.
    assert text(basis) =~
             ~r/^View Everything ?\x{00A0}· in EUR\x{00A0}· Result: today's composition/u
  end

  # A value is a value only when every visible row carries one: while the
  # holdings load, every market value is nil, and a zero there would read as
  # "this category is worth nothing" rather than "not known yet".
  # User story (#1158, Sprint 21 γ6, board 06 ③, before/after):
  # As the operator opening a category on a 390 px phone,
  # I want each security row to fit the screen as a two-line row, the
  # Wealth Positions row's shape (UX-DR27),
  # so that a long name wraps instead of pushing the quantity and the value
  # past the screen's edge, where `.workspace-page` clips them.
  #
  # Acceptance criteria:
  # - The list of rows never wraps as a flex line (`flex-wrap: nowrap`): a
  #   wrapping line took the width of its widest row and caused the overflow.
  # - Under 560 px of the page the row is a grid: the name (600, wrapping)
  #   over "TICKER · CCY", the value (600) over the quantity with its unit
  #   word ("units" / "Stück", 12 px, muted) on the right.
  # - The unit word is in the markup and shown under 560 px only; the row
  #   stays the drag source (`draggable`, `data-drag-security`).
  test "a security row is a two-line row on a phone and stays the drag source", %{conn: conn} do
    %{classification: classification} = tree()

    {:ok, view, _html} = live(conn, "/classifications/#{classification.id}")
    render_async(view)
    doc = view |> render() |> Floki.parse_document!()

    [row] =
      doc
      |> Floki.find(~s(li.dnd-row[data-role="security-row"]))
      |> Enum.filter(&(text(Floki.find(&1, ".row-name")) == "Active ETF"))

    assert Floki.attribute(row, "draggable") == ["true"]
    assert [_id] = Floki.attribute(row, "data-drag-security")

    assert text(Floki.find(row, ~s([data-role="security-quantity"]))) == "10.00 units"

    assert text(Floki.find(row, ~s([data-role="security-quantity"] .row-quantity__unit))) ==
             "units"

    css = File.read!("priv/static/app.css")

    assert css =~ ~r/\n\.classifications-detail \.cat-securities \{[^}]*flex-wrap: nowrap;/
    assert css =~ ~r/\n\.dnd-row \.row-quantity__unit \{\s*display: none;\s*\}/

    phone =
      case Regex.run(
             ~r/@container classifications \(max-width: 560px\) \{\n  \/\* Security rows on two lines[^\n]*\n(.*?)\n\}\n/s,
             css
           ) do
        [_, body] -> body
        nil -> flunk("no 560 px container block for the two-line security row")
      end

    assert phone =~
             ~r/\.dnd-row \{[^}]*display: grid;[^}]*grid-template-columns: auto auto minmax\(0, 1fr\) auto;/

    assert phone =~ ~r/\.row-name \{[^}]*grid-column: 1 \/ 4;[^}]*white-space: normal;/
    assert phone =~ ~r/\.row-value \{[^}]*grid-column: 4;[^}]*grid-row: 1;/
    assert phone =~ ~r/\.row-quantity \{[^}]*grid-column: 4;[^}]*grid-row: 2;/
    assert phone =~ ~r/\.row-quantity__unit \{\s*display: inline;/
  end

  test "the value cell is a dash until the holdings land", %{conn: conn} do
    %{classification: classification} = tree()

    {:ok, view, html} = live(conn, "/classifications/#{classification.id}")

    refute html =~ "1,100.00"
    doc = Floki.parse_document!(html)
    assert text(Floki.find(row_for(doc, "Core"), ~s([data-role="category-value"]))) == "—"

    loaded = view |> render_async() |> Floki.parse_document!()

    assert text(Floki.find(row_for(loaded, "Core"), ~s([data-role="category-value"]))) ==
             "1,100.00"

    # The empty category keeps its dash after the load, not a zero.
    assert text(Floki.find(row_for(loaded, "Empty"), ~s([data-role="category-value"]))) == "—"
  end

  # Board 10 (ux-design-2026-10-04/10-category-results), rules ② and ③,
  # found while drawing J10.2 (#1048): the partial count "1/2" had no rule
  # and printed as a bare third line in the result's own size and colour;
  # it is the cell's sub-figure -- the percentage's size, muted, weight 500.
  # The note naming the left-out members keeps its distance from the basis
  # line above it.
  test "the partial count is the result's sub-figure, and the note keeps its distance" do
    css = File.read!("priv/static/app.css")

    assert css =~
             ~r/\.cat-result-partial\s*\{[^}]*font-size:\s*0\.72rem;[^}]*font-weight:\s*500;[^}]*color:\s*var\(--color-text-muted\)/s

    assert css =~
             ~r/\.classifications-detail \[data-role="category-result-excluded"\]\s*\{[^}]*margin-top:\s*0\.5rem/s
  end

  test "the head and the dashes are German where the page is", %{conn: conn} do
    %{classification: classification} = tree()

    {:ok, view, _html} = live(conn, "/classifications/#{classification.id}?locale=de")
    render_async(view)
    doc = view |> render() |> Floki.parse_document!()

    assert text(Floki.find(doc, ~s([data-role="tree-head"]))) ==
             "Kategorie Positionen Wert Einstand Ergebnis"

    assert text(Floki.find(row_for(doc, "Core"), ~s(.cat-name [data-role="without-holdings"]))) ==
             "+1 ohne Bestand"

    assert text(Floki.find(doc, ~s([data-role="category-result-basis"]))) =~
             ~r/^Ansicht Alles ?\x{00A0}· in EUR\x{00A0}· Ergebnis: heutige Zusammensetzung/u
  end

  # User story (#1368; plan R3, board 02 ①c):
  # As a local portfolio maintainer reading a category's cost and result,
  # I want a member without a quote counted at its last own trade price, as
  # Wealth counts it, and named as such on its row,
  # so that the category's figures agree with Wealth and I can see which
  # values stand at a trade price rather than a quote.
  #
  # Acceptance criteria:
  # - A trade-priced member's value names „zum Handelspreis“ / "at trade
  #   price"; a quoted member's does not.
  # - The category's cost and result count it; the excluded note keeps only
  #   the member no rule can value.
  # - The basis line names the price rule: "prices: the latest quote,
  #   without one the last own trade price".
  test "a trade-priced member names its price source and counts in cost and result",
       %{conn: conn} do
    world = base_world()
    quoted = create_security!(name: "Quoted ETF", ticker: "QTD", currency: "EUR")
    traded = create_security!(name: "Traded AG", ticker: "TRD", currency: "EUR")
    dark = create_security!(name: "Dark AG", ticker: "DRK", currency: "EUR")

    deposit!(world, "10000", ~D[2026-01-01])
    buy!(world, quoted, quantity: "10", price: "100", date: ~D[2026-01-02])
    buy!(world, traded, quantity: "10", price: "40", date: ~D[2026-01-02])
    buy!(world, traded, quantity: "10", price: "50", date: ~D[2026-02-02])
    deliver_untraded!(world, dark, "3")
    put_quote!(quoted, ~D[2026-03-02], "110")

    {:ok, classification} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    {:ok, core} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Core"
      })

    for security <- [quoted, traded, dark] do
      {:ok, _} =
        Classifications.assign_security(Actor.owner_ui(), security.id, classification.id, core.id)
    end

    {:ok, view, _html} = live(conn, "/classifications/#{classification.id}")
    render_async(view)
    doc = view |> render() |> Floki.parse_document!()

    value_of = fn doc, name ->
      doc
      |> Floki.find(~s(li[data-role="security-row"]))
      |> Enum.find(&(text(Floki.find(&1, ".row-name")) == name))
      |> Floki.find(~s([data-role="security-value"]))
    end

    # Traded AG: 20 at its last own trade price 50,00 = 1,000.00, cost 900.00.
    assert text(value_of.(doc, "Traded AG")) == "at trade price 1,000.00"
    assert [_] = Floki.find(value_of.(doc, "Traded AG"), "small.cell-note")
    assert text(value_of.(doc, "Quoted ETF")) == "1,100.00"

    # Cost 1,000.00 + 900.00, result +100.00 + +100.00: Wealth's figures.
    core_row = row_for(doc, "Core")
    assert text(Floki.find(core_row, ~s([data-role="category-invested"]))) == "1,900.00"
    assert text(Floki.find(core_row, ~s([data-role="category-result"]))) =~ "+200.00"

    excluded = text(Floki.find(doc, ~s([data-role="category-result-excluded"])))
    assert excluded =~ "Dark AG"
    refute excluded =~ "Traded AG"

    assert text(Floki.find(doc, ~s([data-role="category-result-basis"]))) =~
             " · prices: the latest quote, without one the last own trade price"

    {:ok, de, _html} = live(conn, "/classifications/#{classification.id}?locale=de")
    render_async(de)
    de_doc = de |> render() |> Floki.parse_document!()

    assert text(value_of.(de_doc, "Traded AG")) == "zum Handelspreis 1.000,00"

    assert text(Floki.find(de_doc, ~s([data-role="category-result-basis"]))) =~
             "Kurse: der neueste, ohne Kurs der letzte eigene Handelspreis"
  end
end
