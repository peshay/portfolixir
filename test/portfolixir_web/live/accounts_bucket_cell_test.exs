defmodule PortfolixirWeb.AccountsBucketCellTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Portfolios

  # User story (#806, review C9 — variant A, picked by the owner 2026-09-14):
  # As a local portfolio maintainer reading Accounts & depots,
  # I want the bucket cell to say what a set applies to instead of holding
  # four controls for one question, and the role label to appear once,
  # so that the table can be READ before it is edited.
  #
  # Acceptance criteria:
  # - "Liquidity role" renders once per table (in the head); the cell holds
  #   the select, its label carried for assistive technology only.
  # - Bucket state is readable without interacting: the chips, a scope
  #   sub-line, and "No bucket" as a word when the set is empty.
  # - "Tag separately" is in the row menu, not a fourth control in the cell;
  #   assignment, removal and the separate-tagging path still work.

  defp world do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Cell World",
        base_currency_code: "EUR"
      })

    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Cell Cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Cell Depot",
        cash_account_id: cash.id
      })

    %{portfolio: portfolio, cash: cash, depot: depot}
  end

  test "the role label renders once, in the head", %{conn: conn} do
    world()
    {:ok, _view, html} = live(conn, "/portfolios")

    # Once as the column head, once per row as a visually-hidden label for
    # the select — never as visible text beside it.
    assert html =~ ~s(<th>Liquidity role</th>)
    assert html =~ ~s(class="visually-hidden")
    refute html =~ ~s(class="liquidity-role-field__label")
  end

  test "the bucket cell is readable without interacting", %{conn: conn} do
    %{depot: depot} = world()
    {:ok, view, _html} = live(conn, "/portfolios")

    band = view |> element("#account-row-depot-#{depot.id}") |> render()

    # A fresh pair carries equal empty sets, so it is merged: the scope says
    # what it would apply to, and the emptiness is a word.
    assert band =~ "Applies to depot and cash account"
    assert has_element?(view, "#pair-buckets-#{depot.id} [data-role='bucket-empty']")
    assert has_element?(view, "#pair-buckets-#{depot.id} [data-role='bucket-scope']")
  end

  test "the scope sub-line follows the split", %{conn: conn} do
    %{cash: cash, depot: depot} = world()
    {:ok, view, _html} = live(conn, "/portfolios")

    view |> element("#account-kebab-#{depot.id}") |> render_click()
    view |> element("#split-pair-#{depot.id}") |> render_click()

    assert view |> element("#depot-buckets-#{depot.id}") |> render() =~ "Applies to the depot"

    assert view |> element("#cash-buckets-#{cash.id}") |> render() =~
             "Applies to the cash account"
  end

  test "Tag separately lives in the row menu and still splits the pair", %{conn: conn} do
    %{cash: cash, depot: depot} = world()
    {:ok, tag} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Household"})
    :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), depot, [tag.id])
    :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), cash, [tag.id])

    {:ok, view, _html} = live(conn, "/portfolios")

    # Not a fourth control in the cell.
    refute has_element?(view, "#pair-buckets-#{depot.id} [data-role='split-pair']")

    view |> element("#account-kebab-#{depot.id}") |> render_click()
    view |> element("#account-row-menu-#{depot.id} #split-pair-#{depot.id}") |> render_click()

    refute has_element?(view, "#pair-buckets-#{depot.id}")
    assert has_element?(view, "#depot-buckets-#{depot.id}")
    assert has_element?(view, "#cash-buckets-#{cash.id}")
    # The menu closes with the act.
    refute has_element?(view, "#account-row-menu-#{depot.id}")
  end
end
