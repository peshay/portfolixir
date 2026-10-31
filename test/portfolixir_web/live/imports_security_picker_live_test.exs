defmodule PortfolixirWeb.ImportsSecurityPickerLiveTest do
  # Board ux-design-2026-10-27/02-imports-mapping, Q1 B (security review
  # 2026-10-12, H45; Sprint 21 γ7): the preview's security mapping without
  # the catalog in every row. A plain creation reads as its answer, "Created
  # as new: …", and "Map elsewhere…" opens the merge dialog's search field
  # and its radio cards inside the row, loaded on demand; a decision row's
  # candidates are its cards. No row renders the catalog. The bound itself
  # is pinned in `PortfolixirWeb.ImportsSecurityMappingBoundTest`. Every
  # name, amount and identifier is synthetic.
  use PortfolixirWeb.ConnCase

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Imports
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios
  alias Portfolixir.Repo

  @sorrel %{"name" => "Sorrel Bay Foods AG", "currency" => "EUR"}
  @holding %{"name" => "Larkspur Rail Holding AG", "isin" => "DE0007654329", "currency" => "EUR"}
  @brightwater %{"name" => "Brightwater Utilities SE", "wkn" => "BWU001", "currency" => "EUR"}

  setup do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "PP Import Target",
        base_currency_code: "EUR"
      })

    larkspur = security!(%{name: "Larkspur Rail AG", isin: "DE0001234565"})
    bright_a = security!(%{name: "Brightwater Utilities SE", wkn: "BWU001", isin: nil})
    bright_b = security!(%{name: "Brightwater Utilities SE", wkn: "BWU001", ticker_symbol: nil})
    for i <- 1..12, do: security!(%{name: "Catalog Security #{i}"})

    %{portfolio: portfolio, larkspur: larkspur, bright: [bright_a, bright_b]}
  end

  # User story (H45, Sprint 21 γ7, Q1 B): As the operator reviewing the
  # securities a file creates, I want each plain creation to read as its
  # answer with one control to map it elsewhere, and nothing suggested until
  # I search, so that the preview carries no catalog list per row and the
  # common case reads at a glance.
  #
  # Acceptance criteria:
  # - A plain creation reads "Created as new: Sorrel Bay Foods AG" with the
  #   button "Map elsewhere…"; its choice rides as the hidden input
  #   `security[<key>][choice]` = "create". No `<select>` and no `<option>`
  #   anywhere in the securities step.
  # - "Map elsewhere…" opens, inside the row, a group labelled "Map
  #   elsewhere: Larkspur Rail Holding AG": the search field ("Search
  #   securities: name, ISIN, WKN or ticker", placeholder "Name, ISIN, WKN
  #   or ticker"), the cards' legend "Map to" with the one card "+ Create
  #   new: Larkspur Rail Holding AG", checked, and the basis line "The
  #   catalog is searched by name, ISIN, WKN and ticker; nothing is
  #   suggested."
  # - A search lists its hits as cards after the creation: "Larkspur Rail
  #   AG", "EUR · DE0001234565 · created <date>", "0 bookings"; a search
  #   with no hit says "No security matches."
  # - A pick closes the picker into "Mapped to: Larkspur Rail AG · EUR ·
  #   DE0001234565" with "Change…", the ISIN change is offered as before,
  #   and the summary counts one new security, not two.
  # - Confirmed, the holding's purchase is booked on Larkspur Rail AG and no
  #   security named "Larkspur Rail Holding AG" is created.
  test "a creation reads as its answer, and the remap opens a search on ask", %{
    conn: conn,
    larkspur: larkspur
  } do
    {:ok, view, _html} = live(conn, "/imports")
    upload(view, [purchase(@sorrel, "2026-01-15"), purchase(@holding, "2026-01-16")])

    mapping = "#import-security-mapping"
    refute has_element?(view, mapping <> " select")
    refute has_element?(view, mapping <> " option")

    sorrel = row(view, "Sorrel Bay Foods AG")

    assert text(view, sorrel <> " .mapping-target__current") =~
             "Created as new: Sorrel Bay Foods AG"

    assert has_element?(view, sorrel <> " button.link-button", "Map elsewhere…")

    assert has_element?(
             view,
             sorrel <>
               ~s( input[type="hidden"][name="security[#{key("Sorrel Bay Foods AG")}][choice]"][value="create"])
           )

    assert text(view, mapping <> " [data-role='plain-creates'] summary") ==
             "2 new securities will be created"

    holding = row(view, "Larkspur Rail Holding AG")
    view |> element(holding <> " button.link-button", "Map elsewhere…") |> render_click()

    picker =
      holding <>
        " .mapping-remap[role='group'][aria-label='Map elsewhere: Larkspur Rail Holding AG']"

    assert has_element?(view, picker)

    assert has_element?(
             view,
             picker <>
               " .search-field input[type='search'][aria-label='Search securities: name, ISIN, WKN or ticker'][placeholder='Name, ISIN, WKN or ticker']"
           )

    assert text(view, picker <> " .merge-targets legend") == "Map to"

    assert texts(view, picker <> " .merge-target .merge-target__name b") == [
             "+ Create new: Larkspur Rail Holding AG"
           ]

    assert has_element?(
             view,
             picker <> " .merge-target input[type='radio'][value='create'][checked]"
           )

    assert text(view, picker <> " .mapping-remap__basis") ==
             "The catalog is searched by name, ISIN, WKN and ticker; nothing is suggested."

    search(view, "Larkspur Rail Holding AG", "Lark")

    assert texts(view, picker <> " .merge-target .merge-target__name b") == [
             "+ Create new: Larkspur Rail Holding AG",
             "Larkspur Rail AG"
           ]

    created = PortfolixirWeb.Format.date(DateTime.to_date(larkspur.inserted_at))

    assert text(view, picker <> " .merge-target[data-id='#{larkspur.id}'] small") ==
             "EUR · DE0001234565 · created #{created}"

    assert text(view, picker <> " .merge-target[data-id='#{larkspur.id}'] .merge-target__balance") ==
             "0 bookings"

    search(view, "Larkspur Rail Holding AG", "Nothing like it")
    assert has_element?(view, picker <> " .mapping-remap__empty", "No security matches.")

    search(view, "Larkspur Rail Holding AG", "Lark")
    choose(view, "Larkspur Rail Holding AG", "existing:#{larkspur.id}")

    refute has_element?(view, holding <> " .mapping-remap")

    assert text(view, holding <> " .mapping-target__current") ==
             "Mapped to: Larkspur Rail AG · EUR · DE0001234565 Change…"

    assert has_element?(view, holding <> " button.link-button", "Change…")

    assert has_element?(
             view,
             holding <>
               ~s( input[type="checkbox"][name="security[#{key("Larkspur Rail Holding AG")}][record_isin_change]"])
           )

    assert text(view, mapping <> " [data-role='plain-creates'] summary") ==
             "1 new security will be created"

    view |> element("form#pp-import-apply") |> render_submit()
    assert render_async(view, 2_000) =~ "Created transactions: 2"

    assert Repo.one(
             from(t in Transaction, where: t.security_id == ^larkspur.id, select: count(t.id))
           ) == 1

    refute Enum.any?(Catalog.list_securities(), &(&1.name == "Larkspur Rail Holding AG"))
  end

  # User story (H45, Sprint 21 γ7, Q1 B; board 02, found while drawing 2):
  # As the operator asked to decide between securities that share an
  # identifier, I want the candidates themselves as the choices, with
  # "+ Create new" beside them and a search for the rare case that is
  # neither, so that the row answers its own question without listing the
  # catalog.
  #
  # Acceptance criteria:
  # - The decision row shows its two candidates and "+ Create new:
  #   Brightwater Utilities SE" as radio cards, none checked, and the button
  #   "Search for another security…"; "Decide…" is gone.
  # - The still-to-map hint names the security until a card is chosen; a
  #   chosen candidate unlocks the confirm.
  # - "Search for another security…" opens the search inside the row.
  test "a decision row's candidates are its cards, and a search is one ask away", %{
    conn: conn,
    bright: [bright_a, bright_b]
  } do
    {:ok, view, _html} = live(conn, "/imports")
    upload(view, [purchase(@sorrel, "2026-01-15"), purchase(@brightwater, "2026-01-17")])

    decision = "#import-security-mapping [data-role='security-decision']"

    assert texts(view, decision <> " .merge-target .merge-target__name b") == [
             "Brightwater Utilities SE",
             "Brightwater Utilities SE",
             "+ Create new: Brightwater Utilities SE"
           ]

    assert has_element?(view, decision <> " .merge-target[data-id='#{bright_a.id}']")
    assert has_element?(view, decision <> " .merge-target[data-id='#{bright_b.id}']")
    refute has_element?(view, decision <> " input[type='radio'][checked]")
    refute render(view) =~ "Decide…"
    assert has_element?(view, decision <> " button.link-button", "Search for another security…")

    assert view |> element("#import-missing-hint") |> render() =~
             "security: Brightwater Utilities SE"

    choose(view, "Brightwater Utilities SE", "existing:#{bright_a.id}")

    assert has_element?(
             view,
             decision <> " input[type='radio'][value='existing:#{bright_a.id}'][checked]"
           )

    refute has_element?(view, "#pp-import-confirm[disabled]")

    view
    |> element(decision <> " button.link-button", "Search for another security…")
    |> render_click()

    assert has_element?(view, decision <> " .mapping-remap .search-field input[type='search']")
  end

  # --- the file ----------------------------------------------------------------

  defp purchase(security, date) do
    %{
      "type" => "PURCHASE",
      "account" => "Test-Cash",
      "portfolio" => "Test-Depot",
      "date" => date,
      "time" => "10:00",
      "currency" => "EUR",
      "amount" => Jason.Fragment.new("100.00"),
      "shares" => Jason.Fragment.new("10"),
      "security" => security
    }
  end

  defp upload(view, rows) do
    body = Jason.encode!(%{"version" => 1, "transactions" => rows})

    view
    |> file_input("#pp-import-form", :pp_file, [
      %{
        name: "synthetic.json",
        content: body,
        type: "application/json",
        last_modified: 1_700_000_000_000
      }
    ])
    |> render_upload("synthetic.json")

    render_async(view)
  end

  # --- the page ----------------------------------------------------------------

  # The resolution key of the file's security named `name`.
  defp key(name) do
    {:ok, preview} =
      Imports.parse_portfolio_performance(
        Jason.encode!(%{
          "version" => 1,
          "transactions" => [
            purchase(
              Enum.find([@sorrel, @holding, @brightwater], &(&1["name"] == name)),
              "2026-01-15"
            )
          ]
        }),
        filename: "key.json"
      )

    %{resolutions: [res]} = Imports.resolve_securities(preview)
    res.key
  end

  defp row(_view, name), do: "#import-security-mapping [data-security-row='#{key(name)}']"

  defp search(view, name, query) do
    view
    |> element("form#pp-import-apply")
    |> render_change(%{"remap" => %{key(name) => %{"q" => query}}})
  end

  defp choose(view, name, choice) do
    view
    |> element("form#pp-import-apply")
    |> render_change(%{"security" => %{key(name) => %{"choice" => choice}}})
  end

  defp text(view, selector) do
    view
    |> element(selector)
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.text(sep: " ")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp texts(view, selector) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find(selector)
    |> Enum.map(&(&1 |> Floki.text() |> String.replace(~r/\s+/u, " ") |> String.trim()))
  end

  defp security!(attrs) do
    {:ok, security} =
      Catalog.create_security(
        Actor.owner_ui(),
        Map.merge(%{currency_code: "EUR", asset_class: "equity"}, attrs)
      )

    security
  end
end
