defmodule PortfolixirWeb.SecuritiesFilterChipsTest do
  # Issue #717 (D2): the common securities filters become one-tap chips above
  # the table; the Column/Operator/Value builder is demoted behind a counted
  # "More filters" control. The chip set is fixed and named; chips are
  # toggles (aria-pressed), families compose AND, chips within one family
  # compose OR, and the active set is URL-addressable.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Catalog
  alias Portfolixir.Fx
  alias Portfolixir.Repo
  alias Portfolixir.WorldFixtures

  # The journal guard requires an actor for any write; stored NULL is the
  # legacy-import state the #700 decision distinguishes from the effective
  # (inferred) class, and it cannot be produced through the changeset, which
  # infers on create.
  defp clear_stored_class!(security_id) do
    Repo.query!("SELECT set_config('portfolixir.journal_actor', 'test_chips', true)")
    Repo.query!("UPDATE securities SET asset_class = NULL WHERE id = $1", [security_id])
  end

  # User story (issue #717):
  # As a local portfolio maintainer,
  # I want Held / Not held as one-tap chips,
  # so that the default reading of "my securities" is one tap, not a
  # segmented control's third option.
  #
  # Acceptance criteria:
  # - The chips ride the existing `?holding=` URL state.
  # - Clicking the active chip returns to the full list.
  # - The old segmented control is gone (the chips replace it, not join it).
  test "held and not-held chips ride the URL and replace the segmented control", %{conn: conn} do
    world = WorldFixtures.base_world()
    held = WorldFixtures.create_security!(name: "Held Equity", ticker: "HLD")
    WorldFixtures.create_security!(name: "Never Held Equity", ticker: "NHD")
    WorldFixtures.buy!(world, held, quantity: "3")

    {:ok, view, html} = live(conn, "/securities")

    refute html =~ ~s(id="holding-status-filter")

    view |> element("#sec-chip-held") |> render_click()
    assert_patch(view, "/securities?holding=held")

    assert view |> element("#sec-chip-held") |> render() =~ ~s(aria-pressed="true")
    assert has_element?(view, "td", "Held Equity")
    refute has_element?(view, "td", "Never Held Equity")

    view |> element("#sec-chip-held") |> render_click()
    assert_patch(view, "/securities")
    assert has_element?(view, "td", "Never Held Equity")
  end

  # User story (issue #717):
  # As a local portfolio maintainer,
  # I want the Unclassified chip keyed on the STORED class,
  # so that the chip, the dashboard count and the API's predicate (#705) all
  # select the same auditable set — an inferred class is a guess, not a
  # stated fact (#700).
  #
  # Acceptance criteria:
  # - The chip toggles the canonical `filter[]=asset_class:is_nil` URL state.
  # - A row with stored NULL but an inferable class still matches.
  test "the unclassified chip is keyed on the stored class, not the effective one", %{conn: conn} do
    WorldFixtures.create_security!(
      name: "Classified Equity AG",
      ticker: "CLS",
      asset_class: "equity"
    )

    legacy = WorldFixtures.create_security!(name: "World Index ETF", ticker: "WIE")
    clear_stored_class!(legacy.id)

    {:ok, view, _html} = live(conn, "/securities")

    view |> element("#sec-chip-unclassified") |> render_click()
    path = assert_patch(view)
    assert path =~ "asset_class%3Ais_nil"

    # Stored NULL matches even though the name infers "etf" — the effective
    # class is display, the stored one is the filter (#700).
    assert has_element?(view, "td", "World Index ETF")
    refute has_element?(view, "td", "Classified Equity AG")

    view |> element("#sec-chip-unclassified") |> render_click()
    path = assert_patch(view)
    refute path =~ "asset_class"
  end

  # User story (issue #717):
  # As a local portfolio maintainer,
  # I want the asset-class chips keyed on the EFFECTIVE class,
  # so that "show me the ETFs" includes a legacy row whose class is inferred
  # from its name — the display and the chip agree on what an ETF is.
  #
  # Acceptance criteria:
  # - One chip per effective class in use, labelled with the class label.
  # - A stored-NULL row with an inferred class matches its class chip.
  # - Two class chips compose OR.
  test "asset-class chips are keyed on the effective class and compose OR", %{conn: conn} do
    WorldFixtures.create_security!(name: "Plain Equity AG", ticker: "PEQ", asset_class: "equity")
    stored_etf = WorldFixtures.create_security!(name: "Stored World ETF", ticker: "SWE")
    legacy = WorldFixtures.create_security!(name: "Legacy Index ETF", ticker: "LIE")
    clear_stored_class!(legacy.id)

    assert %{asset_class: "etf"} = Catalog.get_security(stored_etf.id)

    {:ok, view, _html} = live(conn, "/securities")

    view |> element("#sec-chip-class-etf") |> render_click()
    path = assert_patch(view)
    assert path =~ "class[]=etf"

    assert has_element?(view, "td", "Stored World ETF")
    assert has_element?(view, "td", "Legacy Index ETF")
    refute has_element?(view, "td", "Plain Equity AG")

    view |> element("#sec-chip-class-equity") |> render_click()
    assert has_element?(view, "td", "Plain Equity AG")
    assert has_element?(view, "td", "Stored World ETF")
  end

  # User story (issue #717):
  # As a local portfolio maintainer,
  # I want one currency chip per currency in use, composing OR,
  # so that "the EUR and USD part of the catalog" is two taps.
  #
  # Acceptance criteria:
  # - Chips exist only for currencies actually in use.
  # - Two currency chips compose OR; the state rides the URL.
  test "currency chips compose OR within the family", %{conn: conn} do
    WorldFixtures.create_security!(
      name: "Euro Equity",
      ticker: "EEQ",
      currency: "EUR",
      asset_class: "equity"
    )

    WorldFixtures.create_security!(
      name: "Dollar Equity",
      ticker: "DEQ",
      currency: "USD",
      asset_class: "equity"
    )

    WorldFixtures.create_security!(
      name: "Pound Equity",
      ticker: "PEQ",
      currency: "GBP",
      asset_class: "equity"
    )

    {:ok, view, _html} = live(conn, "/securities")

    refute has_element?(view, "#sec-chip-cur-CHF")

    view |> element("#sec-chip-cur-USD") |> render_click()
    path = assert_patch(view)
    assert path =~ "cur[]=USD"

    assert has_element?(view, "td", "Dollar Equity")
    refute has_element?(view, "td", "Euro Equity")

    view |> element("#sec-chip-cur-EUR") |> render_click()
    assert has_element?(view, "td", "Dollar Equity")
    assert has_element?(view, "td", "Euro Equity")
    refute has_element?(view, "td", "Pound Equity")
  end

  # User story (issue #717):
  # As a local portfolio maintainer,
  # I want the data-quality chips (stale quote, no price, missing FX) to be
  # the same predicates the dashboard counts and the API serves,
  # so that a chip narrows to exactly the set an alarm links into.
  #
  # Acceptance criteria:
  # - Stale quote / No price ride the existing `?dq=` state.
  # - Missing FX is a new predicate in Catalog.DataQuality: priced, but no
  #   stored rate to the base currency — storing the rate empties the set.
  test "data-quality chips narrow to the shared predicate sets", %{conn: conn} do
    fresh = WorldFixtures.create_security!(name: "Fresh Equity", ticker: "FRS")
    WorldFixtures.put_quote!(fresh, Date.utc_today(), "100")

    stale = WorldFixtures.create_security!(name: "Stale Equity", ticker: "STL")
    WorldFixtures.put_quote!(stale, Date.add(Date.utc_today(), -30), "90")

    WorldFixtures.create_security!(name: "Unpriced Equity", ticker: "UNP")

    unfx =
      WorldFixtures.create_security!(
        name: "Unrated Dollar Equity",
        ticker: "UFX",
        currency: "USD"
      )

    WorldFixtures.put_quote!(unfx, Date.utc_today(), "50")

    {:ok, view, _html} = live(conn, "/securities")

    view |> element("#sec-chip-stale_quote") |> render_click()
    assert_patch(view, "/securities?dq=stale_quote")
    assert has_element?(view, "td", "Stale Equity")
    assert has_element?(view, "td", "Unpriced Equity")
    refute has_element?(view, "td", "Fresh Equity")

    view |> element("#sec-chip-missing_quote") |> render_click()
    assert has_element?(view, "td", "Unpriced Equity")
    refute has_element?(view, "td", "Stale Equity")

    view |> element("#sec-chip-missing_fx") |> render_click()
    assert_patch(view, "/securities?dq=missing_fx")
    assert has_element?(view, "td", "Unrated Dollar Equity")
    refute has_element?(view, "td", "Fresh Equity")
    refute has_element?(view, "td", "Unpriced Equity")

    # Storing the rate empties the set — the predicate is about the rate,
    # not the currency.
    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: Date.utc_today(),
          rate: "1.08",
          source: "manual"
        }
      ])

    {:ok, view, _html} = live(conn, "/securities?dq=missing_fx")
    refute has_element?(view, "td", "Unrated Dollar Equity")
  end

  # User story (issue #717):
  # As a local portfolio maintainer,
  # I want the builder demoted behind "More filters" with a count,
  # so that the escape hatch stays reachable and a demoted control never
  # hides active state.
  #
  # Acceptance criteria:
  # - The "More filters" control opens the existing builder popover.
  # - It counts only conditions the chips cannot express.
  test "more filters demotes the builder and counts what chips cannot express", %{conn: conn} do
    WorldFixtures.create_security!(name: "Countable Equity", ticker: "CNT")

    {:ok, view, _html} = live(conn, "/securities?filter[]=name:contains:Count")
    assert view |> element("[data-role='more-filters-count']") |> render() =~ "1"

    view |> element("#more-filters-toggle") |> render_click()
    assert has_element?(view, "#filter-popover")

    # The chip-expressible unclassified condition does not count.
    {:ok, view, _html} = live(conn, "/securities?filter[]=asset_class:is_nil")
    refute has_element?(view, "[data-role='more-filters-count']")
    assert view |> element("#sec-chip-unclassified") |> render() =~ ~s(aria-pressed="true")
  end
end
