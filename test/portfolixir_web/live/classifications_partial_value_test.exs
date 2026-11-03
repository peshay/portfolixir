defmodule PortfolixirWeb.ClassificationsPartialValueTest do
  # #1362's S2 line (board `ux-design-2026-11-03-sprint23-i1` ⑨): a
  # category whose members are not all priced shows the sum of the priced
  # ones and names how many it leaves out, as the category result's API
  # read does (ADR-0041 §4), instead of „—“. Every name is synthetic.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures

  alias Portfolixir.Actor
  alias Portfolixir.Classifications

  @auth {"authorization", "Bearer test-api-token"}

  defp category!(classification, name) do
    {:ok, category} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: classification.id,
        name: name
      })

    category
  end

  defp file!(security, classification, category) do
    {:ok, _} =
      Classifications.assign_security(
        Actor.owner_ui(),
        security.id,
        classification.id,
        category.id
      )
  end

  # "Bond": one priced member (10 at 100, quoted 150.37) and one delivered
  # in, never traded or quoted, so no rule values it. "Equity": one priced
  # member and two such. "Dormant": only one such. "Cash-like": every
  # member priced.
  defp tree! do
    world = base_world()
    deposit!(world, "100000", ~D[2026-01-01])

    {:ok, classification} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Asset mix"})

    bond = category!(classification, "Bond")
    equity = category!(classification, "Equity")
    dormant = category!(classification, "Dormant")
    cash_like = category!(classification, "Cash-like")

    priced = fn name, ticker, category, quantity, price, quote ->
      security = create_security!(name: name, ticker: ticker)
      buy!(world, security, quantity: quantity, price: price, date: ~D[2026-01-02])
      put_quote!(security, Date.utc_today(), quote)
      file!(security, classification, category)
    end

    unpriced = fn name, ticker, category ->
      security = create_security!(name: name, ticker: ticker)
      deliver_untraded!(world, security, "3")
      file!(security, classification, category)
    end

    priced.("Kestrel Treasury 2031", "KT31", bond, "10", "100", "150.37")
    unpriced.("Moorland Water Bond", "MWB", bond)

    priced.("Saltmarsh Mining plc", "SMP", equity, "7", "40", "41.25")
    unpriced.("Brightwater Tools AG", "BWT", equity)
    unpriced.("Fernhill Bonus AG", "FHB", equity)

    unpriced.("Larchmere Dormant AG", "LDA", dormant)

    priced.("Greywell Money Fund", "GMF", cash_like, "2", "500", "501.10")

    %{classification: classification, bond: bond}
  end

  defp squish(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()

  defp value_cell(doc, name) do
    doc
    |> Floki.find("summary.cat-summary")
    |> Enum.find(&(squish(Floki.text(Floki.find(&1, ".cat-name__text"))) == name))
    |> Kernel.||(flunk("no category row for #{name}"))
    |> Floki.find(~s([data-role="category-value"]))
  end

  # The figure without its cell note, as the page prints it.
  defp figure(cell), do: cell |> Floki.filter_out(".cell-note") |> Floki.text() |> squish()
  defp cell_note(cell), do: cell |> Floki.find(".cell-note") |> Floki.text() |> squish()

  # User story (#1362's S2 line; Sprint 23's UAT persona on #1377):
  # As the operator reading a category's value beside the agent's answer,
  # I want the value of a category whose members are not all priced to be
  # the sum of the priced ones, with how many it leaves out beneath,
  # so that the screen and the category result the agent reads state the
  # same figure, and a dash means only that nothing is priced.
  #
  # Acceptance criteria:
  # - "Bond" reads the sum of its priced member, 1,503.70, the exact
  #   `current_value` the category result's read
  #   (`GET /api/v1/category-results`) reports for it, with "without 1
  #   position" („ohne 1 Position“) beneath it in `.cell-note`.
  # - "Equity" reads 288.75 with "without 2 positions" („ohne 2
  #   Positionen“).
  # - A category with no priced member keeps the dash and no note; a
  #   category whose every member is priced has no note.
  # - The note sits in the value cell in the cell-note's muted voice
  #   (`.cat-value .cell-note`, display: block).
  test "a category shows its priced members' sum and names what it leaves out", %{conn: conn} do
    %{classification: classification, bond: bond} = tree!()

    {:ok, view, _html} = live(conn, "/classifications/#{classification.id}")
    doc = view |> render_async() |> Floki.parse_document!()

    bond_cell = value_cell(doc, "Bond")
    assert figure(bond_cell) == "1,503.70"
    assert cell_note(bond_cell) == "without 1 position"

    # Exact parity with the category result's read for the same category.
    api =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header(elem(@auth, 0), elem(@auth, 1))
      |> get("/api/v1/category-results?classification_id=#{classification.id}")
      |> json_response(200)
      |> get_in(["data", "categories"])
      |> Enum.find(&(&1["category_id"] == bond.id))

    assert api["covered_count"] == 1
    assert api["member_count"] == 2

    assert Decimal.equal?(
             Decimal.new(String.replace(figure(bond_cell), ",", "")),
             Decimal.new(api["current_value"])
           )

    assert Decimal.equal?(Decimal.new(api["current_value"]), Decimal.new("1503.70"))

    equity_cell = value_cell(doc, "Equity")
    assert figure(equity_cell) == "288.75"
    assert cell_note(equity_cell) == "without 2 positions"

    dormant_cell = value_cell(doc, "Dormant")
    assert figure(dormant_cell) == "—"
    assert Floki.find(dormant_cell, ".cell-note") == []

    cash_cell = value_cell(doc, "Cash-like")
    assert figure(cash_cell) == "1,002.20"
    assert Floki.find(cash_cell, ".cell-note") == []

    {:ok, de, _html} = live(conn, "/classifications/#{classification.id}?locale=de")
    de_doc = de |> render_async() |> Floki.parse_document!()

    assert figure(value_cell(de_doc, "Bond")) == "1.503,70"
    assert cell_note(value_cell(de_doc, "Bond")) == "ohne 1 Position"
    assert cell_note(value_cell(de_doc, "Equity")) == "ohne 2 Positionen"

    css = File.read!("priv/static/app.css")

    assert css =~
             ~r/\n\.cat-value \.cell-note \{[^}]*display: block;[^}]*color: var\(--color-text-muted\);/
  end
end
