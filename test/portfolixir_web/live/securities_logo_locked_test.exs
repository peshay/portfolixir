defmodule PortfolixirWeb.SecuritiesLogoLockedTest do
  # The Securities page's "Update logo" and "Search again" go through the
  # same locked-security check as the API's POST .../logo/discover (#1271).
  # No network: any outbound request runs into a recording Req `plug:` stub.
  use PortfolixirWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog

  # 1x1 PNG
  @png <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8,
         6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 250, 207, 0, 0,
         0, 3, 0, 1, 5, 12, 60, 192, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130>>

  @auth {"authorization", "Bearer test-api-token"}

  # Records every request a lookup makes, then answers with an image.
  defp recording_stub(test_pid) do
    [
      plug: fn conn ->
        send(test_pid, {:outbound, conn.host, conn.request_path})

        conn
        |> Plug.Conn.put_resp_content_type("image/png")
        |> Plug.Conn.send_resp(200, @png)
      end
    ]
  end

  setup do
    tmp = Path.join(System.tmp_dir!(), "logo-locked-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    prior = Application.get_env(:portfolixir, :logo_discovery_opts, [])

    Application.put_env(:portfolixir, :logo_discovery_opts,
      req: recording_stub(self()),
      storage_dir: tmp
    )

    on_exit(fn ->
      Application.put_env(:portfolixir, :logo_discovery_opts, prior)
      File.rm_rf(tmp)
    end)

    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Lanzhuo Inc.",
        currency_code: "USD",
        provider: "manual",
        asset_class: "equity"
      })

    {:ok, locked} =
      Catalog.put_logo_attributes(Actor.owner_ui(), security, %{
        "logo_path" => "/security_logos/#{security.id}.png",
        "logo_source" => "manual",
        "logo_locked" => true
      })

    %{locked: locked}
  end

  defp await_logo_result(view, tries \\ 100)
  defp await_logo_result(view, 0), do: render(view)

  defp await_logo_result(view, tries) do
    html = render(view)

    if html =~ "Looking up logo…" do
      Process.sleep(20)
      await_logo_result(view, tries - 1)
    else
      html
    end
  end

  # User story (#1271):
  # As the operator who locked a security's logo by choosing it by hand,
  # I want "Update logo" on the Securities page to leave that logo alone,
  # as the API's rediscovery already does,
  # so that the screen and the agent get the same answer (ADR-0002) and a
  # click on the page cannot replace a logo the API refuses to replace.
  #
  # Acceptance criteria:
  # - "Update logo" and the dialog's "Search again" on a locked row make no
  #   lookup request and keep the logo's path, source and lock unchanged.
  # - The page answers "No logo source available", the note for the API's
  #   `"result": "no_source"`, which the API answers for the same row.
  test "a locked security's logo update is refused on the page as on the API",
       %{conn: conn, locked: locked} do
    before = Catalog.logo_status(locked)
    {:ok, view, _html} = live(conn, "/securities")
    update = %{"action" => "update_logo", "id" => Integer.to_string(locked.id)}

    render_hook(view, "row_action", update)
    assert await_logo_result(view) =~ "No logo source available"

    render_click(view, "row_action", %{"action" => "manage_logo", "id" => "#{locked.id}"})
    render_hook(view, "row_action", update)
    assert await_logo_result(view) =~ "No logo source available"

    refute_received {:outbound, _host, _path}
    assert Catalog.logo_status(Catalog.get_security(locked.id)) == before

    api =
      build_conn()
      |> put_req_header(elem(@auth, 0), elem(@auth, 1))
      |> post("/api/v1/securities/#{locked.id}/logo/discover")
      |> json_response(200)

    assert api["data"]["result"] == "no_source"
    assert Catalog.logo_status(Catalog.get_security(locked.id)) == before
  end
end
