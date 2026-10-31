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

  # User story (security review 2026-10-12, H06):
  # As an operator who wrote a protective switch in a spelling the
  # application does not read,
  # I want the boot log to name the variable and the value,
  # so that I learn the switch is off before I rely on it.
  #
  # Acceptance criteria:
  # - With PHX_FORCE_SSL=enabled in the environment, warn_if_exposed/0 logs
  #   a warning naming PHX_FORCE_SSL and the value, and returns :ok.
  test "names an unrecognised protective switch value at boot" do
    previous = System.get_env("PHX_FORCE_SSL")

    on_exit(fn ->
      if previous,
        do: System.put_env("PHX_FORCE_SSL", previous),
        else: System.delete_env("PHX_FORCE_SSL")
    end)

    System.put_env("PHX_FORCE_SSL", "enabled")

    log =
      capture_log([level: :warning], fn ->
        assert Portfolixir.Application.warn_if_exposed() == :ok
      end)

    {:warn, message} = RuntimeConfig.switch_warning("PHX_FORCE_SSL", "enabled", false)
    assert log =~ message
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

  # The UI password as warn_if_exposed/0 reads it: the application
  # environment first, the variable second; both restored afterwards.
  defp with_ui_password(password) do
    previous_env = Application.fetch_env(:portfolixir, :ui_password)
    previous_var = System.get_env("PORTFOLIXIR_UI_PASSWORD")

    on_exit(fn ->
      case previous_env do
        {:ok, value} -> Application.put_env(:portfolixir, :ui_password, value)
        :error -> Application.delete_env(:portfolixir, :ui_password)
      end

      if previous_var,
        do: System.put_env("PORTFOLIXIR_UI_PASSWORD", previous_var),
        else: System.delete_env("PORTFOLIXIR_UI_PASSWORD")
    end)

    System.delete_env("PORTFOLIXIR_UI_PASSWORD")
    Application.put_env(:portfolixir, :ui_password, password)
  end

  # User story (security review 2026-10-12, H21):
  # As an operator who binds the web UI beyond loopback,
  # I want the exposure warning and the short-password warning written to the
  # log at boot, not only decided by a function,
  # so that dropping either from the boot wiring cannot pass unnoticed while
  # SECURITY.md and ADR-0045 still promise it.
  #
  # Acceptance criteria:
  # - Bound to 0.0.0.0 with no UI password, warn_if_exposed/0 logs the
  #   exposure warning once.
  # - Bound to 0.0.0.0 with an eight-character password, it logs the
  #   short-password warning once and no exposure warning.
  # - With a password of the minimum length, it logs neither.
  test "logs the exposure and the short-password warnings at boot" do
    Application.put_env(
      :portfolixir,
      :trusted_proxies,
      RuntimeConfig.trusted_proxies("172.18.0.1")
    )

    {:warn, exposure} = RuntimeConfig.exposure_warning({0, 0, 0, 0}, nil)
    {:warn, short} = RuntimeConfig.password_warning({0, 0, 0, 0}, "eightchr")

    with_ui_password(nil)
    log = capture_log([level: :warning], fn -> Portfolixir.Application.warn_if_exposed() end)
    assert length(String.split(log, exposure)) == 2, "the exposure warning, logged once"
    refute log =~ short

    with_ui_password("eightchr")
    log = capture_log([level: :warning], fn -> Portfolixir.Application.warn_if_exposed() end)
    assert length(String.split(log, short)) == 2, "the short-password warning, logged once"
    refute log =~ exposure

    with_ui_password(String.duplicate("p", RuntimeConfig.min_ui_password_length()))
    log = capture_log([level: :warning], fn -> Portfolixir.Application.warn_if_exposed() end)
    refute log =~ exposure
    refute log =~ short
  end
end
