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
             RuntimeConfig.force_ssl_opts(
               System.get_env("PHX_FORCE_SSL"),
               System.get_env("PORTFOLIXIR_FORCE_SSL_EXCLUDED_HOSTS")
             )

    assert RuntimeConfig.allowed_hosts() ==
             RuntimeConfig.allowed_hosts(
               System.get_env("PHX_HOST"),
               System.get_env("PORTFOLIXIR_ALLOWED_HOSTS")
             )
  end

  # User story:
  # As an operator who writes PHX_HOST the way a browser shows it,
  # I want a port or an IPv6 literal to match the Host the request carries,
  # so that "example.com:8443" or "::1" does not refuse every request.
  test "normalises a port and an IPv6 literal in the Host list" do
    assert RuntimeConfig.allowed_hosts("Example.com:8443", nil) ==
             ["example.com", "localhost", "127.0.0.1"]

    assert RuntimeConfig.allowed_hosts("::1", "[fd00::1]:4000, [2001:db8::1]") ==
             ["[::1]", "localhost", "127.0.0.1", "[fd00::1]", "[2001:db8::1]"]
  end

  # User story:
  # As an operator naming the proxy in front of the instance,
  # I want addresses and CIDR blocks accepted and anything else dropped,
  # so that a typo cannot widen the set of proxies whose header is believed.
  test "parses trusted proxies as addresses and blocks" do
    blocks =
      RuntimeConfig.trusted_proxies(
        "127.0.0.1, 172.16.0.0/12,::1, 2001:db8::/32, nope, 10.0.0.0/33"
      )

    assert blocks == [
             {{127, 0, 0, 1}, 32},
             {{172, 16, 0, 0}, 12},
             {{0, 0, 0, 0, 0, 0, 0, 1}, 128},
             {{0x2001, 0xDB8, 0, 0, 0, 0, 0, 0}, 32}
           ]

    assert RuntimeConfig.trusted_proxies(nil) == []
    assert RuntimeConfig.trusted_proxy?({172, 31, 255, 254}, blocks)
    refute RuntimeConfig.trusted_proxy?({172, 32, 0, 1}, blocks)
    assert RuntimeConfig.trusted_proxy?({0x2001, 0xDB8, 1, 2, 3, 4, 5, 6}, blocks)
    refute RuntimeConfig.trusted_proxy?({0x2001, 0xDB9, 0, 0, 0, 0, 0, 1}, blocks)
    refute RuntimeConfig.trusted_proxy?({127, 0, 0, 1}, [])

    assert RuntimeConfig.trusted_proxies() ==
             RuntimeConfig.trusted_proxies(System.get_env("PORTFOLIXIR_TRUSTED_PROXIES"))
  end

  # User story (#777):
  # As an operator who does not want to type the password every day,
  # I want the session lifetime to be a setting with a sensible default,
  # so that a home instance asks about once a month and a stricter setup can say otherwise.
  #
  # Acceptance criteria:
  # - Unset, blank or nonsense means the 30-day default.
  # - A positive number of days becomes that many seconds.
  # - Zero means no lifetime at all: the browser-session cookie of before.
  test "parses the session lifetime in days, defaulting to 30" do
    day = 24 * 60 * 60

    assert RuntimeConfig.session_max_age(nil) == 30 * day
    assert RuntimeConfig.session_max_age("") == 30 * day
    assert RuntimeConfig.session_max_age("  ") == 30 * day
    assert RuntimeConfig.session_max_age("nope") == 30 * day
    assert RuntimeConfig.session_max_age("-7") == 30 * day
    assert RuntimeConfig.session_max_age("7") == 7 * day
    assert RuntimeConfig.session_max_age(" 90 ") == 90 * day
    assert RuntimeConfig.session_max_age(1) == day
    assert RuntimeConfig.session_max_age("0") == nil
    assert RuntimeConfig.session_max_age(0) == nil
  end

  # User story (E25 S1, F67):
  # As an operator starting a production instance,
  # I want a short, placeholder or publicly committed SECRET_KEY_BASE refused at
  # boot with the variable named,
  # so that no instance signs its sessions with a value anyone can read.
  #
  # Acceptance criteria:
  # - A value shorter than 64 bytes (what the cookie store needs) raises, naming SECRET_KEY_BASE.
  # - A missing value raises the same way.
  # - The .env.example placeholder and the other placeholder prefixes are
  #   refused whatever their length.
  # - The literals committed in config/dev.exs and config/test.exs are refused.
  # - A 64-byte random value is returned unchanged, and config/runtime.exs
  #   reads the variable through this check.
  test "refuses short, placeholder and committed secret key bases" do
    sound = Base.encode64(:crypto.strong_rand_bytes(48))
    assert byte_size(sound) == 64
    assert RuntimeConfig.validate_secret_key_base!(sound) == sound

    assert_raise ArgumentError, ~r/SECRET_KEY_BASE/, fn ->
      RuntimeConfig.validate_secret_key_base!(binary_part(sound, 0, 63))
    end

    assert_raise ArgumentError, ~r/SECRET_KEY_BASE/, fn ->
      RuntimeConfig.validate_secret_key_base!(nil)
    end

    for placeholder <- ["replace-with-openssl-rand-base64-48", "changeme", "secret", "example"] do
      assert_raise ArgumentError, ~r/SECRET_KEY_BASE.*placeholder/, fn ->
        RuntimeConfig.validate_secret_key_base!(String.pad_trailing(placeholder, 64, "x"))
      end
    end

    for config <- ["config/dev.exs", "config/test.exs"] do
      [_, committed] = Regex.run(~r/secret_key_base:\s*"([^"]+)"/, File.read!(config))

      assert_raise ArgumentError, ~r/SECRET_KEY_BASE/, fn ->
        RuntimeConfig.validate_secret_key_base!(committed)
      end
    end

    assert File.read!("config/runtime.exs") =~
             ~s{RuntimeConfig.validate_secret_key_base!(System.get_env("SECRET_KEY_BASE"))}
  end

  # User story (E25 S1, F67; T-2 of the 2026-09-24 triage):
  # As an operator who opened the instance beyond loopback with a UI password,
  # I want a startup warning when that password is short,
  # so that a weak password is named in the log without an upgrade refusing to boot.
  #
  # Acceptance criteria:
  # - Bound beyond loopback with a password shorter than the floor: a warning
  #   naming PORTFOLIXIR_UI_PASSWORD and ADR-0045; never an exception.
  # - A password at the floor, or any password on loopback: no warning.
  # - No password at all is the exposure warning's case, not this one.
  test "warns about a short UI password beyond loopback" do
    floor = RuntimeConfig.min_ui_password_length()
    short = String.duplicate("p", floor - 1)

    assert {:warn, message} = RuntimeConfig.password_warning({0, 0, 0, 0}, short)
    assert message =~ "PORTFOLIXIR_UI_PASSWORD"
    assert message =~ "ADR-0045"
    refute message =~ short

    assert RuntimeConfig.password_warning({0, 0, 0, 0}, String.duplicate("p", floor)) == :ok
    assert RuntimeConfig.password_warning({127, 0, 0, 1}, short) == :ok
    assert RuntimeConfig.password_warning({0, 0, 0, 0, 0, 0, 0, 1}, short) == :ok
    assert RuntimeConfig.password_warning({0, 0, 0, 0}, nil) == :ok
    assert RuntimeConfig.password_warning({0, 0, 0, 0}, "") == :ok
  end

  # User story (E25 S2, F59):
  # As an operator running the release image,
  # I want the directory stored logos live in to be configuration,
  # so that the logos sit on a volume of their own, outside the release tree
  # the running user cannot write, survive a rebuild and are backed up.
  #
  # Acceptance criteria:
  # - PORTFOLIXIR_LOGO_DIR unset or blank leaves the default (nil here).
  # - A value is taken trimmed; a relative path is refused, naming the variable,
  #   because a release resolves it against its own read-only tree.
  # - config/runtime.exs reads the variable through this function.
  test "reads the logo directory from PORTFOLIXIR_LOGO_DIR" do
    assert RuntimeConfig.logo_dir(nil) == nil
    assert RuntimeConfig.logo_dir("") == nil
    assert RuntimeConfig.logo_dir("  ") == nil
    assert RuntimeConfig.logo_dir(" /var/lib/portfolixir/logos ") == "/var/lib/portfolixir/logos"

    assert_raise ArgumentError, ~r/PORTFOLIXIR_LOGO_DIR.*absolute/, fn ->
      RuntimeConfig.logo_dir("logos")
    end

    assert File.read!("config/runtime.exs") =~ "Portfolixir.RuntimeConfig.logo_dir()"
  end
end
