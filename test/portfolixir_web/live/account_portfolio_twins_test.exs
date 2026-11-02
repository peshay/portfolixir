defmodule PortfolixirWeb.AccountPortfolioTwinsTest do
  # Sprint 22 U2 (#1333; board `ux-design-2026-11-01-sprint22/03-drawer-import`,
  # section ⑤, and the plan's D-9 finding for U2). Account names are unique
  # per portfolio, not across portfolios: two portfolios may each hold a
  # "Coupon-Cash" and a "Coupon-Depot". Where an account's name is also the
  # name of an account of its kind in another portfolio, the account carries
  # its portfolio's name after its own (`.twin-id.twin-id--portfolio`, a
  # visually hidden "Portfolio" before it) on the Accounts page, the
  # history's account chips, the booking drawer's depot and cash account
  # selects and Wealth's cash table. An account with a unique name stays
  # bare. Every name and figure is synthetic.
  use PortfolixirWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures, only: [add_depot: 2, base_world: 1, deposit!: 3]

  alias Portfolixir.Classifications

  setup do
    main =
      base_world(name: "Hauptportfolio", cash_name: "Coupon-Cash", depot_name: "Coupon-Depot")

    %{cash: demo_cash, depot: demo_depot} =
      add_depot(main.portfolio, cash_name: "Demo Cash", depot_name: "Demo Depot")

    bonds = base_world(name: "Anleihen", cash_name: "Coupon-Cash", depot_name: "Coupon-Depot")

    deposit!(main, "450.00", ~D[2026-10-01])
    deposit!(bonds, "450.00", ~D[2026-09-30])
    deposit!(%{main | cash: demo_cash}, "2899.90", ~D[2026-10-29])

    %{main: main, bonds: bonds, demo_cash: demo_cash, demo_depot: demo_depot}
  end

  defp text(nodes), do: nodes |> Floki.text() |> String.replace(~r/\s+/, " ") |> String.trim()

  defp find(html, selector), do: html |> Floki.parse_document!() |> Floki.find(selector)

  defp tag_text(html, selector), do: html |> find(selector <> " .twin-id--portfolio") |> text()

  defp option_text(html, select, id),
    do: html |> find(~s(select[name="#{select}"] option[value="#{id}"])) |> text()

  # User story (#1333, board 03 ⑤):
  # As the operator whose two portfolios each hold an account named
  # "Coupon-Cash" and a depot named "Coupon-Depot",
  # I want each of them to read with its portfolio's name on the Accounts
  # page,
  # so that I can tell the pairs apart and act on the right one.
  #
  # Acceptance criteria:
  # - Each twin depot and each twin cash account carries a
  #   `.twin-id--portfolio` tag reading "Portfolio <its portfolio>".
  # - The unique "Demo Depot" and "Demo Cash" carry none.
  test "the Accounts page names the portfolio of each twin account, and only of twins",
       %{conn: conn, main: main, bonds: bonds, demo_depot: demo_depot} do
    {:ok, _view, html} = live(conn, "/portfolios")

    main_band = "#account-row-depot-#{main.depot.id}"
    bonds_band = "#account-row-depot-#{bonds.depot.id}"

    assert tag_text(html, main_band <> " .cell-name--depot") == "Portfolio Hauptportfolio"
    assert tag_text(html, main_band <> " .cell-name--cash") == "Portfolio Hauptportfolio"
    assert tag_text(html, bonds_band <> " .cell-name--depot") == "Portfolio Anleihen"
    assert tag_text(html, bonds_band <> " .cell-name--cash") == "Portfolio Anleihen"

    assert find(html, "#account-row-depot-#{demo_depot.id} .twin-id--portfolio") == []
    assert html |> find(".twin-id--portfolio") |> length() == 4
  end

  # User story (#1333, board 03 ⑤):
  # As the operator filtering the history by account,
  # I want the two "Coupon-Cash" chips to name their portfolios,
  # so that I filter on the account I mean.
  #
  # Acceptance criteria:
  # - The chip of each twin reads "Coupon-Cash Portfolio <its portfolio>"
  #   (the word "Portfolio" visually hidden); "Demo Cash" reads its name.
  test "the history's account chips name the portfolio of each twin",
       %{conn: conn, main: main, bonds: bonds, demo_cash: demo_cash} do
    {:ok, _view, html} = live(conn, "/transactions")

    chip = fn id -> html |> find("#transaction-chips #tx-chip-account-#{id}") |> text() end

    assert chip.(main.cash.id) == "Coupon-Cash Portfolio Hauptportfolio"
    assert chip.(bonds.cash.id) == "Coupon-Cash Portfolio Anleihen"
    assert chip.(demo_cash.id) == "Demo Cash"
  end

  # User story (#1333, D-9's finding for U2):
  # As the operator booking a buy or a deposit in the drawer,
  # I want the depot and cash account options of two same-named accounts to
  # name their portfolios,
  # so that I book into the account I mean.
  #
  # Acceptance criteria:
  # - The depot select reads "Coupon-Depot · Anleihen (Coupon-Cash)" and
  #   "Coupon-Depot · Hauptportfolio (Coupon-Cash)"; "Demo Depot (Demo Cash)"
  #   is unchanged.
  # - The cash form's account select reads "Coupon-Cash · Anleihen (EUR)";
  #   "Demo Cash (EUR)" is unchanged.
  test "the booking drawer's depot and cash account selects name the portfolio of each twin",
       %{conn: conn, main: main, bonds: bonds, demo_cash: demo_cash, demo_depot: demo_depot} do
    {:ok, view, _html} = live(conn, "/transactions")
    html = render_click(view, "open_booking", %{})

    depot = "transaction[securities_account_id]"
    assert option_text(html, depot, bonds.depot.id) == "Coupon-Depot · Anleihen (Coupon-Cash)"

    assert option_text(html, depot, main.depot.id) ==
             "Coupon-Depot · Hauptportfolio (Coupon-Cash)"

    assert option_text(html, depot, demo_depot.id) == "Demo Depot (Demo Cash)"

    html =
      render_change(view, "form_changed", %{
        "_target" => ["transaction", "type"],
        "transaction" => %{"type" => "deposit", "date" => "2026-10-08"}
      })

    cash = "transaction[cash_account_id]"
    assert option_text(html, cash, bonds.cash.id) == "Coupon-Cash · Anleihen (EUR)"
    assert option_text(html, cash, main.cash.id) == "Coupon-Cash · Hauptportfolio (EUR)"
    assert option_text(html, cash, demo_cash.id) == "Demo Cash (EUR)"
  end

  # User story (#1333, D-9's finding for U2):
  # As the operator reading Wealth's cash accounts,
  # I want the two "Coupon-Cash" rows to name their portfolios,
  # so that the two 450,00 EUR balances are not one account printed twice.
  #
  # Acceptance criteria:
  # - The twin rows carry "Portfolio Anleihen" and "Portfolio
  #   Hauptportfolio"; "Demo Cash" carries none.
  test "Wealth's cash table names the portfolio of each twin", %{conn: conn} do
    Classifications.ensure_builtins()
    {:ok, view, _html} = live(conn, "/portfolio")
    html = render_async(view)

    tags = html |> find("#portfolio-cash .twin-id--portfolio") |> Enum.map(&text/1)
    assert Enum.sort(tags) == ["Portfolio Anleihen", "Portfolio Hauptportfolio"]

    rows = html |> find("#portfolio-cash tbody tr") |> Enum.map(&text/1)
    assert Enum.any?(rows, &String.starts_with?(&1, "Demo Cash 2,899.90 EUR"))
  end
end
