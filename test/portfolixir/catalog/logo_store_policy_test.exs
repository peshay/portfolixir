defmodule Portfolixir.Catalog.LogoStorePolicyTest do
  # Issue #762: the URL policy applied where the manual override and the
  # discovery job meet, so no caller can reach `Req.get/2` with an unchecked
  # URL. The resolver in test config never touches DNS.
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.LogoStore

  @png <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8,
         6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 250, 207, 0, 0,
         0, 3, 0, 1, 5, 12, 60, 192, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130>>

  setup do
    tmp = Path.join(System.tmp_dir!(), "portfolixir-logos-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    {:ok, sec} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Synthetic Corp.",
        currency_code: "EUR",
        provider: "manual",
        asset_class: "equity"
      })

    %{tmp: tmp, security: sec}
  end

  defp counting_png_stub(test_pid) do
    [
      plug: fn conn ->
        send(test_pid, {:fetched, conn.host <> conn.request_path})

        conn
        |> Plug.Conn.put_resp_content_type("image/png")
        |> Plug.Conn.send_resp(200, @png)
      end
    ]
  end

  # User story:
  # As an operator,
  # I want a manual logo URL that points inside my network refused before any
  # connection is made,
  # so that neither I nor my agent can turn the logo feature into a probe of my LAN.
  #
  # Acceptance criteria:
  # - A private, loopback or metadata address, or a plain-http URL, is refused
  #   with a policy error; the stub is never called and no file is written.
  test "refuses a manual URL to a non-public address without fetching",
       %{tmp: tmp, security: sec} do
    for url <- [
          "https://internal.test/logo.png",
          "https://loopback.test/logo.png",
          "https://meta.test/latest/meta-data",
          "https://10.0.0.5/logo.png",
          "http://example.test/logo.png"
        ] do
      assert {:error, {:url_not_allowed, _}} =
               LogoStore.store_manual_override(sec, url,
                 storage_dir: tmp,
                 req: counting_png_stub(self())
               ),
             url

      refute_received {:fetched, _}
    end

    assert File.ls!(tmp) == []
    assert (Catalog.get_security(sec.id).attributes || %{})["logo_path"] == nil
  end

  test "stores a manual URL to a public host", %{tmp: tmp, security: sec} do
    assert {:ok, updated} =
             LogoStore.store_manual_override(sec, "https://example.test/logo.png",
               storage_dir: tmp,
               req: counting_png_stub(self())
             )

    assert_received {:fetched, "example.test/logo.png"}
    assert updated.attributes["logo_path"] == "/security_logos/#{sec.id}.png"
  end

  # User story:
  # As the discovery job,
  # I want an image URL confined to its provider's own image host,
  # so that a poisoned provider payload cannot send the fetch elsewhere.
  #
  # Acceptance criteria:
  # - A discovery source may only fetch from the hosts configured for it
  #   (test config: coingecko -> "coingecko", wikipedia -> "wikipedia",
  #   companieslogo -> "logos"); another host is refused unfetched.
  test "confines discovery sources to their configured hosts", %{tmp: tmp, security: sec} do
    assert {:error, {:url_not_allowed, :host_not_allowed}} =
             LogoStore.download_and_store(sec, "https://evil.test/btc.png", :coingecko,
               storage_dir: tmp,
               req: counting_png_stub(self())
             )

    refute_received {:fetched, _}

    assert {:ok, _} =
             LogoStore.download_and_store(sec, "https://coingecko/btc.png", :coingecko,
               storage_dir: tmp,
               req: counting_png_stub(self())
             )

    assert_received {:fetched, "coingecko/btc.png"}
  end

  # User story (#763):
  # As an operator,
  # I want stored logo bytes checked by their magic bytes, not only by the
  # upstream Content-Type header,
  # so that an HTML or script body labelled image/png is never written next to the app's assets.
  #
  # Acceptance criteria:
  # - A body whose leading bytes are not PNG, JPEG or WebP is refused as an
  #   unsupported type even when the header says image/png; nothing is written.
  test "refuses bytes that are not an image whatever the header says", %{tmp: tmp, security: sec} do
    stub = fn content_type, body ->
      [
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type(content_type)
          |> Plug.Conn.send_resp(200, body)
        end
      ]
    end

    assert {:error, :unsupported_content_type} =
             LogoStore.download_and_store(sec, "https://example.test/x.png", :wikipedia,
               storage_dir: tmp,
               req: stub.("image/png", "<html><script>alert(1)</script></html>")
             )

    # PNG bytes under a WebP header are a mismatch too.
    assert {:error, :unsupported_content_type} =
             LogoStore.download_and_store(sec, "https://example.test/x.webp", :wikipedia,
               storage_dir: tmp,
               req: stub.("image/webp", @png)
             )

    assert File.ls!(tmp) == []

    webp = "RIFF" <> <<0, 0, 0, 0>> <> "WEBPVP8 " <> :binary.copy(<<0>>, 16)

    assert {:ok, _} =
             LogoStore.download_and_store(sec, "https://example.test/x.webp", :wikipedia,
               storage_dir: tmp,
               req: stub.("image/webp", webp)
             )
  end

  # User story:
  # As the discovery job following a Commons file redirect,
  # I want a redirect followed only when its target passes the same policy,
  # so that a redirect cannot do what a direct URL may not.
  #
  # Acceptance criteria:
  # - Req's automatic redirect following is off; the store follows at most a
  #   few hops itself, re-checking each Location.
  # - A redirect to an allowed public https host is followed and stored.
  # - A redirect to a non-public address, another scheme or a host outside the
  #   source's list is refused.
  test "follows a redirect only to an allowed target", %{tmp: tmp, security: sec} do
    test_pid = self()

    redirecting = fn target ->
      [
        plug: fn conn ->
          send(test_pid, {:fetched, conn.host <> conn.request_path})

          case conn.request_path do
            "/start.png" ->
              conn
              |> Plug.Conn.put_resp_header("location", target)
              |> Plug.Conn.send_resp(302, "")

            _ ->
              conn
              |> Plug.Conn.put_resp_content_type("image/png")
              |> Plug.Conn.send_resp(200, @png)
          end
        end
      ]
    end

    assert {:ok, _} =
             LogoStore.download_and_store(
               sec,
               "https://wikipedia/start.png",
               :wikipedia,
               storage_dir: tmp,
               req: redirecting.("https://wikipedia/final.png")
             )

    assert_received {:fetched, "wikipedia/start.png"}
    assert_received {:fetched, "wikipedia/final.png"}

    for target <- [
          "https://internal.test/final.png",
          "http://wikipedia/final.png",
          "https://evil.test/final.png"
        ] do
      assert {:error, {:url_not_allowed, _}} =
               LogoStore.download_and_store(
                 sec,
                 "https://wikipedia/start.png",
                 :wikipedia,
                 storage_dir: tmp,
                 req: redirecting.(target)
               ),
             target

      assert_received {:fetched, "wikipedia/start.png"}
      refute_received {:fetched, _}
    end
  end

  # User story (#763):
  # As the discovery job,
  # I want every upstream misbehaviour named as an error value,
  # so that a redirect loop, a bad status or a body without a type never
  # writes a file or crashes the job.
  #
  # Acceptance criteria:
  # - A redirect loop stops after a few hops; a non-2xx status is named.
  # - A body without a Content-Type is refused; a JPEG under its own header is stored.
  test "names a redirect loop, a bad status and a missing type; stores a JPEG",
       %{tmp: tmp, security: sec} do
    respond = fn fun -> [plug: fun] end

    loop =
      respond.(fn conn ->
        conn
        |> Plug.Conn.put_resp_header("location", "https://wikipedia/loop.png")
        |> Plug.Conn.send_resp(302, "")
      end)

    assert {:error, :too_many_redirects} =
             LogoStore.download_and_store(sec, "https://wikipedia/loop.png", :wikipedia,
               storage_dir: tmp,
               req: loop
             )

    missing = respond.(fn conn -> Plug.Conn.send_resp(conn, 404, "") end)

    assert {:error, {:http_status, 404}} =
             LogoStore.download_and_store(sec, "https://wikipedia/x.png", :wikipedia,
               storage_dir: tmp,
               req: missing
             )

    untyped = respond.(fn conn -> Plug.Conn.send_resp(conn, 200, @png) end)

    assert {:error, :unsupported_content_type} =
             LogoStore.download_and_store(sec, "https://wikipedia/x.png", :wikipedia,
               storage_dir: tmp,
               req: untyped
             )

    assert File.ls!(tmp) == []

    jpeg = <<0xFF, 0xD8, 0xFF, 0xE0>> <> :binary.copy(<<0>>, 16)

    jpeg_stub =
      respond.(fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("image/jpeg")
        |> Plug.Conn.send_resp(200, jpeg)
      end)

    assert {:ok, updated} =
             LogoStore.download_and_store(sec, "https://wikipedia/x.jpg", :wikipedia,
               storage_dir: tmp,
               req: jpeg_stub
             )

    assert updated.attributes["logo_path"] == "/security_logos/#{sec.id}.jpg"
  end
end
