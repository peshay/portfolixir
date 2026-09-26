defmodule Portfolixir.Net.UrlPolicy do
  @moduledoc """
  The deny-by-default check every server-side fetch of a caller-supplied or
  provider-supplied URL passes before a socket opens (#762, ADR-0045 context).

  A URL is allowed only when all of these hold:

    * the scheme is `https`, and there is no userinfo;
    * the host is present and, when an allow-list is given, on it — an exact
      entry matches that host, a `.domain` entry matches its subdomains;
    * the host, literal or resolved, maps only to public addresses, and one
      bad address among several refuses the host. Every block of the IANA
      special-purpose registries is refused in both families (loopback,
      private, link-local, carrier-grade NAT, documentation, benchmarking,
      multicast, reserved and the rest). IPv6 is deny-by-default (E25 S3, F32):
      an address is public only inside global unicast (`2000::/3`) and outside
      its special-purpose blocks, and the embedded-IPv4 forms (IPv4-mapped,
      the well-known NAT64 prefix, 6to4) are judged by the IPv4 they carry.

  The resolver is injectable (`:resolver` option or application config as an
  MFA) so the test suite never touches DNS. The default resolves both address
  families through `:inet`.

  Known limit: the check resolves the name and the client resolves it again
  when it connects, so a name whose answer changes between the two (DNS
  rebinding with a very short TTL) can pass. The redirect re-check, the byte
  cap and the deadline bound what such a fetch can do; pinning the connection
  to the checked address is the fix, and it needs the client's connect step.
  """

  @type reason ::
          :scheme | :userinfo | :host | :host_not_allowed | :unresolvable | :private_address

  @type resolver :: (String.t() -> {:ok, [:inet.ip_address()]} | {:error, term()})

  @doc """
  `:ok`, or `{:error, {:url_not_allowed, reason}}`.

  Options: `:allowed_hosts` (`:any` or a list; default `:any`), `:resolver`,
  and `:resolve` (default `true`). With `resolve: false` a host name is not
  resolved, so only the scheme, the userinfo, the allow-list and a literal
  address are judged: the check `Portfolixir.Net.Http` runs on a client's own
  compiled-in endpoint, where the full check runs on every redirect hop.
  """
  @spec check(String.t() | nil, keyword()) :: :ok | {:error, {:url_not_allowed, reason()}}
  def check(url, opts \\ [])

  def check(url, opts) when is_binary(url) do
    uri = URI.parse(url)

    with :ok <- check_scheme(uri),
         :ok <- check_userinfo(uri),
         {:ok, host} <- check_host(uri),
         :ok <- check_allowed(host, Keyword.get(opts, :allowed_hosts, :any)),
         {:ok, addresses} <-
           addresses_for(host, resolver(opts), Keyword.get(opts, :resolve, true)),
         :ok <- check_public(addresses) do
      :ok
    else
      {:error, reason} when is_atom(reason) -> {:error, {:url_not_allowed, reason}}
    end
  end

  def check(_url, _opts), do: {:error, {:url_not_allowed, :scheme}}

  @doc "Whether `host` is allowed by an allow-list (`:any`, or exact and `.domain` entries)."
  @spec host_allowed?(String.t(), :any | [String.t()]) :: boolean()
  def host_allowed?(_host, :any), do: true

  def host_allowed?(host, entries) when is_list(entries) do
    host = String.downcase(host)

    Enum.any?(entries, fn
      "." <> domain -> String.ends_with?(host, "." <> String.downcase(domain))
      exact -> host == String.downcase(exact)
    end)
  end

  @doc "Whether an address is outside every reserved, private or local range."
  @spec public_address?(:inet.ip_address()) :: boolean()
  def public_address?({a, _, _, _}) when a in [0, 10, 127], do: false
  def public_address?({100, b, _, _}) when b >= 64 and b <= 127, do: false
  def public_address?({169, 254, _, _}), do: false
  def public_address?({172, b, _, _}) when b >= 16 and b <= 31, do: false
  def public_address?({192, 168, _, _}), do: false
  # IETF protocol assignments, the documentation ranges, the benchmarking
  # range, the AS112 and AMT anycast blocks and the retired 6to4 relay anycast
  # are special-purpose, not the internet (F32).
  def public_address?({192, 0, c, _}) when c in [0, 2], do: false
  def public_address?({192, 31, 196, _}), do: false
  def public_address?({192, 52, 193, _}), do: false
  def public_address?({192, 88, 99, _}), do: false
  def public_address?({192, 175, 48, _}), do: false
  def public_address?({198, b, _, _}) when b in [18, 19], do: false
  def public_address?({198, 51, 100, _}), do: false
  def public_address?({203, 0, 113, _}), do: false
  # Multicast, reserved and the limited broadcast.
  def public_address?({a, _, _, _}) when a >= 224, do: false
  def public_address?({_, _, _, _}), do: true

  # IPv6 is deny-by-default (F32). The embedded-IPv4 forms are judged by the
  # IPv4 they carry: IPv4-mapped (::ffff:0:0/96), the well-known NAT64 prefix
  # (64:ff9b::/96) and 6to4 (2002::/16).
  def public_address?({0, 0, 0, 0, 0, 0xFFFF, hi, lo}), do: public_address?(embedded_ipv4(hi, lo))

  def public_address?({0x64, 0xFF9B, 0, 0, 0, 0, hi, lo}),
    do: public_address?(embedded_ipv4(hi, lo))

  def public_address?({0x2002, hi, lo, _, _, _, _, _}), do: public_address?(embedded_ipv4(hi, lo))

  # Inside global unicast (2000::/3), the special-purpose blocks: IETF protocol
  # assignments with Teredo, benchmarking, ORCHID and AMT (2001::/23), the
  # documentation prefixes (2001:db8::/32, 3fff::/20) and the direct-delegation
  # AS112 service (2620:4f:8000::/48).
  def public_address?({0x2001, b, _, _, _, _, _, _}) when b <= 0x01FF, do: false
  def public_address?({0x2001, 0x0DB8, _, _, _, _, _, _}), do: false
  def public_address?({0x2620, 0x004F, 0x8000, _, _, _, _, _}), do: false
  def public_address?({0x3FFF, b, _, _, _, _, _, _}) when b <= 0x0FFF, do: false

  # Everything else is public only inside 2000::/3: loopback, unspecified,
  # IPv4-compatible, the discard and dummy prefixes, the local-use NAT64
  # prefix, segment-routing SIDs, unique-local, link-local, site-local and
  # multicast all sit outside it.
  def public_address?({a, _, _, _, _, _, _, _}) when Bitwise.band(a, 0xE000) == 0x2000, do: true
  def public_address?({_, _, _, _, _, _, _, _}), do: false

  defp embedded_ipv4(hi, lo), do: {div(hi, 256), rem(hi, 256), div(lo, 256), rem(lo, 256)}

  @doc "The default resolver: both address families through `:inet`."
  @spec resolve_host(String.t()) :: {:ok, [:inet.ip_address()]} | {:error, term()}
  def resolve_host(host) when is_binary(host) do
    charlist = String.to_charlist(host)

    addresses =
      [:inet, :inet6]
      |> Enum.flat_map(fn family ->
        case :inet.getaddrs(charlist, family) do
          {:ok, list} -> list
          {:error, _} -> []
        end
      end)

    case addresses do
      [] -> {:error, :unresolvable}
      list -> {:ok, list}
    end
  end

  defp check_scheme(%URI{scheme: "https"}), do: :ok
  defp check_scheme(_uri), do: {:error, :scheme}

  defp check_userinfo(%URI{userinfo: nil}), do: :ok
  defp check_userinfo(_uri), do: {:error, :userinfo}

  defp check_host(%URI{host: host}) when is_binary(host) and host != "", do: {:ok, host}
  defp check_host(_uri), do: {:error, :host}

  defp check_allowed(host, allowed) do
    if host_allowed?(host, allowed), do: :ok, else: {:error, :host_not_allowed}
  end

  defp addresses_for(host, resolver, resolve?) do
    case :inet.parse_strict_address(String.to_charlist(host)) do
      {:ok, address} ->
        {:ok, [address]}

      {:error, _not_literal} when not resolve? ->
        {:ok, []}

      {:error, _not_literal} ->
        case resolver.(host) do
          {:ok, [_ | _] = addresses} -> {:ok, addresses}
          _ -> {:error, :unresolvable}
        end
    end
  end

  defp check_public(addresses) do
    if Enum.all?(addresses, &public_address?/1), do: :ok, else: {:error, :private_address}
  end

  defp resolver(opts) do
    case Keyword.get(opts, :resolver) ||
           Application.get_env(:portfolixir, __MODULE__, [])[:resolver] do
      fun when is_function(fun, 1) -> fun
      {module, function, args} -> fn host -> apply(module, function, [host | args]) end
      nil -> &resolve_host/1
    end
  end
end
