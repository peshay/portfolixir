defmodule Portfolixir.Chains.EsploraAttackOwnUrlTest do
  # Sprint 29, H2, the closing act's security lens (D-8 item 5): the
  # operator's own Esplora URL attacked. Not async: each test sets the
  # adapter's application environment, and some the URL policy's resolver.
  # Each case here was seen held: a refused URL makes no request at all.
  use ExUnit.Case, async: false

  import Portfolixir.EsploraFixtures

  alias Portfolixir.Chains.Esplora

  @now ~U[2026-11-12 12:00:00Z]
  @tip 870_000

  setup do
    saved = Application.get_env(:portfolixir, Esplora)
    saved_policy = Application.get_env(:portfolixir, Portfolixir.Net.UrlPolicy)

    on_exit(fn ->
      Application.put_env(:portfolixir, Esplora, saved)
      Application.put_env(:portfolixir, Portfolixir.Net.UrlPolicy, saved_policy)
    end)

    %{saved: saved, saved_policy: saved_policy}
  end

  defp configure(saved, changes),
    do: Application.put_env(:portfolixir, Esplora, Keyword.merge(saved, changes))

  defp read, do: Esplora.read(&[&1, &1 - 2016], now: @now)

  defp requested do
    receive do
      {:esplora, host, path} -> [{host, suffix(path)} | requested()]
    after
      0 -> []
    end
  end

  # A stub that answers every host as a valid chain, so a URL that slipped
  # through would show as a request.
  defp serve_everything do
    test_pid = self()

    Req.Test.stub(Esplora, fn conn ->
      send(test_pid, {:esplora, conn.host, conn.request_path})
      Plug.Conn.send_resp(conn, 200, Integer.to_string(@tip))
    end)
  end

  # User story:
  # As the operator whose own URL is checked as every outbound URL is,
  # I want every spelling of a loopback, private or unspecified address
  # refused, literal or resolved,
  # so that the chain source can never be pointed at the local network.
  #
  # Acceptance criteria:
  # - IPv4-mapped IPv6, the unspecified addresses, IPv4 shorthand, a decimal
  #   or hex address, link-local and the metadata address are refused with
  #   `url_not_allowed:<reason>`, and no request is made.
  # - A name the resolver maps to loopback (`localhost.`) or to the
  #   metadata address is refused: the check judges the resolved address,
  #   not the spelling.
  describe "a private own URL in any spelling" do
    for url <- [
          "https://[::ffff:10.0.0.1]/api",
          "https://[::ffff:127.0.0.1]/api",
          "https://[::1]/api",
          "https://[::]/api",
          "https://[fe80::1]/api",
          "https://[fd00::1]/api",
          "https://[64:ff9b::a00:1]/api",
          "https://0.0.0.0/api",
          "https://127.1/api",
          "https://2130706433/api",
          "https://0x7f000001/api",
          "https://0177.0.0.1/api",
          "https://169.254.169.254/api",
          "https://100.64.0.1/api",
          "https://meta.test/api",
          "https://v6mapped.test/api",
          "https://cgnat.test/api"
        ] do
      test "#{url} is refused before any request", %{saved: saved} do
        configure(saved, own_url: unquote(url))
        serve_everything()

        assert {:error, [%{source: :own, error: "url_not_allowed:" <> reason}]} = read()
        assert reason in ["private_address", "host"]
        assert requested() == []
      end
    end

    for name <- ["localhost.", "LOCALHOST", "localhost"] do
      test "#{name} resolving to loopback is refused", %{saved: saved, saved_policy: policy} do
        Application.put_env(
          :portfolixir,
          Portfolixir.Net.UrlPolicy,
          Keyword.put(policy || [], :resolver, fn host ->
            if String.downcase(host) in ["localhost", "localhost."],
              do: {:ok, [{127, 0, 0, 1}, {0, 0, 0, 0, 0, 0, 0, 1}]},
              else: {:ok, [{93, 184, 216, 34}]}
          end)
        )

        configure(saved, own_url: "https://#{unquote(name)}/api")
        serve_everything()

        assert {:error, [%{source: :own, error: "url_not_allowed:private_address"}]} = read()
        assert requested() == []
      end
    end
  end

  # User story:
  # As the operator,
  # I want an own URL that is not a plain https base refused,
  # so that no credential, query or fragment rides on the chain source's
  # requests and no other scheme is reached.
  #
  # Acceptance criteria:
  # - userinfo (with or without a password), an empty query or fragment,
  #   `file:`, `ftp:` and a scheme-relative URL are refused, with no request.
  # - A blank or non-binary own URL never reaches a host.
  describe "an own URL that is not a plain https base" do
    for {url, reason} <- [
          {"https://user@node.example.com/api", "userinfo"},
          {"https://user:@node.example.com/api", "userinfo"},
          {"https://node.example.com/api?", "query"},
          {"https://node.example.com/api#", "query"},
          {"https://node.example.com/api?host=elsewhere.example.com", "query"},
          {"file:///etc/esplora", "scheme"},
          {"ftp://node.example.com/api", "scheme"},
          {"//node.example.com/api", "scheme"},
          {"HTTP://node.example.com/api", "scheme"}
        ] do
      test "#{url} is refused as #{reason}", %{saved: saved} do
        configure(saved, own_url: unquote(url))
        serve_everything()

        assert {:error, [%{source: :own, error: "url_not_allowed:" <> unquote(reason)}]} =
                 read()

        assert requested() == []
      end
    end
  end

  # User story:
  # As the operator,
  # I want an own URL's path, port or case never to reach another host,
  # so that the own URL's one host is all its client can reach.
  #
  # Acceptance criteria:
  # - A base with dot segments, an encoded slash or an `@` in its path asks
  #   only the own host.
  # - A port on a public host is the operator's choice and is used; the
  #   host is still the only one asked.
  # - An uppercase host is the same host.
  describe "an own URL's path, port and case" do
    for url <- [
          "https://node.example.com/api/../../x",
          "https://node.example.com/%2e%2e/%2fapi",
          "https://node.example.com/api/@elsewhere.example.com",
          "https://node.example.com:8443/api",
          "https://NODE.Example.COM/api"
        ] do
      test "#{url} asks its own host only", %{saved: saved} do
        configure(saved, own_url: unquote(url))
        serve(%{"node.example.com" => {:chain, @tip}, "NODE.Example.COM" => {:chain, @tip}})

        assert {:ok, %{source: :own}} = read()

        hosts = requested() |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
        assert Enum.map(hosts, &String.downcase/1) == ["node.example.com"]
      end
    end
  end
end
