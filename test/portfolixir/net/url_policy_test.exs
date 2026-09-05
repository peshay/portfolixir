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
end
