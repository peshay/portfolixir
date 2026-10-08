defmodule PortfolixirWeb.Securities.MasterDataCreationTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Classifications
  alias Portfolixir.Portfolios
  alias Portfolixir.Repo

  defp open_security_dialog(conn) do
    {:ok, view, _html} = live(conn, "/securities")
    view |> element("#open-new-dialog") |> render_click()
    view
  end

  # User story (#491 item 7):
  # As a local portfolio maintainer adding a security the provider search
  # does not know,
  # I want a manual-entry escape hatch in the creation dialog,
  # so that an unlisted instrument can still be recorded without abusing the
  # search flow.
  #
  # Acceptance criteria:
  # - The choose step offers "Manual entry" beside the two search modes.
  # - The search step links to manual entry when the search comes up short.
  # - Manual entry lands on the details form; saving creates the security.
  describe "manual entry escape hatch (#491)" do
    test "the choose step offers manual entry and saving creates the security",
         %{conn: conn} do
      view = open_security_dialog(conn)

      view
      |> element(~s(button[phx-click="choose_mode"][phx-value-mode="manual"]))
      |> render_click()

      assert has_element?(view, "#security-dialog-form")

      view
      |> form("#security-dialog-form", %{
        "security" => %{
          "name" => "Unlisted Holding GmbH",
          "currency_code" => "EUR",
          "asset_class" => "equity"
        }
      })
      |> render_submit()

      # Rendering synchronises with the parent's {:created, _} handling, so
      # the LiveView finishes its reload inside the sandbox ownership window.
      assert has_element?(view, "td", "Unlisted Holding GmbH")

      assert [security] = Catalog.list_securities(query: "Unlisted Holding")
      assert security.name == "Unlisted Holding GmbH"
      assert security.currency_code == "EUR"
    end

    test "the search step carries a manual-entry link", %{conn: conn} do
      view = open_security_dialog(conn)

      view
      |> element(~s(button[phx-click="choose_mode"][phx-value-mode="security"]))
      |> render_click()

      assert has_element?(view, ~s(button[data-role="manual-entry-link"]))

      view
      |> element(~s(button[data-role="manual-entry-link"]))
      |> render_click()

      assert has_element?(view, "#security-dialog-form")
    end

    # User story (#942; the F15 allow-list precedent, T-5):
    # As the operator whose security dialog writes what it shows,
    # I want a save to take only the fields the dialog renders,
    # so that a crafted form payload cannot set the provider marker or the
    # security's flags, and an unknown key does not throw the form away.
    #
    # Acceptance criteria:
    # - A manual save whose payload also carries provider, online_id,
    #   is_benchmark, is_retired, latest_feed and latest_feed_url creates the
    #   security from the rendered fields alone: the manual provider marker,
    #   no online id, neither a benchmark nor retired, no latest feed.
    # - A key no field is named after is dropped, and the rest of the form is
    #   saved.
    test "a save takes only the fields the dialog renders", %{conn: conn} do
      for {name, extra} <- [
            {"Allowlisted Holding AG",
             %{
               "provider" => "coingecko",
               "online_id" => "synthetic-online-id",
               "is_benchmark" => "true",
               "is_retired" => "true",
               "latest_feed" => "COINGECKO",
               "latest_feed_url" => "https://quotes.example.invalid/latest"
             }},
            {"Unknown Key Holding AG", %{"zz_no_such_field_942" => "anything"}}
          ] do
        view = open_security_dialog(conn)

        view
        |> element(~s(button[phx-click="choose_mode"][phx-value-mode="manual"]))
        |> render_click()

        view
        |> form("#security-dialog-form", %{
          "security" => %{"name" => name, "currency_code" => "EUR", "asset_class" => "equity"}
        })
        |> render_submit(%{"security" => extra})

        assert {^name, %Security{} = security} =
                 {name, Repo.get_by(Security, name: name)}

        assert security.provider == "manual"
        assert security.online_id == nil
        assert security.is_benchmark == false
        assert security.is_retired == false
        assert security.latest_feed == nil
        assert security.latest_feed_url == nil
      end
    end
  end

  # User story (#491 item 3):
  # As a local portfolio maintainer picking a market for a found security,
  # I want the sensible default (XETR/EUR) recommended first with the rest
  # collapsed,
  # so that the market step is a one-click confirmation instead of a wall of
  # raw MIC codes.
  #
  # Acceptance criteria:
  # - The XETR (else first EUR) market renders as the recommended pick with
  #   its human exchange name.
  # - The remaining markets sit behind a "More markets" disclosure.
  describe "market step default (#491)" do
    test "XETR is recommended first and the rest collapse", %{conn: conn} do
      view = open_security_dialog(conn)

      view
      |> element(~s(button[phx-click="choose_mode"][phx-value-mode="security"]))
      |> render_click()

      view
      |> form("#security-dialog-search-form", %{"dialog_query" => "arbolia"})
      |> render_change()

      view
      |> element(~s(button[phx-click="pick_result"]))
      |> render_click()

      recommended = view |> element(~s([data-role="market-recommended"])) |> render()
      assert recommended =~ "Xetra"
      assert recommended =~ "EUR"

      more = view |> element(~s(details[data-role="market-more"])) |> render()
      assert more =~ "NASDAQ"
    end
  end

  # User story (#491 item 6):
  # As a local portfolio maintainer creating a cash account,
  # I want the currency to be a dropdown of known codes,
  # so that a typo like "ZZZ" cannot become an account currency.
  #
  # Acceptance criteria:
  # - The account dialog's currency field is a select over the known
  #   currency codes, defaulting to EUR — not a free-text maxlength-3 input.
  describe "account dialog currency select (#491)" do
    test "the currency field is a select of known codes", %{conn: conn} do
      Classifications.ensure_builtins()

      {:ok, portfolio} =
        Portfolios.create_portfolio(Actor.owner_ui(), %{name: "Main", base_currency_code: "EUR"})

      {:ok, _cash} =
        Portfolios.create_cash_account(Actor.owner_ui(), %{
          portfolio_id: portfolio.id,
          name: "Giro",
          currency_code: "EUR"
        })

      {:ok, view, _html} = live(conn, "/portfolios")
      view |> element("#add-account-button") |> render_click()

      view
      |> element(~s(#account-form-dialog button[phx-click="choose_mode"][phx-value-mode="cash"]))
      |> render_click()

      assert has_element?(view, ~s(#account-form-dialog select[name="account[currency_code]"]))
      refute has_element?(view, ~s(#account-form-dialog input[name="account[currency_code]"]))

      currency = view |> element(~s(select[name="account[currency_code]"])) |> render()
      assert currency =~ "EUR"
      assert currency =~ "USD"
    end
  end
end
