defmodule PortfolixirWeb.ApiV1LogoAndDefaultViewJournalTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.LogoLookup
  alias Portfolixir.Journal

  @agent_token String.duplicate("a", 40)
  @default_token String.duplicate("d", 40)

  @override_url "https://beacon-host.test/pixel.png"

  # 1x1 PNG
  @png <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8,
         6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 250, 207, 0, 0,
         0, 3, 0, 1, 5, 12, 60, 192, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130>>

  # Every request answers a PNG, except the discovery source's API, which
  # names an image on its own image host.
  defp stub do
    [
      plug: fn conn ->
        case conn.host do
          "api.coingecko.com" ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(
              200,
              Jason.encode!(%{"image" => %{"large" => "https://coingecko/synthetic.png"}})
            )

          _image_host ->
            conn
            |> Plug.Conn.put_resp_content_type("image/png")
            |> Plug.Conn.send_resp(200, @png)
        end
      end
    ]
  end

  setup do
    previous_tokens = Application.get_env(:portfolixir, :api_tokens)
    prior_opts = Application.get_env(:portfolixir, :logo_discovery_opts, [])

    Application.put_env(:portfolixir, :api_tokens, [
      {"mcp", @agent_token},
      {nil, @default_token}
    ])

    tmp =
      Path.join(
        System.tmp_dir!(),
        "portfolixir-logo-journal-#{System.unique_integer([:positive])}"
      )

    Application.put_env(:portfolixir, :logo_discovery_opts, req: stub(), storage_dir: tmp)

    on_exit(fn ->
      Application.put_env(:portfolixir, :api_tokens, previous_tokens)
      Application.put_env(:portfolixir, :logo_discovery_opts, prior_opts)
      File.rm_rf(tmp)
    end)

    %{tmp: tmp}
  end

  defp api_conn(conn, token) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer " <> token)
  end

  defp create_security!(conn, token, name) do
    conn
    |> api_conn(token)
    |> post("/api/v1/securities", Jason.encode!(%{security: %{name: name, currency_code: "EUR"}}))
    |> json_response(201)
    |> get_in(["data", "id"])
  end

  defp create_coin! do
    {:ok, coin} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Synthetic Coin",
        currency_code: "USD",
        provider: "coingecko",
        asset_class: "crypto",
        online_id: "synthetic-coin"
      })

    coin
  end

  # Newest first (inserted_at desc, id desc), as GET /api/v1/journal lists them.
  defp security_entries(id),
    do: Journal.list_entries(resource_type: "security", resource_id: to_string(id))

  defp who(entry), do: {entry.actor_type, entry.actor_label}

  # User story (security review 2026-10-12, H61):
  # As the operator who gives an agent its own named API token,
  # I want a manual logo override, a logo removal and a logo rediscovery
  # journaled under the token that asked for them, with the host the override
  # was fetched from,
  # so that the journal says which credential sent the instance to which host,
  # and only the background discovery stays attributed to the logo system job.
  #
  # Acceptance criteria:
  # - PUT .../logo under a named token journals api_token_rw with the token's
  #   name, and the entry's after-image names the override's host.
  # - DELETE .../logo and POST .../logo/discover under a named token journal
  #   that token.
  # - The background discovery's write still journals system_job "logo".
  # - A control: a security create under the named token journals that token.
  test "control: a security create under the named token journals that token", %{conn: conn} do
    id = create_security!(conn, @agent_token, "Logo Journal Control")
    assert [created] = security_entries(id)
    assert who(created) == {:api_token_rw, "mcp"}
  end

  test "PUT /api/v1/securities/:id/logo under a named token journals that token", %{conn: conn} do
    id = create_security!(conn, @agent_token, "Logo Journal Override")

    assert %{"data" => %{"source" => "manual", "locked" => true}} =
             conn
             |> api_conn(@agent_token)
             |> put(
               "/api/v1/securities/#{id}/logo",
               Jason.encode!(%{logo: %{url: @override_url}})
             )
             |> json_response(200)

    [newest | _] = entries = security_entries(id)
    assert length(entries) == 2
    assert newest.operation == :update
    assert newest.after["attributes"]["logo_source"] == "manual"
    assert newest.after["attributes"]["logo_locked"] == true

    assert who(newest) == {:api_token_rw, "mcp"},
           "manual logo override journaled as #{inspect(who(newest))}, not the token"
  end

  test "the override's journal entry names the host the server was sent to", %{conn: conn} do
    id = create_security!(conn, @agent_token, "Logo Journal Host")

    conn
    |> api_conn(@agent_token)
    |> put("/api/v1/securities/#{id}/logo", Jason.encode!(%{logo: %{url: @override_url}}))
    |> json_response(200)

    [newest | _] = security_entries(id)
    recorded = Jason.encode!(%{before: newest.before, after: newest.after})

    assert recorded =~ "beacon-host.test",
           "the journal entry records only #{inspect(newest.after["attributes"])}"

    assert newest.after["attributes"]["logo_source_host"] == "beacon-host.test"
  end

  test "DELETE /api/v1/securities/:id/logo under a named token journals that token", %{
    conn: conn
  } do
    id = create_security!(conn, @agent_token, "Logo Journal Remove")

    assert %{"data" => %{"has_logo" => false, "locked" => true}} =
             conn
             |> api_conn(@agent_token)
             |> delete("/api/v1/securities/#{id}/logo")
             |> json_response(200)

    [newest | _] = security_entries(id)
    assert newest.operation == :update
    assert newest.after["attributes"]["logo_locked"] == true

    assert who(newest) == {:api_token_rw, "mcp"},
           "logo removal journaled as #{inspect(who(newest))}, not the token"
  end

  test "POST /api/v1/securities/:id/logo/discover under a named token journals that token", %{
    conn: conn
  } do
    coin = create_coin!()

    assert %{"data" => %{"result" => "updated", "source" => "coingecko"}} =
             conn
             |> api_conn(@agent_token)
             |> post("/api/v1/securities/#{coin.id}/logo/discover")
             |> json_response(200)

    [newest | _] = security_entries(coin.id)
    assert newest.after["attributes"]["logo_source"] == "coingecko"

    assert who(newest) == {:api_token_rw, "mcp"},
           "logo rediscovery journaled as #{inspect(who(newest))}, not the token"
  end

  test "the background discovery's write still journals the logo system job", %{tmp: tmp} do
    coin = create_coin!()

    assert {:ok, _updated} = LogoLookup.run(coin, req: stub(), storage_dir: tmp)

    [newest | _] = security_entries(coin.id)
    assert newest.after["attributes"]["logo_source"] == "coingecko"
    assert who(newest) == {:system_job, "logo"}
  end

  # User story (security review 2026-10-12, H61):
  # As the operator,
  # I want the default view I or an agent set journaled under whoever set it,
  # so that a switch of the scope the Wealth page and the dashboard open on
  # is attributable like every other write over the API.
  #
  # Acceptance criteria:
  # - PUT /api/v1/settings/default_view under a named token leaves a journal
  #   entry naming that token, whose after-image carries the view's id.
  # - Clearing it back to Everything journals a delete under that token.
  test "PUT /api/v1/settings/default_view under a named token leaves a journal entry naming it",
       %{conn: conn} do
    {:ok, view} =
      Portfolixir.Buckets.create_view(Actor.owner_ui(), %{
        name: "Narrow Synthetic View",
        include_all: false
      })

    before_count = length(Journal.list_entries())

    assert %{"data" => %{"view_id" => view_id}} =
             conn
             |> api_conn(@agent_token)
             |> put("/api/v1/settings/default_view", Jason.encode!(%{view_id: view.id}))
             |> json_response(200)

    assert view_id == view.id
    assert Portfolixir.Settings.default_view_id() == view.id

    entries = Journal.list_entries()
    new_entries = Enum.take(entries, length(entries) - before_count)

    assert Enum.any?(new_entries, &(who(&1) == {:api_token_rw, "mcp"})),
           "default-view switch left #{length(new_entries)} journal entries " <>
             "(#{before_count} before, #{length(entries)} after)"

    assert [set] = Journal.list_entries(resource_type: "setting")
    assert who(set) == {:api_token_rw, "mcp"}
    assert set.after["value"] == to_string(view.id)

    conn
    |> api_conn(@agent_token)
    |> put("/api/v1/settings/default_view", Jason.encode!(%{view_id: nil}))
    |> json_response(200)

    assert [cleared, ^set] = Journal.list_entries(resource_type: "setting")
    assert cleared.operation == :delete
    assert who(cleared) == {:api_token_rw, "mcp"}
  end

  # User story (security review 2026-10-12, H61):
  # As the operator,
  # I want my own logo upload and removal on the Securities page journaled
  # under the operator, not the logo system job,
  # so that the journal tells my choice from the background discovery's.
  #
  # Acceptance criteria:
  # - The page's manual logo (the dialog's upload) and its removal journal
  #   owner_ui.
  test "the UI's manual logo override journals the operator, not the logo system job", %{
    conn: conn
  } do
    {:ok, sec} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Logo Journal Ui",
        currency_code: "USD",
        provider: "manual",
        asset_class: "equity"
      })

    {:ok, view, _html} = live(conn, "/securities")
    render_hook(view, "row_action", %{"action" => "manage_logo", "id" => to_string(sec.id)})

    # The dialog's upload (H38): choose a PNG, then save it.
    view
    |> file_input("#logo-upload-form", :logo, [
      %{name: "logo.png", content: @png, type: "image/png", last_modified: 1_700_000_000_000}
    ])
    |> render_upload("logo.png")

    view |> element("#logo-upload-form") |> render_submit()

    [newest | _] = security_entries(sec.id)
    assert newest.after["attributes"]["logo_source"] == "manual"

    assert who(newest) == {:owner_ui, nil},
           "UI logo override journaled as #{inspect(who(newest))}, not owner_ui"

    render_hook(view, "remove_logo_override", %{"id" => to_string(sec.id)})

    [removed | _] = security_entries(sec.id)
    assert removed.after["attributes"]["logo_locked"] == true
    refute Map.has_key?(removed.after["attributes"], "logo_source_host")
    assert who(removed) == {:owner_ui, nil}
  end
end
