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
        name: "Arbolia Inc.",
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
        name: "Arbolia Inc.",
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
        name: "Gravonia Federal Bond",
        isin: "DEEXMPL20530",
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
        name: "Union of Examplia Treasury Note",
        isin: "USEXMPL23215",
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
        isin: "USEXMPL21490",
        currency_code: "USD",
        provider: "portfolio_performance",
        asset_class: "other"
      })

    {:ok, _sec} =
      Catalog.update_security(Portfolixir.Actor.owner_ui(), sec, %{
        name: "Anleihe USA 21/47",
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
        name: "Lanzhuo",
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

  # User story (#933, review pass 1):
  # As an operator whose logo files were lost with the volume,
  # I want a row whose logo file is gone to show its monogram or flag,
  # so that the list never shows a broken image for a logo that is not there.
  #
  # Acceptance criteria:
  # - A row rendered with its logo switches live to its fallback once the
  #   reconciliation marks it (the broadcast patches the row).
  # - A fresh visit renders the fallback in the row and in the detail pane,
  #   for a discovered and a manual logo; the path itself is kept.
  # - dq=missing_logo lists both rows.
  test "a logo whose file is gone renders its fallback once marked", %{conn: conn} do
    tmp =
      Path.join(System.tmp_dir!(), "portfolixir-logo-gone-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf(tmp) end)

    {:ok, discovered} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Arbolia Inc.",
        currency_code: "USD",
        provider: "manual",
        asset_class: "equity"
      })

    {:ok, manual} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Gravonia Federal Bond",
        isin: "DEEXMPL20530",
        currency_code: "EUR",
        provider: "manual",
        asset_class: "bond"
      })

    {:ok, _} =
      Catalog.put_logo_attributes(discovered, %{
        "logo_path" => "/security_logos/#{discovered.id}.png",
        "logo_source" => "wikipedia"
      })

    {:ok, _} =
      Catalog.put_logo_attributes(manual, %{
        "logo_path" => "/security_logos/#{manual.id}.png",
        "logo_source" => "manual",
        "logo_locked" => true
      })

    {:ok, view, html} = live(conn, "/securities")
    assert html =~ ~s(src="/security_logos/#{discovered.id}.png")
    assert html =~ ~s(src="/security_logos/#{manual.id}.png")

    assert {:ok, %{marked: 2}} = LogoStore.reconcile_missing_files(storage_dir: tmp)

    html = render(view)
    refute html =~ ~s(src="/security_logos/)
    assert html =~ ~r/security-logo--initial[^>]*>[\s]*A[\s]*</
    assert html =~ "🇩🇪"

    {:ok, _view, html} = live(conn, "/securities?id=#{discovered.id}")
    refute html =~ ~s(src="/security_logos/)
    assert html =~ ~r/security-logo--lg[^"]*security-logo--initial/

    assert Catalog.get_security!(manual.id).attributes["logo_path"] ==
             "/security_logos/#{manual.id}.png"

    {:ok, list, _html} = live(conn, "/securities?dq=missing_logo")
    assert has_element?(list, "td", "Gravonia Federal Bond")
    assert has_element?(list, "td", "Arbolia Inc.")
  end

  # User story (#933, review passes 1 and 2; board
  # mockups/ux-design-2026-10-04/07b-logo-dialog-missing-file):
  # As an operator whose manual logo's file was lost,
  # I want the Manage-logo dialog to say the file is gone and how to set it
  # again, and to let me remove it,
  # so that it never tells me a manual logo is set, nor that I chose "no
  # logo", for a logo I lost.
  #
  # Acceptance criteria:
  # - The dialog on a marked locked manual row reads "The stored logo file is
  #   missing. Set it again from an image URL, or remove the logo.", never
  #   "This security is set to have no logo." nor the manual-logo sentence.
  # - "Remove logo" is enabled there; it stays disabled on the "no logo"
  #   choice.
  # - The image URL field is empty: never prefilled with a stored local path,
  #   on a marked row nor on a manual logo whose file is there.
  # - Saving an image URL there stores the logo again, clears the mark, and
  #   the row renders the image.
  test "the manage-logo dialog names a missing logo file and keeps the way back open",
       %{conn: conn} do
    prior = Application.get_env(:portfolixir, :logo_discovery_opts, [])

    tmp =
      Path.join(System.tmp_dir!(), "portfolixir-logo-redo-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp)
    Application.put_env(:portfolixir, :logo_discovery_opts, req: png_stub(), storage_dir: tmp)

    on_exit(fn ->
      Application.put_env(:portfolixir, :logo_discovery_opts, prior)
      File.rm_rf(tmp)
    end)

    create = fn name ->
      {:ok, security} =
        Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
          name: name,
          currency_code: "USD",
          provider: "manual",
          asset_class: "equity"
        })

      security
    end

    sec = create.("Lanzhuo")
    present = create.("Meridian")
    chosen = create.("Nordwind")

    for security <- [sec, present] do
      {:ok, _} =
        Catalog.put_logo_attributes(security, %{
          "logo_path" => "/security_logos/#{security.id}.png",
          "logo_source" => "manual",
          "logo_locked" => true
        })
    end

    File.write!(Path.join(tmp, "#{present.id}.png"), @png)
    {:ok, _} = LogoStore.remove_logo(chosen, storage_dir: tmp)

    assert {:ok, %{marked: 1}} = LogoStore.reconcile_missing_files(storage_dir: tmp)

    {:ok, view, _html} = live(conn, "/securities")
    remove = "#logo-override-dialog button[phx-click='remove_logo_override']"
    url = "#logo-override-url"

    html =
      render_hook(view, "row_action", %{"action" => "manage_logo", "id" => to_string(sec.id)})

    assert html =~
             "The stored logo file is missing. Set it again from an image URL, or remove the logo."

    refute html =~ "This security is set to have no logo."
    refute html =~ "A manual logo is set"
    refute html =~ "No logo found yet."
    assert has_element?(view, remove <> ":not([disabled])")
    assert has_element?(view, url <> "[value='']")
    assert has_element?(view, "#logo-override-dialog form[phx-submit='save_logo_url']")

    # A manual logo whose file is there: its local path is not an image URL.
    render_hook(view, "close_logo_dialog", %{})
    render_hook(view, "row_action", %{"action" => "manage_logo", "id" => to_string(present.id)})
    assert render(view) =~ "A manual logo is set"
    assert has_element?(view, url <> "[value='']")

    # The "no logo" choice: nothing left to remove.
    render_hook(view, "close_logo_dialog", %{})
    render_hook(view, "row_action", %{"action" => "manage_logo", "id" => to_string(chosen.id)})
    assert render(view) =~ "This security is set to have no logo."
    assert has_element?(view, remove <> "[disabled]")

    render_hook(view, "close_logo_dialog", %{})
    render_hook(view, "row_action", %{"action" => "manage_logo", "id" => to_string(sec.id)})
    render_hook(view, "save_logo_url", %{"logo" => %{"url" => "https://example.test/logo.png"}})

    status = Catalog.logo_status(Catalog.get_security!(sec.id))
    assert status.has_logo
    refute status.file_missing
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
        name: "Lanzhuo",
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
