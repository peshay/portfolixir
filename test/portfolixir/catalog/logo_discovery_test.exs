defmodule Portfolixir.Catalog.LogoDiscoveryTest do
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.LogoDiscovery

  @png <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8,
         6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 250, 207, 0, 0,
         0, 3, 0, 1, 5, 12, 60, 192, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130>>

  defp logo_stub do
    [
      plug: fn conn ->
        cond do
          conn.request_path =~ "/api/rest_v1/page/summary/" ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(
              200,
              Jason.encode!(%{
                "originalimage" => %{"source" => "https://example.test/logo.png"}
              })
            )

          conn.request_path == "/logo.png" ->
            conn
            |> Plug.Conn.put_resp_content_type("image/png")
            |> Plug.Conn.send_resp(200, @png)

          true ->
            Plug.Conn.send_resp(conn, 404, "not found")
        end
      end
    ]
  end

  defp wait_until(fun, attempts \\ 40)

  defp wait_until(fun, attempts) when attempts > 0 do
    case fun.() do
      nil ->
        Process.sleep(50)
        wait_until(fun, attempts - 1)

      false ->
        Process.sleep(50)
        wait_until(fun, attempts - 1)

      value ->
        value
    end
  end

  defp wait_until(fun, _attempts), do: fun.()

  # User story:
  # As a local portfolio maintainer importing many securities at once,
  # I want Portfolixir to keep looking for missing logos in the background,
  # so that newly created Aktien/ETFs get logos without row-by-row clicks
  # while Staatsanleihen keep their ISIN country flag fallback.
  #
  # Acceptance criteria:
  # - The background process can enqueue all missing-logo candidates.
  # - Equity and ETF candidates are looked up and stored with fake HTTP only.
  # - Government bonds are skipped because their visible fallback is the flag.
  test "background queue fills missing stock and ETF logos but skips government bonds" do
    prior_enabled = Application.get_env(:portfolixir, :enable_logo_discovery, false)
    prior_opts = Application.get_env(:portfolixir, :logo_discovery_opts, [])

    tmp =
      Path.join(
        System.tmp_dir!(),
        "portfolixir-logo-queue-#{System.unique_integer([:positive])}"
      )

    Application.put_env(:portfolixir, :enable_logo_discovery, false)

    {:ok, apple} =
      Catalog.create_security(%{
        name: "Apple Inc.",
        currency_code: "USD",
        provider: "portfolio_performance",
        feed: "PORTFOLIO_PERFORMANCE"
      })

    {:ok, etf} =
      Catalog.create_security(%{
        name: "iShares Core MSCI World UCITS ETF",
        currency_code: "EUR",
        provider: "portfolio_performance",
        feed: "PORTFOLIO_PERFORMANCE"
      })

    {:ok, bond} =
      Catalog.create_security(%{
        name: "Anleihe USA 20/50",
        isin: "US912810SN90",
        currency_code: "USD",
        provider: "portfolio_performance",
        feed: "PORTFOLIO_PERFORMANCE"
      })

    Application.put_env(:portfolixir, :enable_logo_discovery, true)
    Application.put_env(:portfolixir, :logo_discovery_opts, req: logo_stub(), storage_dir: tmp)

    try do
      assert :ok = LogoDiscovery.enqueue_missing_security_logos()

      assert wait_until(fn ->
               [apple.id, etf.id]
               |> Enum.map(&Catalog.get_security!/1)
               |> Enum.all?(& &1.attributes["logo_path"])
             end)

      assert Catalog.get_security!(apple.id).attributes["logo_path"] ==
               "/security_logos/#{apple.id}.png"

      assert Catalog.get_security!(etf.id).attributes["logo_path"] ==
               "/security_logos/#{etf.id}.png"

      refute Catalog.get_security!(bond.id).attributes["logo_path"]
      assert File.exists?(Path.join(tmp, "#{apple.id}.png"))
      assert File.exists?(Path.join(tmp, "#{etf.id}.png"))
      refute File.exists?(Path.join(tmp, "#{bond.id}.png"))
    after
      Application.put_env(:portfolixir, :enable_logo_discovery, prior_enabled)
      Application.put_env(:portfolixir, :logo_discovery_opts, prior_opts)
      File.rm_rf(tmp)
    end
  end

  # User story:
  # As a local portfolio maintainer with securities imported before logo
  # discovery was reliable,
  # I want the background process to pick up missing logos after the app starts,
  # so that I do not need a manual bulk action just to backfill old rows.
  #
  # Acceptance criteria:
  # - Startup of the logo queue scans existing logo-less candidates.
  # - The scan remains gated by the normal logo discovery config.
  # - Tests use fake Wikipedia/image responses and temporary storage only.
  test "startup scan enqueues existing missing-logo candidates" do
    prior_enabled = Application.get_env(:portfolixir, :enable_logo_discovery, false)
    prior_opts = Application.get_env(:portfolixir, :logo_discovery_opts, [])

    tmp =
      Path.join(
        System.tmp_dir!(),
        "portfolixir-logo-startup-#{System.unique_integer([:positive])}"
      )

    Application.put_env(:portfolixir, :enable_logo_discovery, false)

    {:ok, security} =
      Catalog.create_security(%{
        name: "Tesla, Inc.",
        currency_code: "USD",
        provider: "portfolio_performance",
        feed: "PORTFOLIO_PERFORMANCE"
      })

    Application.put_env(:portfolixir, :enable_logo_discovery, true)
    Application.put_env(:portfolixir, :logo_discovery_opts, req: logo_stub(), storage_dir: tmp)

    name = {:global, {__MODULE__, self(), System.unique_integer([:positive])}}

    try do
      start_supervised!({LogoDiscovery, name: name})

      assert wait_until(fn ->
               Catalog.get_security!(security.id).attributes["logo_path"]
             end) == "/security_logos/#{security.id}.png"

      assert File.exists?(Path.join(tmp, "#{security.id}.png"))
    after
      Application.put_env(:portfolixir, :enable_logo_discovery, prior_enabled)
      Application.put_env(:portfolixir, :logo_discovery_opts, prior_opts)
      File.rm_rf(tmp)
    end
  end

  # User story:
  # As a maintainer who deliberately removed a logo (or set a manual one),
  # I want background discovery to leave that security alone, so my choice
  # is never silently overwritten on the next scan.
  test "background queue skips securities locked to a manual/no-logo choice" do
    prior_enabled = Application.get_env(:portfolixir, :enable_logo_discovery, false)
    prior_opts = Application.get_env(:portfolixir, :logo_discovery_opts, [])

    tmp =
      Path.join(
        System.tmp_dir!(),
        "portfolixir-logo-locked-#{System.unique_integer([:positive])}"
      )

    Application.put_env(:portfolixir, :enable_logo_discovery, false)

    {:ok, candidate} =
      Catalog.create_security(%{
        name: "Apple Inc.",
        currency_code: "USD",
        provider: "portfolio_performance",
        feed: "PORTFOLIO_PERFORMANCE"
      })

    # Lock it to "no logo" — this is the state set by removing a logo.
    {:ok, locked} = Catalog.remove_logo(candidate, storage_dir: tmp)
    assert locked.attributes["logo_locked"] == true

    Application.put_env(:portfolixir, :enable_logo_discovery, true)
    Application.put_env(:portfolixir, :logo_discovery_opts, req: logo_stub(), storage_dir: tmp)

    try do
      assert :ok = LogoDiscovery.enqueue_missing_security_logos()
      # Give the queue a chance to (not) act.
      Process.sleep(200)

      refute Catalog.get_security!(candidate.id).attributes["logo_path"]
      refute File.exists?(Path.join(tmp, "#{candidate.id}.png"))
    after
      Application.put_env(:portfolixir, :enable_logo_discovery, prior_enabled)
      Application.put_env(:portfolixir, :logo_discovery_opts, prior_opts)
      File.rm_rf(tmp)
    end
  end
end
