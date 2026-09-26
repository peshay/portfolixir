defmodule Portfolixir.RuntimeConfig do
  @moduledoc """
  Small deterministic helpers for runtime configuration parsing.

  Everything here is a pure function over the raw environment strings so the
  release-time decisions in `config/runtime.exs` can be pinned by unit tests
  instead of by a deployment (ADR-0045 §2, #758).
  """

  @true_values ["1", "true", "yes"]
  @loopback {127, 0, 0, 1}
  @any {0, 0, 0, 0}
  @always_allowed_hosts ["localhost", "127.0.0.1"]

  def database_ssl?(value \\ System.get_env("DATABASE_SSL", "false"))

  def database_ssl?(value) when is_binary(value), do: truthy?(value)
  def database_ssl?(_value), do: false

  @doc """
  The address the HTTP listener binds. Loopback unless `PHX_BIND_ALL` is one of
  the accepted true values — the same switch and default `config/dev.exs` has
  had all along; production gets it here.
  """
  @spec bind_ip(String.t() | nil) :: :inet.ip4_address()
  def bind_ip(value \\ System.get_env("PHX_BIND_ALL"))
  def bind_ip(value) when is_binary(value), do: if(truthy?(value), do: @any, else: @loopback)
  def bind_ip(_value), do: @loopback

  @doc """
  The Host names a request may carry (`PortfolixirWeb.HostGuard`): `PHX_HOST`,
  the two loopback names, and whatever `PORTFOLIXIR_ALLOWED_HOSTS` adds
  (comma-separated; a reverse-proxy name, a LAN address). Lower-cased, trimmed,
  blanks dropped, duplicates removed, order kept.
  """
  @spec allowed_hosts(String.t() | nil, String.t() | nil) :: [String.t()]
  def allowed_hosts(
        phx_host \\ System.get_env("PHX_HOST"),
        extra \\ System.get_env("PORTFOLIXIR_ALLOWED_HOSTS")
      )

  def allowed_hosts(phx_host, extra) do
    ([phx_host | @always_allowed_hosts] ++ split_hosts(extra))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&normalize_host/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  @doc """
  The startup check behind ADR-0045 §2: bound beyond loopback with no UI
  password is a state the operator must have chosen knowingly, so it is named
  in the log rather than left silent. Pure; `Portfolixir.Application` logs it.
  """
  @spec exposure_warning(:inet.ip_address(), String.t() | nil) :: :ok | {:warn, String.t()}
  def exposure_warning(@loopback, _password), do: :ok
  def exposure_warning({0, 0, 0, 0, 0, 0, 0, 1}, _password), do: :ok

  def exposure_warning(_ip, password) when is_binary(password) and password != "", do: :ok

  def exposure_warning(_ip, _password) do
    {:warn,
     "The web UI is bound beyond loopback and PORTFOLIXIR_UI_PASSWORD is not set: " <>
       "every page and every write is reachable by anyone who can reach this port. " <>
       "Set PORTFOLIXIR_UI_PASSWORD, or put reverse-proxy authentication in front " <>
       "(ADR-0045)."}
  end

  @min_ui_password_length 12

  @doc "The UI password length below which a network-bound instance warns at boot (T-2)."
  @spec min_ui_password_length() :: pos_integer()
  def min_ui_password_length, do: @min_ui_password_length

  @doc """
  The startup check behind T-2 of the 2026-09-24 triage (E25 S1, F67): bound
  beyond loopback with a UI password shorter than `min_ui_password_length/0`
  is named in the log. A warning, never a refusal: an instance that already
  runs keeps booting (ADR-0045 §1). No password at all is
  `exposure_warning/2`'s case. Pure; `Portfolixir.Application` logs it.
  """
  @spec password_warning(:inet.ip_address(), String.t() | nil) :: :ok | {:warn, String.t()}
  def password_warning(@loopback, _password), do: :ok
  def password_warning({0, 0, 0, 0, 0, 0, 0, 1}, _password), do: :ok

  def password_warning(_ip, password) when is_binary(password) and password != "" do
    if String.length(password) < @min_ui_password_length do
      {:warn,
       "The web UI is bound beyond loopback and PORTFOLIXIR_UI_PASSWORD is shorter " <>
         "than #{@min_ui_password_length} characters: the login throttle slows guessing, " <>
         "it does not stop it. Choose a longer password (ADR-0045)."}
    else
      :ok
    end
  end

  def password_warning(_ip, _password), do: :ok

  @doc """
  A signing salt derived from `SECRET_KEY_BASE` for one named purpose (#759):
  no installation shares a salt printed in the repository, and the two salts
  (session, LiveView) never coincide. URL-safe base64 of an HMAC, 43 bytes.
  """
  @spec derived_salt(String.t(), String.t()) :: String.t()
  def derived_salt(secret_key_base, purpose)
      when is_binary(secret_key_base) and is_binary(purpose) do
    :hmac
    |> :crypto.mac(:sha256, secret_key_base, "portfolixir." <> purpose <> ".signing_salt")
    |> Base.url_encode64(padding: false)
  end

  @doc """
  The `Plug.SSL` options behind `PHX_FORCE_SSL` (#759): off unless asked for;
  on, plain HTTP is redirected and HSTS is set, with the scheme read from the
  proxy's `x-forwarded-proto`, which `PortfolixirWeb.TrustedProxy` keeps only
  from loopback or a trusted proxy (E25 S1, F09).

  `localhost` is always left on plain HTTP (the container's own health
  check), and so is every host `PORTFOLIXIR_FORCE_SSL_EXCLUDED_HOSTS` names,
  comma-separated (E25 S7, F23): the internal name the MCP companion calls
  the app under on the Compose network, where there is no TLS to redirect
  to. Names are normalised like `allowed_hosts/2` (trimmed, lower-cased, a
  port dropped); an excluded host gets neither the redirect nor HSTS.
  """
  @spec force_ssl_opts(String.t() | nil, String.t() | nil) :: false | keyword()
  def force_ssl_opts(
        value \\ System.get_env("PHX_FORCE_SSL"),
        excluded \\ System.get_env("PORTFOLIXIR_FORCE_SSL_EXCLUDED_HOSTS")
      )

  def force_ssl_opts(value, excluded) when is_binary(value) do
    if truthy?(value) do
      hosts =
        (["localhost"] ++ split_hosts(excluded))
        |> Enum.map(&normalize_host/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.uniq()

      [rewrite_on: [:x_forwarded_proto], hsts: true, exclude: hosts]
    else
      false
    end
  end

  def force_ssl_opts(_value, _excluded), do: false

  @min_token_bytes 32
  @placeholder_prefixes ~w(dev-api-token dev-mcp-token test-api-token replace change secret token password example)

  @doc "The bearer tokens' length floor; the MCP companion holds its token to it too (F01)."
  @spec min_token_bytes() :: pos_integer()
  def min_token_bytes, do: @min_token_bytes

  @doc "The placeholder prefixes a bearer token may not start with; mirrored by the companion."
  @spec token_placeholder_prefixes() :: [String.t()]
  def token_placeholder_prefixes, do: @placeholder_prefixes

  @doc """
  The bearer token a production instance boots with (#761): at least 32 bytes
  and not one of the placeholders the example files ship. Raises with the
  variable's name so the fix is obvious from the log.
  """
  @spec validate_api_token!(String.t() | nil) :: String.t()
  def validate_api_token!(token) when is_binary(token) do
    cond do
      byte_size(token) < @min_token_bytes ->
        raise ArgumentError,
              "PORTFOLIXIR_API_TOKEN must be at least #{@min_token_bytes} bytes " <>
                "(got #{byte_size(token)}); generate one with `openssl rand -base64 48`"

      placeholder?(token) ->
        raise ArgumentError,
              "PORTFOLIXIR_API_TOKEN is a placeholder value; generate a real token " <>
                "with `openssl rand -base64 48`"

      true ->
        token
    end
  end

  def validate_api_token!(_missing) do
    raise ArgumentError,
          "PORTFOLIXIR_API_TOKEN is required; generate one with `openssl rand -base64 48`"
  end

  defp placeholder?(token, prefixes \\ @placeholder_prefixes) do
    lowered = String.downcase(token)
    Enum.any?(prefixes, &String.starts_with?(lowered, &1))
  end

  # What the cookie store needs, and what `openssl rand -base64 48` prints.
  @min_secret_key_base_bytes 64
  # The placeholders, plus the prefixes of the literals committed in
  # config/dev.exs and config/test.exs, which anyone can read.
  @secret_key_base_placeholders @placeholder_prefixes ++
                                  ~w(dev_secret_key_base test_secret_key_base)

  @doc """
  The `SECRET_KEY_BASE` a production instance boots with (E25 S1, F67): at
  least #{@min_secret_key_base_bytes} bytes, not a placeholder the example
  files ship, and not a literal committed in this repository. Raises with the
  variable's name, mirroring `validate_api_token!/1`.
  """
  @spec validate_secret_key_base!(String.t() | nil) :: String.t()
  def validate_secret_key_base!(secret) when is_binary(secret) do
    cond do
      byte_size(secret) < @min_secret_key_base_bytes ->
        raise ArgumentError,
              "SECRET_KEY_BASE must be at least #{@min_secret_key_base_bytes} bytes " <>
                "(got #{byte_size(secret)}); generate one with `openssl rand -base64 48`"

      placeholder?(secret, @secret_key_base_placeholders) ->
        raise ArgumentError,
              "SECRET_KEY_BASE is a placeholder or a value committed in the repository; " <>
                "generate a real one with `openssl rand -base64 48`"

      true ->
        secret
    end
  end

  def validate_secret_key_base!(_missing) do
    raise ArgumentError,
          "SECRET_KEY_BASE is required; generate one with `openssl rand -base64 48`"
  end

  defp truthy?(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> then(&(&1 in @true_values))
  end

  defp split_hosts(nil), do: []
  defp split_hosts(extra) when is_binary(extra), do: String.split(extra, ",")

  # A Host header carries no port by the time Plug hands it over, and an IPv6
  # literal carries its brackets; the operator writes `example.com:8443` or
  # `::1` and both must match. Port stripped, a bare IPv6 literal bracketed.
  defp normalize_host(host) do
    host = host |> String.trim() |> String.downcase()

    cond do
      host == "" ->
        ""

      String.starts_with?(host, "[") ->
        host |> String.split("]:") |> hd() |> ensure_bracket()

      match?({:ok, {_, _, _, _, _, _, _, _}}, :inet.parse_strict_address(to_charlist(host))) ->
        "[" <> host <> "]"

      true ->
        host |> String.split(":") |> hd()
    end
  end

  defp ensure_bracket(host), do: if(String.ends_with?(host, "]"), do: host, else: host <> "]")

  @doc """
  The directory stored logos are written to and served from, from
  `PORTFOLIXIR_LOGO_DIR` (E25 S2, F59). Unset or blank leaves the default, the
  release's own `priv/static/security_logos` (`nil` here); the release image
  names a directory of its own, on a volume outside the read-only release
  tree. A relative path is refused, naming the variable: a release would
  resolve it against that read-only tree.
  """
  @spec logo_dir(String.t() | nil) :: Path.t() | nil
  def logo_dir(value \\ System.get_env("PORTFOLIXIR_LOGO_DIR"))

  def logo_dir(value) when is_binary(value) do
    case String.trim(value) do
      "" ->
        nil

      dir ->
        if Path.type(dir) == :absolute do
          dir
        else
          raise ArgumentError,
                "PORTFOLIXIR_LOGO_DIR must be an absolute path, got a relative one"
        end
    end
  end

  def logo_dir(_value), do: nil

  @default_session_days 30

  @doc """
  How long a UI login stays valid, in seconds, from `PORTFOLIXIR_SESSION_DAYS`
  (#777, ADR-0045 §1). A positive number of days becomes seconds; `0` means no
  lifetime at all, the browser-session cookie of before; anything absent or
  unreadable falls back to #{@default_session_days} days rather than to a
  surprise.
  """
  @spec session_max_age(String.t() | integer() | nil) :: pos_integer() | nil
  def session_max_age(0), do: nil
  def session_max_age(days) when is_integer(days) and days > 0, do: days * 86_400

  def session_max_age(value) when is_binary(value) do
    case value |> String.trim() |> Integer.parse() do
      {0, ""} -> nil
      {days, ""} when days > 0 -> days * 86_400
      _ -> @default_session_days * 86_400
    end
  end

  def session_max_age(_value), do: @default_session_days * 86_400

  @doc """
  The proxies whose forwarding headers the application believes (#771, E25 S1
  F09): their `x-forwarded-for` names the throttle's source, and their
  `x-forwarded-proto` the scheme, which loopback may also set.
  `PORTFOLIXIR_TRUSTED_PROXIES`, comma-separated addresses or CIDR blocks
  (`127.0.0.1`, `172.18.0.1`, `::1`, a block such as `192.0.2.0/29`). Empty
  by default: a header nobody vouches for is never a source. Entries that do
  not parse are dropped.
  """
  @spec trusted_proxies(String.t() | nil) :: [{:inet.ip_address(), non_neg_integer()}]
  def trusted_proxies(value \\ System.get_env("PORTFOLIXIR_TRUSTED_PROXIES"))

  def trusted_proxies(value) when is_binary(value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.flat_map(&parse_cidr/1)
  end

  def trusted_proxies(_value), do: []

  @doc "Whether `ip` lies inside one of the trusted blocks."
  @spec trusted_proxy?(:inet.ip_address(), [{:inet.ip_address(), non_neg_integer()}]) :: boolean()
  def trusted_proxy?(ip, blocks) when is_tuple(ip) and is_list(blocks) do
    Enum.any?(blocks, fn {network, prefix} -> in_block?(ip, network, prefix) end)
  end

  defp parse_cidr(entry) do
    {address, prefix} =
      case String.split(entry, "/", parts: 2) do
        [address, prefix] -> {address, Integer.parse(prefix)}
        [address] -> {address, :whole}
      end

    with {:ok, ip} <- :inet.parse_strict_address(to_charlist(address)),
         {:ok, bits} <- prefix_for(ip, prefix) do
      [{ip, bits}]
    else
      _ -> []
    end
  end

  defp prefix_for({_, _, _, _}, :whole), do: {:ok, 32}
  defp prefix_for({_, _, _, _, _, _, _, _}, :whole), do: {:ok, 128}
  defp prefix_for({_, _, _, _}, {bits, ""}) when bits in 0..32, do: {:ok, bits}
  defp prefix_for({_, _, _, _, _, _, _, _}, {bits, ""}) when bits in 0..128, do: {:ok, bits}
  defp prefix_for(_ip, _prefix), do: :error

  defp in_block?(ip, network, prefix) when tuple_size(ip) == tuple_size(network) do
    width = if tuple_size(ip) == 4, do: 8, else: 16
    total = width * tuple_size(ip)
    shift = total - prefix

    Bitwise.bsr(to_integer(ip, width), shift) == Bitwise.bsr(to_integer(network, width), shift)
  end

  defp in_block?(_ip, _network, _prefix), do: false

  defp to_integer(address, width) do
    address
    |> Tuple.to_list()
    |> Enum.reduce(0, fn part, acc -> Bitwise.bsl(acc, width) + part end)
  end
end
