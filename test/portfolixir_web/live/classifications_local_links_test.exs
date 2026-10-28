defmodule PortfolixirWeb.ClassificationsLocalLinksTest do
  use PortfolixirWeb.ConnCase

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Auth.Throttle
  alias Portfolixir.Buckets
  alias Portfolixir.Classifications

  @origin "http://www.example.com"
  @past_bigint "99999999999999999999"
  @password "local-links-synthetic-password"

  defp classification! do
    {:ok, classification} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Synthetic Tree"})

    classification
  end

  defp view! do
    {:ok, view} =
      Buckets.create_view(Actor.owner_ui(), %{name: "Synthetic View", include_all: true})

    view
  end

  # The hrefs of the locale switch and the view chips, by their ids.
  defp control_hrefs(html, ids) do
    doc = Floki.parse_document!(html)

    for id <- ids do
      case Floki.attribute(doc, "a##{id}", "href") do
        [href] -> {id, href}
        other -> flunk("expected exactly one a##{id}, got #{inspect(other)}")
      end
    end
  end

  # Where a browser goes when the link is clicked on a page at `page_url`.
  defp resolved_host(page_url, href), do: URI.merge(page_url, href).host

  defp assert_stays_on_instance(page_url, hrefs) do
    offsite =
      for {id, href} <- hrefs,
          String.starts_with?(href, "//") or resolved_host(page_url, href) != "www.example.com",
          do: {id, href, resolved_host(page_url, href)}

    assert offsite == [],
           "links on #{page_url} leave the instance (id, href, host a browser resolves): " <>
             inspect(offsite)
  end

  defp all_scheme_relative_hrefs(html) do
    html
    |> Floki.parse_document!()
    |> Floki.attribute("a", "href")
    |> Enum.filter(&String.starts_with?(&1, "//"))
  end

  # User story (security review 2026-10-12, H26):
  # As the operator clicking the language switch or a view chip on the
  # Classifications page,
  # I want every such link to point at a path on my own instance,
  # so that a control that looks like the app's own never leaves it, however
  # the address I opened was spelled.
  #
  # Acceptance criteria:
  # - The page builds its links from its route, never from the request's raw
  #   path: the locale and view hrefs are local paths under /classifications,
  #   on the static and the connected render, open UI or logged in.
  # - No link on the page is scheme-relative.
  # - The id-range guard builds its redirect from a normalised path, so an
  #   address the router accepts answers its redirect, never a 500.
  describe "the Classifications page links are local paths" do
    test "the index: the language links stay on the instance", %{conn: conn} do
      page = @origin <> "//classifications"
      response = get(conn, page)

      assert response.request_path == "//classifications"
      html = html_response(response, 200)

      assert_stays_on_instance(page, control_hrefs(html, ~w(locale-en locale-de)))
      assert all_scheme_relative_hrefs(html) == []
    end

    test "a tree with a view: locale and view chips stay on the instance, static and connected",
         %{conn: conn} do
      classification = classification!()
      view = view!()
      page = "#{@origin}//classifications/#{classification.id}"
      ids = ["locale-en", "locale-de", "view-switch-total", "view-switch-#{view.id}"]

      {:ok, live_view, static_html} = live(conn, page)
      connected_html = render(live_view)

      offsite =
        for {label, html} <- [static: static_html, connected: connected_html],
            {id, href} <- control_hrefs(html, ids),
            not String.starts_with?(href, "/classifications/#{classification.id}?") or
              resolved_host(page, href) != "www.example.com",
            do: {label, id, href, resolved_host(page, href)}

      assert offsite == [],
             "links leave the instance (render, id, href, host a browser resolves): " <>
               inspect(offsite)

      assert all_scheme_relative_hrefs(static_html) == []
      assert all_scheme_relative_hrefs(connected_html) == []
    end

    test "the new form and a tripled slash: no scheme-relative link", %{conn: conn} do
      offsite =
        for page <- [@origin <> "//classifications/new", @origin <> "///classifications"],
            html = conn |> get(page) |> html_response(200),
            {id, href} <- control_hrefs(html, ~w(locale-en locale-de)),
            String.starts_with?(href, "//") or resolved_host(page, href) != "www.example.com",
            do: {page, id, href, resolved_host(page, href)}

      assert offsite == [],
             "links leave the instance (page, id, href, host a browser resolves): " <>
               inspect(offsite)
    end
  end

  describe "with a UI password configured" do
    setup do
      previous = Application.get_env(:portfolixir, :ui_password)
      Application.put_env(:portfolixir, :ui_password, @password)
      on_exit(fn -> Application.put_env(:portfolixir, :ui_password, previous) end)
      :ok
    end

    test "an unauthenticated request returns to the root", %{conn: conn} do
      response = get(conn, @origin <> "//classifications")
      assert redirected_to(response) == "/login?to=%2F"
    end

    test "a logged-in operator gets local links too", %{conn: conn} do
      Throttle.success(:ui, Throttle.source_key(conn.remote_ip))
      logged_in = post(conn, "/login", %{"session" => %{"password" => @password}})
      assert redirected_to(logged_in) == "/"

      authed =
        conn
        |> Phoenix.ConnTest.recycle()
        |> Map.put(:remote_ip, conn.remote_ip)
        |> Plug.Test.init_test_session(Plug.Conn.get_session(logged_in))

      page = @origin <> "//classifications"
      html = authed |> get(page) |> html_response(200)
      assert_stays_on_instance(page, control_hrefs(html, ~w(locale-en locale-de)))
    end
  end

  describe "the id-range guard" do
    test "an out-of-range query id redirects to the normalised page, never a 500" do
      url = "#{@origin}//securities?id=#{@past_bigint}"

      {result, _log} =
        with_log(fn ->
          try do
            {:ok, get(build_conn(), url)}
          rescue
            exception -> {:raised, exception}
          end
        end)

      response =
        case result do
          {:ok, response} -> response
          {:raised, exception} -> flunk("#{url} raised: " <> Exception.message(exception))
        end

      assert redirected_to(response, 302) == "/securities"
    end
  end
end
