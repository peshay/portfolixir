defmodule PortfolixirWeb.WealthStartersMenuTest do
  # Sprint 32 W5 (plan W5; ADR-0062's amendment of 2026-11-25, points 5 and
  # 7; board ux-design-2026-11-25-sprint32/02 ①): the starters of Wealth's
  # tabs stand in the menu after „Überblick“, and Wealth's tab bar leads
  # each tab that became a starter to its dashboard; the page itself stays
  # under „Entdecken“, the full view and the home of the tabs not passed.
  #
  # group: :dashboards -- a create takes the count lock (LockTable row 30).
  use PortfolixirWeb.ConnCase, async: true, group: :dashboards

  import Phoenix.LiveViewTest
  import PortfolixirWeb.PreferenceCookieHelpers
  import Portfolixir.WorldFixtures

  alias Portfolixir.Actor
  alias Portfolixir.Dashboards
  alias Portfolixir.Dashboards.Starters

  defp german(conn), do: put_preference_cookie(conn, "portfolixir_locale", "de")

  defp texts(doc, selector),
    do: doc |> Floki.find(selector) |> Enum.map(&(&1 |> Floki.text() |> String.trim()))

  defp menu(doc), do: texts(doc, ".nav-group--dashboards .nav-label")

  # An instance from before this release: its copy of „Überblick“, then a
  # dashboard of the operator's own; the boot counts „Überblick“.
  defp upgraded! do
    {:ok, overview} = Dashboards.copy_template(Actor.owner_ui(), "overview", %{})
    {:ok, mine} = Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => "Mein Krypto"})
    {overview, mine}
  end

  # User story:
  # As the operator updating to the release that brings Wealth's tabs as
  # dashboards,
  # I want them in the menu right after „Überblick“, before the dashboards
  # I made myself,
  # so that the menu reads like the tabs I know, as board 02 ① draws it.
  #
  # Acceptance criteria:
  # - After the boot's run on an instance that holds „Überblick“ and
  #   „Mein Krypto“, the menu lists Überblick, Bestände, Allokation & Ziele,
  #   Snapshots, Risiko, Mein Krypto, then „Neues Dashboard“; the API's
  #   list is in the same order.
  # - „Vermögen“ stays under „Entdecken“.
  test "the starters follow „Überblick“ in the menu, before the operator's own", %{conn: conn} do
    base_world()
    upgraded!()

    assert {:ok, %{stored: ~w(holdings allocation_targets snapshots risk), counted: ["overview"]}} =
             Starters.seed()

    {:ok, _view, html} = conn |> german() |> live("/")
    doc = Floki.parse_document!(html)

    assert menu(doc) ==
             [
               "Überblick",
               "Bestände",
               "Allokation & Ziele",
               "Snapshots",
               "Risiko",
               "Mein Krypto",
               "Neues Dashboard"
             ]

    assert Enum.map(Dashboards.list_dashboards(), & &1.template_key) ==
             ["overview", "holdings", "allocation_targets", "snapshots", "risk", nil]

    assert texts(doc, ".nav-group--discover #nav-portfolio .nav-label") == ["Vermögen"]
  end

  # User story:
  # As the operator on Wealth's page,
  # I want the tabs that became dashboards to open those dashboards, and
  # the others their pages,
  # so that one click leads to the screen I keep and change.
  #
  # Acceptance criteria:
  # - With the starters stored, Bestände, Allokation & Ziele, Snapshots
  #   and Risiko lead to their dashboards, on Wealth and on the tabs' pages;
  #   Cashflow, Steuer and Prognosen to their pages.
  # - Without a stored starter (a fresh instance shows the template), every
  #   tab leads to its page, as before.
  test "Wealth's tab bar leads each passed tab to its dashboard", %{conn: conn} do
    base_world()

    {:ok, _view, fresh} = conn |> german() |> live("/portfolio")

    assert fresh |> Floki.parse_document!() |> Floki.find("#area-tabs a") |> Enum.map(&href/1) ==
             ~w(/portfolio /portfolio?tab=allocation /cashflow /snapshots /tax /risk /predictions)

    {:ok, _report} = Starters.seed()
    ids = Map.new(Dashboards.list_dashboards(), &{&1.template_key, &1.id})

    for path <- ["/portfolio", "/snapshots", "/risk"] do
      {:ok, _view, html} = conn |> german() |> live(path)

      assert html |> Floki.parse_document!() |> Floki.find("#area-tabs a") |> Enum.map(&href/1) ==
               [
                 "/dashboards/#{ids["holdings"]}",
                 "/dashboards/#{ids["allocation_targets"]}",
                 "/cashflow",
                 "/dashboards/#{ids["snapshots"]}",
                 "/tax",
                 "/dashboards/#{ids["risk"]}",
                 "/predictions"
               ],
             path
    end
  end

  defp href(link), do: link |> Floki.attribute("href") |> hd()
end
