defmodule PortfolixirWeb.SecuritiesLogoRenderTest do
  # User story:
  # As a local portfolio maintainer,
  # I want a small logo next to every security so I can scan my list faster.
  # When a logo has been discovered, it should render inline; otherwise a
  # tasteful initial-letter circle should stand in.
  #
  # This module covers the render side of the contract:
  # - With `attributes["logo_path"]`, an `<img>` is rendered with that
  #   src in the row and in the detail-pane header.
  # - Without it, an initial-letter fallback span is rendered.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.LogoStore

  # 1x1 PNG
  @png <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8,
         6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 250, 207, 0, 0,
         0, 3, 0, 1, 5, 12, 60, 192, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130>>

  defp png_stub do
    [
      plug: fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("image/png")
        |> Plug.Conn.send_resp(200, @png)
      end
    ]
  end

  test "renders an img tag when the security has a logo_path", %{conn: conn} do
    {:ok, sec} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Apple Inc.",
        currency_code: "USD",
        provider: "manual",
        asset_class: "equity"
      })

    {:ok, _updated} =
      Catalog.put_logo_attributes(sec, %{
        "logo_path" => "/security_logos/#{sec.id}.png",
        "logo_source" => "wikipedia"
      })

    {:ok, view, _html} = live(conn, "/securities")
    html = render(view)

    assert html =~ ~s(src="/security_logos/#{sec.id}.png")
    assert html =~ ~s(class="security-logo security-logo--row")
  end

  test "renders the initial-letter fallback when no logo_path is set",
       %{conn: conn} do
    {:ok, _sec} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Apple Inc.",
        currency_code: "USD",
        provider: "manual",
        asset_class: "equity"
      })

    {:ok, view, _html} = live(conn, "/securities")
    html = render(view)

    assert html =~ ~s(security-logo--initial)
    # First letter is 'A' uppercase
    assert html =~ ~r/security-logo--initial[^>]*>[\s]*A[\s]*</
  end

  test "renders a bond country flag fallback from the ISIN country code",
       %{conn: conn} do
    {:ok, _sec} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "German Federal Bond",
        isin: "DE0001102614",
        currency_code: "EUR",
        provider: "manual",
        asset_class: "bond"
      })

    {:ok, view, _html} = live(conn, "/securities")
    html = render(view)

    assert html =~ ~s(security-logo--flag)
    assert html =~ "🇩🇪"
    refute html =~ ~r/security-logo--initial[^>]*>[\s]*G[\s]*</
  end

  test "renders a government bond country flag fallback from the ISIN country code",
       %{conn: conn} do
    {:ok, _sec} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "United States Treasury Note",
        isin: "US91282CFB28",
        currency_code: "USD",
        provider: "manual",
        asset_class: "government_bond"
      })

    {:ok, view, _html} = live(conn, "/securities")
    html = render(view)

    assert html =~ ~s(security-logo--flag)
    assert html =~ "🇺🇸"
    refute html =~ ~r/security-logo--initial[^>]*>[\s]*U[\s]*</
  end

  test "renders an inferred imported state-bond flag when asset_class is still blank",
       %{conn: conn} do
    {:ok, sec} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Placeholder",
        isin: "US912810SN90",
        currency_code: "USD",
        provider: "portfolio_performance",
        asset_class: "other"
      })

    {:ok, _sec} =
      Catalog.update_security(Portfolixir.Actor.owner_ui(), sec, %{
        name: "Anleihe USA 20/50",
        asset_class: nil
      })

    {:ok, view, _html} = live(conn, "/securities")
    html = render(view)

    assert html =~ ~s(security-logo--flag)
    assert html =~ "🇺🇸"
    refute html =~ ~r/security-logo--initial[^>]*>[\s]*A[\s]*</
  end

  test "renders the logo in the detail-pane header when a security is selected",
       %{conn: conn} do
    {:ok, sec} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Bitcoin",
        currency_code: "EUR",
        provider: "coingecko",
        asset_class: "crypto",
        online_id: "bitcoin"
      })

    {:ok, _updated} =
      Catalog.put_logo_attributes(sec, %{
        "logo_path" => "/security_logos/#{sec.id}.png",
        "logo_source" => "coingecko"
      })

    {:ok, view, _html} = live(conn, "/securities?id=#{sec.id}")
    html = render(view)

    assert html =~ ~s(security-logo--lg)
    assert html =~ ~s(src="/security_logos/#{sec.id}.png")
  end

  # User story:
  # As a maintainer watching the list during an import, a logo found by the
  # background discovery queue should replace the initials placeholder live,
  # without me reloading the page. LogoStore broadcasts on store; the LiveView
  # patches the affected row in place.
  test "a logo discovered after mount appears live via PubSub", %{conn: conn} do
    tmp =
      Path.join(System.tmp_dir!(), "portfolixir-logo-live-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(tmp) end)

    {:ok, sec} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Baozun",
        currency_code: "USD",
        provider: "manual",
        asset_class: "equity"
      })

    {:ok, view, html} = live(conn, "/securities")

    # Initially only the initials fallback is shown.
    assert html =~ ~s(security-logo--initial)
    refute html =~ ~s(src="/security_logos/#{sec.id}.png")

    # Background discovery stores a logo and broadcasts.
    {:ok, _updated} =
      LogoStore.download_and_store(
        sec,
        "https://example.test/logo.png",
        :wikipedia,
        req: png_stub(),
        storage_dir: tmp
      )

    # The subscribed LiveView patches the row in place — no reload.
    assert render(view) =~ ~s(src="/security_logos/#{sec.id}.png")
  end

  # User story:
  # As a maintainer, I want to set a logo from a URL when automatic discovery
  # missed one, and remove a wrong logo — directly from the securities list.
  test "manage-logo dialog sets and removes a manual logo", %{conn: conn} do
    prior = Application.get_env(:portfolixir, :logo_discovery_opts, [])

    tmp =
      Path.join(
        System.tmp_dir!(),
        "portfolixir-logo-dialog-#{System.unique_integer([:positive])}"
      )

    Application.put_env(:portfolixir, :logo_discovery_opts, req: png_stub(), storage_dir: tmp)

    on_exit(fn ->
      Application.put_env(:portfolixir, :logo_discovery_opts, prior)
      File.rm_rf(tmp)
    end)

    {:ok, sec} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Baozun",
        currency_code: "USD",
        provider: "manual",
        asset_class: "equity"
      })

    {:ok, view, _html} = live(conn, "/securities")

    # Open the manage-logo dialog for the row.
    html =
      render_hook(view, "row_action", %{"action" => "manage_logo", "id" => to_string(sec.id)})

    assert html =~ "Manage logo"

    # Set a manual logo from a URL (downloaded through the Req stub).
    render_hook(view, "save_logo_url", %{"logo" => %{"url" => "https://example.test/logo.png"}})

    updated = Catalog.get_security!(sec.id)
    assert updated.attributes["logo_source"] == "manual"
    assert updated.attributes["logo_locked"] == true
    assert render(view) =~ ~s(src="/security_logos/#{sec.id}.png")

    # Remove it again -> locked "no logo", initials fallback returns.
    render_hook(view, "remove_logo_override", %{"id" => to_string(sec.id)})

    removed = Catalog.get_security!(sec.id)
    refute removed.attributes["logo_path"]
    assert removed.attributes["logo_locked"] == true
  end
end
