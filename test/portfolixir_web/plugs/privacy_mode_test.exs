defmodule PortfolixirWeb.PrivacyModeTest do
  # Sprint 26 P1 (I22, FR-51; plan D-4): the privacy mode's switch, per
  # browser in a signed preference cookie, and the mask on the server for a
  # LiveView's first (disconnected) render and its connected one alike. The
  # formatters' half is test/portfolixir_web/privacy_mode_format_test.exs;
  # every page of the shell is walked in a real browser by
  # test/browser/privacy_leak_test.exs.
  use PortfolixirWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures
  import PortfolixirWeb.PreferenceCookieHelpers

  alias PortfolixirWeb.UiAuth

  @cookie "portfolixir_privacy"

  defp from(conn, site), do: put_req_header(conn, "sec-fetch-site", site)

  # A world with a held position and cash: 30 shares bought at 42.10 from a
  # deposit of 5,000.00, quoted at 44.55.
  defp world! do
    world = base_world(name: "Privacy Portfolio")
    deposit!(world, "5000", ~D[2026-01-02])
    security = create_security!(name: "Privacy Fixture AG", ticker: "PFX")
    buy!(world, security, quantity: "30", price: "42.10", date: ~D[2026-01-05])
    put_quote!(security, ~D[2026-01-06], "44.55")

    {:ok, _tree} =
      Portfolixir.Classifications.create_classification(Portfolixir.Actor.owner_ui(), %{
        name: "Strategy"
      })

    world
  end

  # The figures the world puts on Wealth, in every form a page or one of
  # its attributes could carry them (English separators, raw decimals).
  @figures ~w(5,000.00 5000 1,263.00 1263 1,336.50 1336.5 3,737.00 3737 42.10 44.55 5,073.50 5073.5)

  # An id in an address (the stacked chart's `tree=` and `category=`, a
  # view's or a security's id), in a chooser's option or in an event's
  # `phx-value-*` is a row id, not a figure: a sequence that happens to
  # reach 1263 must not read as the position's market value.
  @id_sites [
    ~r/([?&;](?:amp;)?[a-z_]*(?:tree|category|id|view|portfolio)=)\d+/,
    ~r/(<option[^>]*\svalue=")\d+(?=")/,
    ~r/(\sphx-value-[a-z-]+=")\d+(?=")/
  ]

  # A figure counts where it stands as a number of its own: "44.55" inside a
  # chart's coordinate "644.55" is not the quote. A plain substring match
  # read the one-year window's x-axis as a leak on the days its spacing put
  # a coordinate on one of the figures, so the test failed by the calendar.
  defp leaked(html) do
    html = Enum.reduce(@id_sites, html, &Regex.replace(&1, &2, "\\1ID"))
    Enum.filter(@figures, &Regex.match?(~r/(?<!\d)#{Regex.escape(&1)}(?!\d)/, html))
  end

  defp switch_tag(html) do
    [tag] = Regex.run(~r/<a[^>]*id="privacy-mode"[^>]*>/, html)
    tag
  end

  # User story (P1):
  # As the operator showing Portfolixir on a screen others can see,
  # I want one switch in the top bar that hides every amount, kept for this
  # browser across a reload,
  # so that I can open any page without a figure appearing first.
  #
  # Acceptance criteria:
  # - `?privacy=on` from this origin writes the signed `portfolixir_privacy`
  #   cookie (SameSite=Lax, Path=/, a year) and answers with a redirect to
  #   the same address without the parameter, its other parameters kept;
  #   `?privacy=off` deletes the cookie.
  # - With the cookie, a page's first render (no script) and its connected
  #   render carry none of the world's figures, in the text or in an
  #   attribute, and show the placeholder; the switch is pressed and links
  #   to `?privacy=off`.
  # - Without it, the figures are there and the switch is not pressed.
  test "the switch is remembered per browser and the page renders masked before and after it connects" do
    world!()

    on = build_conn() |> from("same-origin") |> get("/portfolio?tab=allocation&privacy=on")
    assert redirected_to(on, 302) == "/portfolio?tab=allocation"
    cookie = Map.fetch!(on.resp_cookies, @cookie)
    assert cookie.same_site == "Lax"
    assert cookie.path == "/"
    assert cookie.max_age == 60 * 60 * 24 * 365
    assert remembered(on, @cookie) == "on"

    masked = fn -> build_conn() |> put_preference_cookie(@cookie, "on") end

    first = masked.() |> get("/transactions") |> html_response(200)
    assert leaked(first) == []
    assert first =~ ~r/class="?pf-mask/
    assert switch_tag(first) =~ ~s(aria-pressed="true")
    assert switch_tag(first) =~ "privacy=off"

    {:ok, view, connected} = masked.() |> live("/portfolio")
    assert leaked(connected) == []
    assert leaked(render_async(view)) == []
    assert render_async(view) =~ ~r/class="?pf-mask/

    {:ok, view, plain} = build_conn() |> live("/portfolio")
    assert leaked(render_async(view)) != []
    refute plain =~ ~r/class="?pf-mask/
    assert switch_tag(plain) =~ ~s(aria-pressed="false")
    assert switch_tag(plain) =~ "privacy=on"

    off = masked.() |> from("same-origin") |> get("/portfolio?privacy=off")
    assert redirected_to(off, 302) == "/portfolio"
    assert remembered(off, @cookie) == :deleted
  end

  # Acceptance criteria:
  # - A choice from another site is not remembered (`FetchSite`): it can
  #   hide the figures of the page it opens, never show them.
  # - The login's return path drops the parameter as it drops the other
  #   preferences.
  # - A cookie this server did not sign, or of another value, is no choice.
  test "another site can hide the figures of one page but never show them" do
    world!()

    shown =
      build_conn()
      |> put_preference_cookie(@cookie, "on")
      |> from("cross-site")
      |> get("/transactions?privacy=off")

    assert shown.status == 200
    assert leaked(html_response(shown, 200)) == []
    refute Map.has_key?(shown.resp_cookies, @cookie)

    hidden = build_conn() |> from("cross-site") |> get("/transactions?privacy=on")
    assert leaked(html_response(hidden, 200)) == []
    refute Map.has_key?(hidden.resp_cookies, @cookie)

    assert UiAuth.safe_return_path("/portfolio?privacy=off&tab=income") ==
             "/portfolio?tab=income"

    planted = build_conn() |> put_req_header("cookie", @cookie <> "=on") |> get("/transactions")
    assert leaked(html_response(planted, 200)) != []

    other = build_conn() |> put_preference_cookie(@cookie, "yes") |> get("/transactions")
    assert leaked(html_response(other, 200)) != []
  end

  # --- Sprint 26 fix P begin ---

  # User story (P1, the closing act's finding 4):
  # As the operator switching the mode on a page whose address carries a
  # list or a nested parameter,
  # I want the switch to keep the address as it was,
  # so that the switch never answers an error page.
  #
  # Acceptance criteria:
  # - `?privacy=on` beside `benchmark[]=…` or `a[b]=c` redirects to the
  #   address without it, every other pair kept as written, repeated keys
  #   and their order included.
  # - Every `privacy` pair is dropped, wherever it stands.
  # - The switch's link keeps repeated keys too, and sets one `privacy`.
  test "the switch keeps list and nested parameters, their order and repeats" do
    for {address, back} <- [
          {"/?benchmark[]=security:1&privacy=on", "/?benchmark[]=security:1"},
          {"/?a[b]=c&privacy=on", "/?a[b]=c"},
          {"/securities?cur[]=EUR&cur[]=USD&privacy=on&q=x",
           "/securities?cur[]=EUR&cur[]=USD&q=x"},
          {"/securities?privacy=off&q=a%26b&privacy=on", "/securities?q=a%26b"},
          {"/portfolio?privacy=on", "/portfolio"}
        ] do
      conn = build_conn() |> from("same-origin") |> get(address)
      assert redirected_to(conn, 302) == back, address
    end

    assert PortfolixirWeb.PrivacyMode.toggle_href("/securities?cur[]=EUR&cur[]=USD", false) ==
             "/securities?cur[]=EUR&cur[]=USD&privacy=on"

    assert PortfolixirWeb.PrivacyMode.toggle_href("/?privacy=on&a[b]=c&privacy=off", true) ==
             "/?a[b]=c&privacy=off"

    assert PortfolixirWeb.PrivacyMode.toggle_href("/cashflow", false) == "/cashflow?privacy=on"
    assert PortfolixirWeb.PrivacyMode.toggle_href(nil, false) == "/?privacy=on"
  end

  # User story (P1, the closing act's finding 5):
  # As the operator switching the mode on a security's Predictions tab or a
  # filtered list,
  # I want the switch to bring me back to the page I was on, with its tab,
  # its filters and its comparison,
  # so that switching never takes me off the page.
  #
  # Acceptance criteria:
  # - On every page the switch links to the page's own address, path and
  #   query, with `privacy` set: a security's detail with its tab, Cash
  #   flow's facet with the "After the sale" comparison, a filtered list.
  # - After a patch inside the page (a tab, a filter) the switch follows
  #   the new address.
  test "the switch keeps the page's address, its tab, filters and comparison" do
    %{security: security} = world_with_security!()

    for address <- [
          "/securities/#{security.id}?tab=predictions",
          "/securities?q=Privacy&holding=all",
          "/cashflow?tab=realized&hindsight=rate&hindsight_rate=3",
          "/predictions?author=agent",
          "/portfolio?tab=allocation",
          "/transactions?keep=1",
          "/journal?keep=1",
          "/?keep=1"
        ] do
      {:ok, _view, html} = build_conn() |> live(address)
      assert switch_href(html) == address_with(address, "on"), address
    end

    {:ok, view, _html} = build_conn() |> live("/securities/#{security.id}")
    view |> element("#detail-tab-predictions") |> render_click()

    assert switch_href(render(view)) ==
             "/securities/#{security.id}?tab=predictions&privacy=on"
  end

  defp world_with_security! do
    world = base_world(name: "Privacy Switch")
    security = create_security!(name: "Privacy Fixture AG", ticker: "PFX")
    buy!(world, security, quantity: "3", price: "10", date: ~D[2026-01-05])

    {:ok, _tree} =
      Portfolixir.Classifications.create_classification(Portfolixir.Actor.owner_ui(), %{
        name: "Strategy"
      })

    %{security: security}
  end

  defp switch_href(html) do
    [href] =
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query("#privacy-mode")
      |> LazyHTML.attribute("href")

    href
  end

  defp address_with(address, state) do
    separator = if String.contains?(address, "?"), do: "&", else: "?"
    address <> separator <> "privacy=" <> state
  end

  # --- Sprint 26 fix P end ---

  # --- Sprint 26 fix J begin ---
  # User story (P1, the closing act's follow-up to the language switch):
  # As an operator who opened a page from another site's link,
  # I want the privacy switch never to carry that link's view along, and
  # to stay on this page when its address has a doubled slash,
  # so that pressing it neither makes the foreign view my remembered one
  # nor takes me to another page.
  #
  # Acceptance criteria:
  # - On a Wealth page whose ?view= came from another site, the switch's
  #   link carries no ?view=, on Holdings and on the Allocation tab; on one
  #   whose ?view= is the remembered choice it still does (S7E-2).
  # - Every preference parameter of an address (view, benchmark, locale)
  #   is left out of the link; the page's other parameters stay as written.
  # - A doubled leading slash stays this page's path, never a host (H26),
  #   on the page's first render and in toggle_href/2.
  test "the switch drops a foreign view and keeps a doubled slash on this page" do
    Portfolixir.Classifications.ensure_builtins()

    {:ok, view} =
      Portfolixir.Buckets.create_view(Portfolixir.Actor.owner_ui(), %{name: "Retirement"})

    base_world(name: "Privacy Views")

    stored =
      build_conn()
      |> put_preference_cookie("portfolixir_view", "total")
      |> from("cross-site")

    for path <- ["/portfolio", "/portfolio?tab=allocation"] do
      separator = if path =~ "?", do: "&", else: "?"
      {:ok, page, _html} = live(stored, path <> separator <> "view=#{view.id}")
      html = render_async(page)

      assert html =~ "Retirement"
      refute switch_href(html) =~ "view=", path
    end

    {:ok, page, _html} = build_conn() |> from("same-origin") |> live("/portfolio?view=#{view.id}")
    assert switch_href(render_async(page)) =~ "view=#{view.id}"

    assert PortfolixirWeb.PrivacyMode.toggle_href(
             "/securities?view=3&q=x&benchmark[]=security:1&locale=de",
             false
           ) == "/securities?q=x&privacy=on"

    assert PortfolixirWeb.PrivacyMode.toggle_href("//securities/5?tab=predictions", false) ==
             "/securities/5?tab=predictions&privacy=on"

    %{security: security} = world_with_security!()

    html =
      build_conn()
      |> get("http://www.example.com//securities/#{security.id}?tab=predictions")
      |> html_response(200)

    assert switch_href(html) == "/securities/#{security.id}?tab=predictions&privacy=on"
  end

  # --- Sprint 26 fix J end ---
end
