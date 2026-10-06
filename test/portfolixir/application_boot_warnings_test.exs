defmodule Portfolixir.ApplicationBootWarningsTest do
  # The wiring changes the application environment, so the module runs alone.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Portfolixir.RuntimeConfig

  # User story (#930):
  # As an operator who turned on PHX_FORCE_SSL in the Compose deployment,
  # I want the trusted-proxies decision logged at boot beside the UI-password
  # checks,
  # so that the warning reaches the log the operator reads, not only a unit test.
  #
  # Acceptance criteria:
  # - With :force_ssl on, the endpoint's [:http, :ip] beyond loopback and
  #   :trusted_proxies empty, warn_if_exposed/0 logs one warning naming
  #   PORTFOLIXIR_TRUSTED_PROXIES.
  # - With a trusted proxy configured, it logs no such warning.
  # - It returns :ok either way: a warning, never a refusal.
  setup do
    keys = [:force_ssl, :trusted_proxies, PortfolixirWeb.Endpoint]
    previous = Map.new(keys, &{&1, Application.fetch_env(:portfolixir, &1)})

    on_exit(fn ->
      for {key, value} <- previous do
        case value do
          {:ok, value} -> Application.put_env(:portfolixir, key, value)
          :error -> Application.delete_env(:portfolixir, key)
        end
      end
    end)

    endpoint = Application.get_env(:portfolixir, PortfolixirWeb.Endpoint, [])
    http = Keyword.put(Keyword.get(endpoint, :http, []), :ip, {0, 0, 0, 0})
    Application.put_env(:portfolixir, PortfolixirWeb.Endpoint, Keyword.put(endpoint, :http, http))
    Application.put_env(:portfolixir, :force_ssl, RuntimeConfig.force_ssl_opts("true", nil))

    :ok
  end

  test "logs the trusted-proxies warning at boot when force SSL meets no trusted proxy" do
    Application.put_env(:portfolixir, :trusted_proxies, [])

    log =
      capture_log([level: :warning], fn ->
        assert Portfolixir.Application.warn_if_exposed() == :ok
      end)

    {:warn, message} =
      RuntimeConfig.trusted_proxies_warning(
        RuntimeConfig.force_ssl_opts("true", nil),
        {0, 0, 0, 0},
        []
      )

    assert log =~ message
    assert length(String.split(log, message)) == 2, "logged once"
  end

  test "logs no trusted-proxies warning once a proxy is named" do
    Application.put_env(
      :portfolixir,
      :trusted_proxies,
      RuntimeConfig.trusted_proxies("172.18.0.1")
    )

    log =
      capture_log([level: :warning], fn ->
        assert Portfolixir.Application.warn_if_exposed() == :ok
      end)

    refute log =~ "PORTFOLIXIR_TRUSTED_PROXIES"
  end

  # #930, review passes 1 and 2: a loopback-only list gives the loop warning;
  # the entries the variable held that did not parse get a warning of their
  # own, read from the variable itself, whatever PHX_FORCE_SSL and the bind.
  test "logs the loop warning for a loopback-only list and names unreadable entries on their own" do
    previous = System.get_env("PORTFOLIXIR_TRUSTED_PROXIES")

    on_exit(fn ->
      if previous,
        do: System.put_env("PORTFOLIXIR_TRUSTED_PROXIES", previous),
        else: System.delete_env("PORTFOLIXIR_TRUSTED_PROXIES")
    end)

    raw = "127.0.0.1, 172.18.0.l"
    System.put_env("PORTFOLIXIR_TRUSTED_PROXIES", raw)
    Application.put_env(:portfolixir, :trusted_proxies, RuntimeConfig.trusted_proxies(raw))

    log =
      capture_log([level: :warning], fn ->
        assert Portfolixir.Application.warn_if_exposed() == :ok
      end)

    assert log =~ "PORTFOLIXIR_TRUSTED_PROXIES names loopback only"
    {:warn, unreadable} = RuntimeConfig.unreadable_proxies_warning(["172.18.0.l"])
    assert log =~ unreadable

    # Force SSL off and the listener on loopback: no loop warning, but the
    # unreadable entry is still named.
    Application.put_env(:portfolixir, :force_ssl, false)
    endpoint = Application.get_env(:portfolixir, PortfolixirWeb.Endpoint, [])
    http = Keyword.put(Keyword.get(endpoint, :http, []), :ip, {127, 0, 0, 1})
    Application.put_env(:portfolixir, PortfolixirWeb.Endpoint, Keyword.put(endpoint, :http, http))

    log =
      capture_log([level: :warning], fn ->
        assert Portfolixir.Application.warn_if_exposed() == :ok
      end)

    refute log =~ "loopback only"
    assert log =~ unreadable
  end

  # #930, review pass 2: after_start/0, the step start/2 runs once the
  # supervisor is up, logs the loop warning exactly once (the seed and the
  # logo reconciliation are gated off in the test configuration).
  test "after_start/0 logs the trusted-proxies warning exactly once" do
    Application.put_env(:portfolixir, :trusted_proxies, [])

    log =
      capture_log([level: :warning], fn ->
        assert Portfolixir.Application.after_start() == :ok
      end)

    {:warn, message} =
      RuntimeConfig.trusted_proxies_warning(
        RuntimeConfig.force_ssl_opts("true", nil),
        {0, 0, 0, 0},
        []
      )

    assert length(String.split(log, message)) == 2, "logged once"
  end
end
