defmodule PortfolixirWeb.SecurityTwinsLiveTest do
  # The closing act, UAT-13: twin securities — the case the security merge
  # exists for — could not be told apart where the operator picks or names
  # one. The F1 rule the import preview applies to same-named accounts
  # (DESIGN.md, G4b) now holds for securities too: a name another security of
  # the list carries adds, after a middle dot, its ISIN (else its ticker,
  # else its number); a unique name is unchanged. Every name and identifier
  # is synthetic.
  use PortfolixirWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Portfolixir.WorldFixtures
  alias PortfolixirWeb.SecurityNames

  @isin_old "XS0000000017"
  @isin_new "XS0000000025"

  setup do
    world = WorldFixtures.base_world(name: "Twins")

    old =
      WorldFixtures.create_security!(
        name: "Pinecrest Utilities SA",
        ticker: "PUSA",
        isin: @isin_old
      )

    new =
      WorldFixtures.create_security!(
        name: "Pinecrest Utilities SA",
        ticker: "PUSA",
        isin: @isin_new
      )

    unique = WorldFixtures.create_security!(name: "Orchid Bay Pharmaceuticals plc", ticker: "OBP")

    for security <- [old, new, unique],
        do: WorldFixtures.buy!(world, security, date: ~D[2026-01-05])

    %{world: world, old: old, new: new, unique: unique}
  end

  # Acceptance criteria:
  # - Twins take their ISIN; without one, their ticker when it differs; else
  #   their number. A unique name takes nothing.
  test "a twin is told apart by the first feature that differs", ctx do
    tags = SecurityNames.tags([ctx.old, ctx.new, ctx.unique])

    assert SecurityNames.label(tags, ctx.old) == "Pinecrest Utilities SA · #{@isin_old}"
    assert SecurityNames.label(tags, ctx.new) == "Pinecrest Utilities SA · #{@isin_new}"
    assert SecurityNames.label(tags, ctx.unique) == "Orchid Bay Pharmaceuticals plc"

    no_isin = [%{ctx.old | isin: nil}, %{ctx.new | isin: nil, ticker_symbol: "PUS2"}]
    assert SecurityNames.tags(no_isin) == %{ctx.old.id => "PUSA", ctx.new.id => "PUS2"}

    same = [%{ctx.old | isin: nil}, %{ctx.new | isin: nil}]

    assert SecurityNames.tags(same) == %{
             ctx.old.id => "no. #{ctx.old.id}",
             ctx.new.id => "no. #{ctx.new.id}"
           }
  end

  # User story:
  # As the operator writing a rule about one of two twins,
  # I want the subject list to say which is which,
  # so that the rule reads the security I meant.
  test "the rule dialog's subject options tell twins apart", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/risk")
    view |> element("#policy-rules button", "New rule") |> render_click()
    view |> form("#policy-rule-form", rule: %{measure: "weight"}) |> render_change()

    select = view |> element("select[name='rule[subject]']") |> render()
    assert select =~ "Pinecrest Utilities SA · #{@isin_old}"
    assert select =~ "Pinecrest Utilities SA · #{@isin_new}"
    assert select =~ ~r/>\s*Orchid Bay Pharmaceuticals plc\s*</
  end

  # User story:
  # As the operator booking into one of two twins,
  # I want the security list of the booking drawer to say which is which,
  # so that the booking lands on the security I meant.
  test "the booking drawer's security options tell twins apart", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/transactions")
    view |> element("#open-booking") |> render_click()

    select =
      view |> element("#transaction-form select[name='transaction[security_id]']") |> render()

    assert select =~ "Pinecrest Utilities SA (PUSA) · #{@isin_old}"
    assert select =~ "Pinecrest Utilities SA (PUSA) · #{@isin_new}"
    assert select =~ ~r/Orchid Bay Pharmaceuticals plc \(OBP\)\s*</
  end

  # Acceptance criteria (DESIGN: name every row kebab for its row, never
  # give every kebab on a page the same name): the twins' kebabs on
  # /securities and their bookings' kebabs on /transactions carry
  # different accessible names.
  test "the twins' row menus carry different names", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, "/securities")

    assert has_element?(
             view,
             "#row-kebab-#{ctx.old.id}[aria-label='Actions for Pinecrest Utilities SA · #{@isin_old}']"
           )

    assert has_element?(
             view,
             "#row-kebab-#{ctx.new.id}[aria-label='Actions for Pinecrest Utilities SA · #{@isin_new}']"
           )

    assert has_element?(
             view,
             "#row-kebab-#{ctx.unique.id}[aria-label='Actions for Orchid Bay Pharmaceuticals plc']"
           )

    {:ok, view, _html} = live(conn, "/transactions")
    html = render(view)

    assert html =~ "Pinecrest Utilities SA · #{@isin_old}"
    assert html =~ "Pinecrest Utilities SA · #{@isin_new}"
  end
end
