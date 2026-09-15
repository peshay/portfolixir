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

    for role <- ~w(category-positions category-value category-invested category-result) do
      assert text(Floki.find(empty, ~s([data-role="#{role}"]))) == "—",
             "#{role} of an empty category is not an em dash"
    end

    # The basis is a basis line with its ⓘ, not a paragraph.
    basis = Floki.find(doc, ~s([data-role="category-result-basis"]))
    assert text(basis) =~ "today's composition"
    assert [_] = Floki.find(basis, "details.metric-tooltip")
    assert text(basis) =~ "not a period return"
  end

  # A value is a value only when every visible row carries one: while the
  # holdings load, every market value is nil, and a zero there would read as
  # "this category is worth nothing" rather than "not known yet".
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

  test "the head and the dashes are German where the page is", %{conn: conn} do
    %{classification: classification} = tree()

    {:ok, view, _html} = live(conn, "/classifications/#{classification.id}?locale=de")
    render_async(view)
    doc = view |> render() |> Floki.parse_document!()

    assert text(Floki.find(doc, ~s([data-role="tree-head"]))) ==
             "Kategorie Positionen Wert Einstand Ergebnis"

    assert text(Floki.find(row_for(doc, "Core"), ~s(.cat-name [data-role="without-holdings"]))) ==
             "+1 ohne Bestand"
  end
end
