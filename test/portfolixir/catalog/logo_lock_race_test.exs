defmodule Portfolixir.Catalog.LogoLockRaceTest do
  # Sprint 22's closing act (security lens, S2): a logo rediscovery reads the
  # lock from the struct it was handed, before the lookup's network
  # round-trip, so an operator's removal or override made during the lookup
  # was overwritten by the discovered logo. The discovery's write now re-reads
  # the lock under the row's lock and leaves a locked logo alone, as the logo
  # reconciliation's compare-and-set does. The race is pinned
  # deterministically: the fake provider removes the logo (which locks it)
  # before it answers. Synthetic names; no network.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Catalog

  @png <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8,
         6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 250, 207, 0, 0,
         0, 3, 0, 1, 5, 12, 60, 192, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130>>

  defp json(conn, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, Jason.encode!(body))
  end

  # User story:
  # As the operator who removes a security's logo while a "search again" is
  # still looking one up,
  # I want my removal to stand,
  # so that a lookup that started before my decision never overwrites it.
  #
  # Acceptance criteria:
  # - The rediscovery, handed the security read before the removal, answers
  #   :skip; the stored logo stays removed and locked.
  test "a lock set during the lookup is kept by the discovery's write" do
    tmp = Path.join(System.tmp_dir!(), "portfolixir-logos-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    owner = Actor.owner_ui()

    {:ok, security} =
      Catalog.create_security(owner, %{
        name: "Synthetic Coin",
        currency_code: "USD",
        provider: "coingecko",
        asset_class: "crypto",
        online_id: "synthetic-coin"
      })

    refute Catalog.logo_status(security).locked

    answer = fn conn ->
      case conn.host do
        "api.coingecko.com" ->
          # The operator's removal lands while the lookup is under way.
          {:ok, _removed} = Catalog.remove_logo(owner, security, storage_dir: tmp)
          json(conn, %{"image" => %{"large" => "https://coingecko/synthetic.png"}})

        _image_host ->
          conn |> Plug.Conn.put_resp_content_type("image/png") |> Plug.Conn.send_resp(200, @png)
      end
    end

    assert :skip = Catalog.rediscover_logo(owner, security, req: [plug: answer], storage_dir: tmp)

    stored = Catalog.get_security!(security.id)

    assert Catalog.logo_status(stored) == %{
             path: nil,
             source: nil,
             has_logo: false,
             locked: true,
             file_missing: false
           }
  end

  # User story:
  # As the operator who uploads my own logo while a "search again" is still
  # looking one up,
  # I want my uploaded file to stay as I stored it,
  # so that a lookup the database refuses leaves nothing of its own behind.
  #
  # Acceptance criteria:
  # - The upload lands during the lookup; the discovery answers :skip; the
  #   logo file holds the uploaded bytes, not the discovered ones, and no
  #   other file is left in the logo directory.
  test "a refused discovery leaves the manual logo file as it was" do
    tmp = Path.join(System.tmp_dir!(), "portfolixir-logos-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    owner = Actor.owner_ui()
    uploaded = @png <> "uploaded"
    discovered = @png <> "discovered"

    {:ok, security} =
      Catalog.create_security(owner, %{
        name: "Synthetic Coin",
        currency_code: "USD",
        provider: "coingecko",
        asset_class: "crypto",
        online_id: "synthetic-coin"
      })

    answer = fn conn ->
      case conn.host do
        "api.coingecko.com" ->
          {:ok, _stored} =
            Catalog.LogoStore.store_manual_bytes(owner, security, uploaded, "image/png",
              storage_dir: tmp
            )

          json(conn, %{"image" => %{"large" => "https://coingecko/synthetic.png"}})

        _image_host ->
          conn
          |> Plug.Conn.put_resp_content_type("image/png")
          |> Plug.Conn.send_resp(200, discovered)
      end
    end

    assert :skip = Catalog.rediscover_logo(owner, security, req: [plug: answer], storage_dir: tmp)

    assert File.read!(Path.join(tmp, "#{security.id}.png")) == uploaded
    assert File.ls!(tmp) == ["#{security.id}.png"]
    assert Catalog.logo_status(Catalog.get_security!(security.id)).source == "manual"
  end
end
