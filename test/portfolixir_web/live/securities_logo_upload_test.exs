defmodule PortfolixirWeb.SecuritiesLogoUploadTest do
  # The Manage-logo dialog sets a manual logo from a file the operator's
  # browser uploads; the server never fetches an address typed into the page.
  # No network: an outbound request would run into a recording Req `plug:`
  # stub, and names resolve through Portfolixir.Net.FakeResolver.
  use PortfolixirWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.LogoStore
  alias Portfolixir.Journal
  alias PortfolixirWeb.Securities.LogoOverrideDialog

  # A host nobody configured: not a provider, resolves to a public address.
  @collector "collector.example"

  # 1x1 PNG
  @png <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8,
         6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 250, 207, 0, 0,
         0, 3, 0, 1, 5, 12, 60, 192, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130>>

  # The collector: records every request that reaches it, then answers with
  # an HTML page (a beacon endpoint, not an image).
  defp collector_stub(test_pid) do
    [
      plug: fn conn ->
        send(test_pid, {:outbound, conn.host, conn.request_path, conn.query_string})

        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(200, "<html><body>thanks</body></html>")
      end
    ]
  end

  # The requests the collector saw, as {host, path, query}. The stub sends
  # from Http.get's task before the request returns; 200 ms covers delivery.
  defp outbound(acc \\ []) do
    receive do
      {:outbound, host, path, query} -> outbound([{host, path, query} | acc])
    after
      if(acc == [], do: 200, else: 0) -> Enum.reverse(acc)
    end
  end

  setup do
    tmp = Path.join(System.tmp_dir!(), "logo-upload-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)

    prior = Application.get_env(:portfolixir, :logo_discovery_opts, [])

    Application.put_env(:portfolixir, :logo_discovery_opts,
      req: collector_stub(self()),
      storage_dir: tmp
    )

    on_exit(fn ->
      Application.put_env(:portfolixir, :logo_discovery_opts, prior)
      File.rm_rf(tmp)
    end)

    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Synthetic Holding AG",
        ticker_symbol: "SYNH",
        currency_code: "EUR",
        provider: "manual",
        asset_class: "equity"
      })

    %{tmp: tmp, security: security}
  end

  defp open_dialog(conn, security) do
    {:ok, view, _html} = live(conn, "/securities")
    render_hook(view, "row_action", %{"action" => "manage_logo", "id" => to_string(security.id)})
    view
  end

  defp choose(view, name, content, type) do
    file_input(view, "#logo-upload-form", :logo, [
      %{name: name, content: content, type: type, last_modified: 1_700_000_000_000}
    ])
  end

  # User story (security review 2026-10-12, H38):
  # As the operator setting a logo discovery missed,
  # I want the Manage-logo dialog to take the image from my own machine,
  # so that nothing typed into the page ever makes the server reach out to an
  # address of the typist's choosing.
  #
  # Acceptance criteria:
  # - The dialog offers a file upload and no image-URL field.
  # - An image-URL event pushed at the page sends no request anywhere and
  #   stores nothing.
  test "the Manage-logo dialog takes an upload and never fetches an address typed into it",
       %{conn: conn, security: security} do
    view = open_dialog(conn, security)

    render_hook(view, "save_logo_url", %{
      "logo" => %{"url" => "https://#{@collector}/ui.png?from=open-ui-click"}
    })

    assert outbound() == []
    refute Catalog.logo_status(Catalog.get_security!(security.id)).has_logo

    render_hook(view, "row_action", %{"action" => "manage_logo", "id" => to_string(security.id)})
    assert has_element?(view, "#logo-upload-form input[type=file]")
    refute has_element?(view, "#logo-override-dialog input[type=url]")
    refute has_element?(view, "#logo-override-dialog form[phx-submit='save_logo_url']")
  end

  # User story (security review 2026-10-12, H38; board 01 of
  # ux-design-2026-10-27):
  # As the operator choosing a logo file,
  # I want to see the file I chose before it is stored, and a refused file
  # named under the chooser in my language,
  # so that I store the image I meant and know why another one was refused.
  #
  # Acceptance criteria:
  # - Nothing chosen: "Image file" (a label of the file input), "Choose
  #   image…", the basis line naming
  #   PNG, JPEG or WebP and the store's own size limit, "Save logo" disabled.
  # - A chosen PNG shows its name and a × "Remove the selection"; "Save logo"
  #   is enabled; saving stores it as a locked manual logo, closes the dialog,
  #   says "Logo updated", and no request leaves the server; the journal
  #   names the operator.
  # - A file the upload refuses (too large, wrong type) is a field error under
  #   the chooser with the Imports page's words, the input aria-invalid and
  #   described by it; a file whose bytes are not the image its type names is
  #   refused after the upload with "The file is not a readable image." and
  #   nothing is stored.
  # - The accept list and the size limit are LogoStore's own.
  test "the upload's three states: nothing chosen, a file chosen, a file refused",
       %{conn: conn, security: security, tmp: tmp} do
    view = open_dialog(conn, security)
    html = render(view)

    assert html =~ "Image file"

    # The field's name is a label of the file input, so the input is named
    # "Image file" first, the chooser's words after it.
    [input_id] =
      view
      |> element("#logo-upload-form input[type=file]")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.attribute("id")

    assert has_element?(view, ~s(#logo-upload-form label[for="#{input_id}"]), "Image file")
    assert has_element?(view, ~s(#logo-upload-form label[for="#{input_id}"]), "Choose image…")
    assert html =~ "Choose image…"
    assert html =~ "PNG, JPEG or WebP, at most 256 KB."
    assert has_element?(view, "#logo-upload-form button[type=submit][disabled]")

    [accept] =
      view
      |> element("#logo-upload-form input[type=file]")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.attribute("accept")

    assert accept |> String.split(",") |> Enum.sort() ==
             Enum.sort(LogoStore.upload_accept())

    assert LogoStore.upload_max_bytes() == 256 * 1024

    # Too large: refused before anything is stored.
    big = choose(view, "arbolia-banner.png", @png <> :binary.copy(<<0>>, 300 * 1024), "image/png")
    render_upload(big, "arbolia-banner.png")
    assert has_element?(view, "#logo-upload-error.field-error", "File too large.")
    assert has_element?(view, "#logo-upload-form input[type=file][aria-invalid=true]")
    assert has_element?(view, "#logo-upload-form button[type=submit][disabled]")

    view |> element("#logo-upload-form button[data-role=clear-logo-file]") |> render_click()
    refute render(view) =~ "File too large."

    # Bytes that are not the image their type names.
    fake = choose(view, "not-an-image.png", "GIF89a not a png at all", "image/png")
    render_upload(fake, "not-an-image.png")
    html = view |> element("#logo-upload-form") |> render_submit()
    assert html =~ "The file is not a readable image."

    assert has_element?(
             view,
             "#logo-upload-error.field-error",
             "The file is not a readable image."
           )

    assert has_element?(view, "#logo-upload-form input[type=file][aria-invalid=true]")
    assert File.ls!(tmp) == []

    view |> element("#logo-upload-form button[data-role=clear-logo-file]") |> render_click()

    # A chosen PNG: its name, the clear button, Save enabled; saving stores it.
    good = choose(view, "arbolia-logo.png", @png, "image/png")
    render_upload(good, "arbolia-logo.png")
    html = render(view)
    assert html =~ "arbolia-logo.png"
    assert html =~ "Remove the selection"
    refute has_element?(view, "#logo-upload-form button[type=submit][disabled]")

    html = view |> element("#logo-upload-form") |> render_submit()
    assert html =~ "Logo updated"
    refute has_element?(view, "#logo-override-dialog")

    status = Catalog.logo_status(Catalog.get_security!(security.id))
    assert status.has_logo
    assert status.locked
    assert status.source == "manual"
    assert File.read!(Path.join(tmp, "#{security.id}.png")) == @png
    assert outbound() == []

    # The write is the operator's, and the journal says so.
    assert [resource_type: "security", resource_id: to_string(security.id)]
           |> Journal.list_entries()
           |> Enum.any?(&(&1.actor_type == :owner_ui and &1.operation == :update))
  end

  test "a file of a type the store does not take is refused under the chooser",
       %{conn: conn, security: security} do
    view = open_dialog(conn, security)
    gif = choose(view, "arbolia.gif", "GIF89a", "image/gif")
    render_upload(gif, "arbolia.gif")
    assert has_element?(view, "#logo-upload-error.field-error", "File type not accepted.")
  end

  test "the German dialog carries the upload's strings", %{conn: conn, security: security} do
    conn = put_req_header(conn, "accept-language", "de-DE,de;q=0.9")
    html = conn |> open_dialog(security) |> render()

    assert html =~ "Bilddatei"
    assert html =~ "Bild wählen…"
    assert html =~ "PNG, JPEG oder WebP, höchstens 256 KB."
    assert html =~ "Logo speichern"
  end

  # User story (board 01 of ux-design-2026-10-27, found while drawing 1;
  # EXPERIENCE.md → Amendment 2026-09-12 → Voice and Tone):
  # As the operator reading where a logo came from,
  # I want the dialog to name the source in words,
  # so that no stored adapter name reaches the sentence.
  #
  # Acceptance criteria:
  # - Every source the logo store can write has a label: "manually uploaded"
  #   for the manual source, "found automatically" for every discovery
  #   adapter; none is the stored value, none carries an underscore.
  # - A logo with no recorded source reads "found automatically" too.
  # - The German catalog carries both labels.
  # - The rendered dialog never contains the stored source value.
  test "the logo source is named by a label, never by its stored value",
       %{conn: conn, security: security} do
    sources =
      :portfolixir
      |> Application.get_env(LogoStore, [])
      |> Keyword.fetch!(:allowed_hosts)
      |> Map.keys()
      |> Enum.map(&Atom.to_string/1)

    assert "manual" in sources

    for source <- [nil | sources] do
      label = LogoOverrideDialog.source_label(source)
      assert is_binary(label) and label != "", inspect(source)
      refute label == source, inspect(source)
      refute label =~ "_", inspect(source)
    end

    assert LogoOverrideDialog.source_label("manual") == "manually uploaded"
    assert LogoOverrideDialog.source_label("companieslogo") == "found automatically"
    assert LogoOverrideDialog.source_label(nil) == "found automatically"

    Gettext.with_locale(PortfolixirWeb.Gettext, "de", fn ->
      assert LogoOverrideDialog.source_label("manual") == "manuell hochgeladen"
      assert LogoOverrideDialog.source_label("wikipedia") == "automatisch gefunden"
    end)

    {:ok, _} =
      Catalog.put_logo_attributes(security, %{
        "logo_path" => "/security_logos/#{security.id}.png",
        "logo_source" => "companieslogo"
      })

    html = conn |> open_dialog(security) |> render()
    assert html =~ "Current logo source: found automatically"
    refute html =~ "companieslogo"
  end
end
