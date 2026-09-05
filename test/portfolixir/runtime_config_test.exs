defmodule Portfolixir.RuntimeConfigTest do
  use ExUnit.Case, async: true

  alias Portfolixir.RuntimeConfig

  # User story:
  # As an operator running Portfolixir in internal Compose,
  # I want database SSL to default off while still being configurable,
  # so that app-to-Postgres traffic inside the Compose network does not require TLS.
  #
  # Acceptance criteria:
  # - DATABASE_SSL defaults to false.
  # - The accepted true values are 1, true, and yes.
  # - Other values are parsed as false.
  test "parses DATABASE_SSL with a false default and explicit true values" do
    refute RuntimeConfig.database_ssl?(nil)
    refute RuntimeConfig.database_ssl?("")
    refute RuntimeConfig.database_ssl?("false")
    refute RuntimeConfig.database_ssl?("no")

    assert RuntimeConfig.database_ssl?("1")
    assert RuntimeConfig.database_ssl?("true")
    assert RuntimeConfig.database_ssl?("TRUE")
    assert RuntimeConfig.database_ssl?("yes")
  end

  # User story:
  # As an operator deploying Portfolixir (ADR-0045 §2, #758),
  # I want production to bind loopback unless I say otherwise,
  # so that an instance is reachable only from its own machine until I open it deliberately.
  #
  # Acceptance criteria:
  # - PHX_BIND_ALL unset or false binds 127.0.0.1; 1/true/yes binds 0.0.0.0.
  # - The allowed Host list is PHX_HOST plus localhost and 127.0.0.1, extended by
  #   PORTFOLIXIR_ALLOWED_HOSTS (comma-separated, trimmed, lower-cased, blanks dropped).
  test "binds loopback unless PHX_BIND_ALL is set" do
    assert RuntimeConfig.bind_ip(nil) == {127, 0, 0, 1}
    assert RuntimeConfig.bind_ip("false") == {127, 0, 0, 1}
    assert RuntimeConfig.bind_ip("true") == {0, 0, 0, 0}
    assert RuntimeConfig.bind_ip("YES") == {0, 0, 0, 0}
    assert RuntimeConfig.bind_ip("1") == {0, 0, 0, 0}
  end

  test "builds the allowed Host list from PHX_HOST and the extra hosts variable" do
    assert RuntimeConfig.allowed_hosts("portfolio.home", nil) ==
             ["portfolio.home", "localhost", "127.0.0.1"]

    assert RuntimeConfig.allowed_hosts("Portfolio.Home", " nas.lan ,, 192.168.1.20 ") ==
             ["portfolio.home", "localhost", "127.0.0.1", "nas.lan", "192.168.1.20"]

    assert RuntimeConfig.allowed_hosts(nil, nil) == ["localhost", "127.0.0.1"]
  end

  # User story:
  # As an operator who opened the instance to the network without a UI password,
  # I want a startup warning naming the risk and the variable,
  # so that "reachable from the network" is never a silent state.
  #
  # Acceptance criteria:
  # - Bound beyond loopback with no UI password: a warning naming ADR-0045 and PORTFOLIXIR_UI_PASSWORD.
  # - Bound to loopback, or a password set: no warning.
  test "warns when bound beyond loopback with no UI password" do
    assert {:warn, message} = RuntimeConfig.exposure_warning({0, 0, 0, 0}, nil)
    assert message =~ "ADR-0045"
    assert message =~ "PORTFOLIXIR_UI_PASSWORD"

    assert RuntimeConfig.exposure_warning({0, 0, 0, 0}, "") == {:warn, message}
    assert RuntimeConfig.exposure_warning({127, 0, 0, 1}, nil) == :ok
    assert RuntimeConfig.exposure_warning({0, 0, 0, 0}, "a-long-enough-password") == :ok
  end

  test "the IPv6 loopback is loopback too" do
    assert RuntimeConfig.exposure_warning({0, 0, 0, 0, 0, 0, 0, 1}, nil) == :ok
  end

  # The zero-arity forms read the environment; each must agree with the
  # explicit form fed the same variable, so the wiring cannot drift.
  test "the environment-reading defaults agree with the explicit forms" do
    assert RuntimeConfig.database_ssl?() ==
             RuntimeConfig.database_ssl?(System.get_env("DATABASE_SSL", "false"))

    assert RuntimeConfig.bind_ip() == RuntimeConfig.bind_ip(System.get_env("PHX_BIND_ALL"))

    assert RuntimeConfig.force_ssl_opts() ==
             RuntimeConfig.force_ssl_opts(System.get_env("PHX_FORCE_SSL"))

    assert RuntimeConfig.allowed_hosts() ==
             RuntimeConfig.allowed_hosts(
               System.get_env("PHX_HOST"),
               System.get_env("PORTFOLIXIR_ALLOWED_HOSTS")
             )
  end
end
