defmodule Portfolixir.Net.UrlPolicy do
  @moduledoc """
  The deny-by-default check every server-side fetch of a caller-supplied or
  provider-supplied URL passes before a socket opens (#762, ADR-0045 context).

  A URL is allowed only when all of these hold:

    * the scheme is `https`, and there is no userinfo;
    * the host is present and, when an allow-list is given, on it — an exact
      entry matches that host, a `.domain` entry matches its subdomains;
    * the host, literal or resolved, maps only to public addresses: loopback,
      private, link-local, carrier-grade NAT, multicast, reserved, the IPv6
      local ranges and IPv4-mapped private addresses are all refused, and one
      bad address among several refuses the host.

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

  Options: `:allowed_hosts` (`:any` or a list; default `:any`), `:resolver`.
  """
  @spec check(String.t() | nil, keyword()) :: :ok | {:error, {:url_not_allowed, reason()}}
  def check(url, opts \\ [])

  def check(url, opts) when is_binary(url) do
    uri = URI.parse(url)

    with :ok <- check_scheme(uri),
         :ok <- check_userinfo(uri),
         {:ok, host} <- check_host(uri),
         :ok <- check_allowed(host, Keyword.get(opts, :allowed_hosts, :any)),
         {:ok, addresses} <- addresses_for(host, resolver(opts)),
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
  # IETF protocol assignments and the benchmarking range are not on the internet.
  def public_address?({192, 0, 0, _}), do: false
  def public_address?({198, b, _, _}) when b in [18, 19], do: false
  def public_address?({a, _, _, _}) when a >= 224, do: false
  def public_address?({_, _, _, _}), do: true

  # IPv4-mapped (::ffff:a.b.c.d): judge the embedded IPv4 address.
  def public_address?({0, 0, 0, 0, 0, 0xFFFF, hi, lo}),
    do: public_address?({div(hi, 256), rem(hi, 256), div(lo, 256), rem(lo, 256)})

  def public_address?({0, 0, 0, 0, 0, 0, 0, 0}), do: false
  def public_address?({0, 0, 0, 0, 0, 0, 0, 1}), do: false
  # The other IPv4-embedding forms are judged by the embedded address too:
  # IPv4-compatible (::a.b.c.d), NAT64 (64:ff9b::/96) and 6to4 (2002::/16).
  def public_address?({0, 0, 0, 0, 0, 0, hi, lo}), do: public_address?(embedded_ipv4(hi, lo))

  def public_address?({0x64, 0xFF9B, 0, 0, 0, 0, hi, lo}),
    do: public_address?(embedded_ipv4(hi, lo))

  def public_address?({0x2002, hi, lo, _, _, _, _, _}), do: public_address?(embedded_ipv4(hi, lo))
  # fc00::/7 unique local, fe80::/10 link-local, fec0::/10 site-local, ff00::/8 multicast.
  def public_address?({a, _, _, _, _, _, _, _}) when Bitwise.band(a, 0xFE00) == 0xFC00, do: false
  def public_address?({a, _, _, _, _, _, _, _}) when Bitwise.band(a, 0xFFC0) == 0xFE80, do: false
  def public_address?({a, _, _, _, _, _, _, _}) when Bitwise.band(a, 0xFFC0) == 0xFEC0, do: false
  def public_address?({a, _, _, _, _, _, _, _}) when Bitwise.band(a, 0xFF00) == 0xFF00, do: false
  def public_address?({_, _, _, _, _, _, _, _}), do: true

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

  defp addresses_for(host, resolver) do
    case :inet.parse_strict_address(String.to_charlist(host)) do
      {:ok, address} ->
        {:ok, [address]}

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
