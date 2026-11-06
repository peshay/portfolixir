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

  defp leaked(html), do: Enum.filter(@figures, &String.contains?(html, &1))

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
end
