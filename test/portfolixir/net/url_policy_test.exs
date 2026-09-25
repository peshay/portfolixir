defmodule Portfolixir.Net.UrlPolicyTest do
  # Issue #762: the deny-by-default check every server-side fetch of a
  # caller-supplied or upstream-supplied URL passes before a socket opens.
  # The table below is the invariant the closing act verifies.
  use ExUnit.Case, async: true

  alias Portfolixir.Net.FakeResolver
  alias Portfolixir.Net.UrlPolicy

  @opts [resolver: &FakeResolver.resolve/1]

  # User story:
  # As an operator whose instance can be asked (by me, by my agent, or by a
  # third-party payload) to fetch a URL,
  # I want every such URL refused unless it is https to a public address,
  # so that the server can never be pointed at my router, my NAS or a cloud metadata endpoint.
  #
  # Acceptance criteria:
  # - Only https; no userinfo; a host is required.
  # - Literal or resolved addresses in loopback, private, link-local,
  #   carrier-grade NAT, multicast, reserved, IPv6 local or IPv4-mapped-private
  #   ranges are refused; one bad address among several refuses the host.
  # - An unresolvable host is refused.
  # - A public https URL passes.
  test "accepts a public https URL" do
    assert UrlPolicy.check("https://images.example.com/logo.png", @opts) == :ok
    assert UrlPolicy.check("https://93.184.216.34/logo.png", @opts) == :ok
  end

  test "refuses anything but https" do
    for url <- [
          "http://images.example.com/logo.png",
          "ftp://images.example.com/logo.png",
          "file:///etc/passwd",
          "javascript:alert(1)",
          "//images.example.com/logo.png",
          "images.example.com/logo.png",
          ""
        ] do
      assert {:error, {:url_not_allowed, _}} = UrlPolicy.check(url, @opts), url
    end
  end

  test "refuses userinfo and a missing host" do
    assert {:error, {:url_not_allowed, :userinfo}} =
             UrlPolicy.check("https://user:pass@images.example.com/x.png", @opts)

    assert {:error, {:url_not_allowed, :host}} = UrlPolicy.check("https:///x.png", @opts)
  end

  test "refuses literal addresses in non-public ranges" do
    for host <- [
          "127.0.0.1",
          "127.1.2.3",
          "10.0.0.5",
          "172.16.0.1",
          "172.31.255.254",
          "192.168.1.20",
          "169.254.169.254",
          "100.64.0.1",
          "0.0.0.0",
          "224.0.0.1",
          "240.0.0.1",
          "255.255.255.255",
          "[::1]",
          "[::]",
          "[fc00::1]",
          "[fd12::1]",
          "[fe80::1]",
          "[::ffff:10.0.0.1]",
          "[ff02::1]"
        ] do
      assert {:error, {:url_not_allowed, :private_address}} =
               UrlPolicy.check("https://#{host}/x.png", @opts),
             host
    end

    assert UrlPolicy.check("https://172.32.0.1/x.png", @opts) == :ok
    assert UrlPolicy.check("https://[2606:4700::1111]/x.png", @opts) == :ok
  end

  test "refuses hosts that resolve to non-public addresses, even partly" do
    for host <-
          ~w(internal.test lan.test loopback.test meta.test cgnat.test v6loopback.test v6local.test v6mapped.test mixed.test) do
      assert {:error, {:url_not_allowed, :private_address}} =
               UrlPolicy.check("https://#{host}/x.png", @opts),
             host
    end

    assert {:error, {:url_not_allowed, :unresolvable}} =
             UrlPolicy.check("https://unresolvable.test/x.png", @opts)
  end

  # User story:
  # As the discovery job that receives an image URL from a provider's payload,
  # I want the URL confined to that provider's own image host,
  # so that a poisoned payload cannot redirect the fetch elsewhere.
  #
  # Acceptance criteria:
  # - An exact host entry matches that host only; a ".domain" entry matches
  #   its subdomains; matching is case-insensitive; :any skips the host check
  #   but not the address check.
  test "confines a URL to an allowed host list" do
    hosts = ["upload.wikimedia.org", ".coingecko.com"]

    assert UrlPolicy.check("https://upload.wikimedia.org/x.png", @opts ++ [allowed_hosts: hosts]) ==
             :ok

    assert UrlPolicy.check("https://UPLOAD.wikimedia.org/x.png", @opts ++ [allowed_hosts: hosts]) ==
             :ok

    assert UrlPolicy.check(
             "https://coin-images.coingecko.com/x.png",
             @opts ++ [allowed_hosts: hosts]
           ) == :ok

    for url <- [
          "https://coingecko.com/x.png",
          "https://wikimedia.org/x.png",
          "https://upload.wikimedia.org.evil.test/x.png",
          "https://evil.test/x.png"
        ] do
      assert {:error, {:url_not_allowed, :host_not_allowed}} =
               UrlPolicy.check(url, @opts ++ [allowed_hosts: hosts]),
             url
    end

    assert UrlPolicy.check("https://anything.example/x.png", @opts ++ [allowed_hosts: :any]) ==
             :ok

    assert {:error, {:url_not_allowed, :private_address}} =
             UrlPolicy.check("https://internal.test/x.png", @opts ++ [allowed_hosts: :any])
  end

  test "refuses a non-string URL and the IPv6 site-local range" do
    assert {:error, {:url_not_allowed, :scheme}} = UrlPolicy.check(nil, @opts)

    assert {:error, {:url_not_allowed, :private_address}} =
             UrlPolicy.check("https://[fec0::1]/x.png", @opts)
  end

  test "judges the other IPv4-embedding IPv6 forms and the remaining reserved IPv4 blocks" do
    for host <- [
          "[::7f00:1]",
          "[64:ff9b::7f00:1]",
          "[2002:7f00:1::]",
          "[2002:c0a8:101::1]",
          "192.0.0.8",
          "198.18.0.1",
          "198.19.255.255"
        ] do
      assert {:error, {:url_not_allowed, :private_address}} =
               UrlPolicy.check("https://#{host}/x.png", @opts),
             host
    end

    assert UrlPolicy.check("https://[64:ff9b::5db8:d822]/x.png", @opts) == :ok
    assert UrlPolicy.check("https://198.17.0.1/x.png", @opts) == :ok
  end

  # E25 S3, F32 (#888): the IANA special-purpose address registries, one row
  # per block, each probed at its first address and at an address inside it.
  @ipv6_special_purpose [
    {"::1/128 loopback", ["::1"]},
    {"::/128 unspecified", ["::"]},
    {"::/96 IPv4-compatible (deprecated)", ["::5db8:d822", "::0808:0808"]},
    {"64:ff9b:1::/48 local-use IPv4/IPv6 translation", ["64:ff9b:1::", "64:ff9b:1::5db8:d822"]},
    {"100::/64 discard-only", ["100::", "100::1:2:3:4"]},
    {"100:0:0:1::/64 dummy prefix", ["100:0:0:1::", "100:0:0:1::5"]},
    {"2001::/23 IETF protocol assignments", ["2001::", "2001:1::1", "2001:1ff::1"]},
    {"2001::/32 Teredo", ["2001:0:5db8:d822::1"]},
    {"2001:2::/48 benchmarking", ["2001:2::1"]},
    {"2001:3::/32 AMT", ["2001:3::1"]},
    {"2001:4:112::/48 AS112-v6", ["2001:4:112::1"]},
    {"2001:20::/28 ORCHIDv2", ["2001:20::1", "2001:2f::1"]},
    {"2001:db8::/32 documentation", ["2001:db8::", "2001:db8:ffff::1"]},
    {"2620:4f:8000::/48 direct delegation AS112", ["2620:4f:8000::1"]},
    {"3fff::/20 documentation", ["3fff::", "3fff:fff::1"]},
    {"5f00::/16 segment routing SIDs", ["5f00::1"]},
    {"fc00::/7 unique local", ["fc00::1", "fdff::1"]},
    {"fe80::/10 link-local", ["fe80::1", "febf::1"]},
    {"fec0::/10 site-local (deprecated)", ["fec0::1"]},
    {"ff00::/8 multicast", ["ff02::1", "ff0e::1"]},
    {"outside 2000::/3", ["1234::1", "4000::1", "8000::1", "e000::1"]}
  ]

  @ipv4_special_purpose [
    {"0.0.0.0/8 this network", ["0.0.0.0", "0.1.2.3"]},
    {"10.0.0.0/8 private", ["10.0.0.0", "10.255.0.1"]},
    {"100.64.0.0/10 shared address space", ["100.64.0.0", "100.127.255.254"]},
    {"127.0.0.0/8 loopback", ["127.0.0.1", "127.255.0.1"]},
    {"169.254.0.0/16 link-local", ["169.254.0.1", "169.254.169.254"]},
    {"172.16.0.0/12 private", ["172.16.0.1", "172.31.255.254"]},
    {"192.0.0.0/24 IETF protocol assignments", ["192.0.0.0", "192.0.0.9", "192.0.0.170"]},
    {"192.0.2.0/24 documentation", ["192.0.2.0", "192.0.2.77"]},
    {"192.31.196.0/24 AS112-v4", ["192.31.196.1"]},
    {"192.52.193.0/24 AMT", ["192.52.193.1"]},
    {"192.88.99.0/24 deprecated 6to4 relay anycast", ["192.88.99.1"]},
    {"192.168.0.0/16 private", ["192.168.0.1", "192.168.255.254"]},
    {"192.175.48.0/24 direct delegation AS112", ["192.175.48.1"]},
    {"198.18.0.0/15 benchmarking", ["198.18.0.1", "198.19.255.254"]},
    {"198.51.100.0/24 documentation", ["198.51.100.1"]},
    {"203.0.113.0/24 documentation", ["203.0.113.1"]},
    {"224.0.0.0/4 multicast", ["224.0.0.1", "239.255.255.255"]},
    {"240.0.0.0/4 reserved", ["240.0.0.1", "255.255.255.254"]},
    {"255.255.255.255/32 limited broadcast", ["255.255.255.255"]}
  ]

  # User story:
  # As an operator whose instance fetches provider-supplied URLs,
  # I want the policy to treat an address as public only when it is ordinary
  # global unicast, in both address families,
  # so that no special-purpose range an upstream can name is mistaken for the
  # internet.
  #
  # Acceptance criteria:
  # - Every IANA special-purpose IPv6 block and everything outside 2000::/3 is
  #   refused; an IPv6 address counts as public only inside global unicast
  #   and outside those blocks.
  # - The embedded-IPv4 forms (IPv4-mapped, the well-known NAT64 prefix, 6to4)
  #   are judged by the IPv4 address they carry.
  # - Every IANA special-purpose IPv4 block is refused.
  # - Ordinary global unicast in both families still passes.
  test "every IANA special-purpose block is non-public; ordinary global unicast passes" do
    for {block, addresses} <- @ipv6_special_purpose ++ @ipv4_special_purpose,
        literal <- addresses do
      {:ok, address} = :inet.parse_strict_address(String.to_charlist(literal))
      refute UrlPolicy.public_address?(address), "#{block}: #{literal} is public"

      host = if String.contains?(literal, ":"), do: "[#{literal}]", else: literal

      assert {:error, {:url_not_allowed, :private_address}} =
               UrlPolicy.check("https://#{host}/x.png", @opts),
             "#{block}: #{literal}"
    end

    for literal <- [
          "2606:4700::1111",
          "2a00:1450:4001::200e",
          "2001:200::1",
          "2620:4f:8001::1",
          "3fff:1000::1",
          "::ffff:5db8:d822",
          "64:ff9b::5db8:d822",
          "2002:5db8:d822::1",
          "93.184.216.34",
          "192.0.1.1",
          "192.0.3.1",
          "198.51.101.1",
          "203.0.114.1"
        ] do
      {:ok, address} = :inet.parse_strict_address(String.to_charlist(literal))
      assert UrlPolicy.public_address?(address), literal
    end

    for literal <- ["::ffff:c0a8:0101", "64:ff9b::c000:0201", "2002:c633:6401::1"] do
      {:ok, address} = :inet.parse_strict_address(String.to_charlist(literal))
      refute UrlPolicy.public_address?(address), literal
    end
  end
end
