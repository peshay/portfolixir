defmodule PortfolixirWeb.PortfolioAccounts.AccountDialogAllOrNothingTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Journal
  alias Portfolixir.Portfolios

  defp owner, do: Actor.owner_ui()

  defp existing_depot! do
    portfolio = Portfolios.default_portfolio(owner())

    {:ok, cash} =
      Portfolios.create_cash_account(owner(), %{
        portfolio_id: portfolio.id,
        name: "Giro",
        currency_code: "EUR"
      })

    {:ok, _depot} =
      Portfolios.create_securities_account(owner(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Depot A"
      })

    :ok
  end

  defp cash_creates,
    do: length(Journal.list_entries(resource_type: "cash_account", operation: :create))

  defp submit_depot(view, depot_name) do
    view |> element("#add-account-button") |> render_click()

    view
    |> element("#account-form-dialog button[phx-value-mode='depot']")
    |> render_click()

    view
    |> form("#account-dialog-form", %{
      "account" => %{
        "depot_name" => depot_name,
        "cash_account_id" => "",
        "cash_name" => "Clearing B",
        "currency_code" => "EUR",
        "new_tag" => "Fresh tag"
      }
    })
    |> render_submit()
  end

  # User story (security review 2026-10-12, K14):
  # As the operator creating a depot with a new cash account and a new tag,
  # I want a save the depot refuses to write nothing at all,
  # so that no cash account or tag I did not mean to create stays behind and
  # a corrected retry is not refused on the name the leftover took.
  #
  # Acceptance criteria:
  # - A depot name the depot refuses (another depot's name with surrounding
  #   whitespace, with an invisible character, or exactly) answers the error
  #   on the depot name.
  # - No new cash account and no new tag are left, and no cash account
  #   create is journaled.
  # - A corrected retry with the same cash name then succeeds.
  test "a depot the dialog's save refuses leaves no cash account and no tag behind", %{
    conn: conn
  } do
    :ok = existing_depot!()
    creates = cash_creates()

    {:ok, view, _html} = live(conn, "/portfolios")

    for refused <- ["Depot A ", " Depot A", "Depot\u200BC", "Depot A"] do
      html = submit_depot(view, refused)

      assert html =~ "field-error", inspect(refused)
      assert has_element?(view, "#account-dialog-form .field-error"), inspect(refused)

      assert Enum.map(Portfolios.list_cash_accounts(), & &1.name) == ["Giro"], inspect(refused)
      refute "Fresh tag" in Enum.map(Buckets.list_buckets(), & &1.name), inspect(refused)
      assert cash_creates() == creates, inspect(refused)

      view |> element("#account-form-dialog header button.icon-button") |> render_click()
    end

    submit_depot(view, "Depot B")

    assert Enum.sort(Enum.map(Portfolios.list_cash_accounts(), & &1.name)) == [
             "Clearing B",
             "Giro"
           ]

    assert Enum.sort(Enum.map(Portfolios.list_securities_accounts(), & &1.name)) == [
             "Depot A",
             "Depot B"
           ]

    assert "Fresh tag" in Enum.map(Buckets.list_buckets(), & &1.name)
  end
end
