defmodule Portfolixir.Chains.EsploraOwnUrlTest do
  # ADR-0059 §3, §10 (Sprint 29, H2): the operator's own Esplora URL and the
  # sources' allow-lists. Not async: each test sets the adapter's
  # application environment, as config/runtime.exs sets it from
  # PORTFOLIXIR_BITCOIN_ESPLORA_URL at boot, and the suite's no-network
  # check counts the VM's TCP ports.
  use ExUnit.Case, async: false

  import Portfolixir.EsploraFixtures

  alias Portfolixir.Chains.Esplora

  @now ~U[2026-11-12 12:00:00Z]
  @tip 870_000

  setup do
    saved = Application.get_env(:portfolixir, Esplora)
    on_exit(fn -> Application.put_env(:portfolixir, Esplora, saved) end)
    %{saved: saved}
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

  # User story:
  # As the operator who runs an own mempool or Esplora instance,
  # I want PORTFOLIXIR_BITCOIN_ESPLORA_URL to replace both public sources,
  # so that my instance asks only my own host for the chain.
  #
  # Acceptance criteria:
  # - With the own URL set, only its host is asked; neither mempool.space
  #   nor blockstream.info is, not even when the own host fails.
  # - A trailing slash on the URL changes nothing.
  # - A plain-http URL, one with userinfo, or one whose host resolves to a
  #   private or loopback address is refused with `url_not_allowed:<reason>`
  #   and makes no request at all.
  describe "the operator's own URL replaces both sources" do
    test "only the own host is asked", %{saved: saved} do
      configure(saved, own_url: "https://node.example.com/esplora/")
      serve(%{"node.example.com" => {:chain, @tip}, "mempool.space" => {:chain, @tip}})

      assert {:ok, reading} = read()
      assert reading.source == :own
      assert reading.host == "node.example.com"
      assert reading.base == "https://node.example.com/esplora"
      assert reading.tip == @tip

      assert Enum.all?(requested(), &match?({"node.example.com", _}, &1))
    end

    test "a failing own host has no fallback", %{saved: saved} do
      configure(saved, own_url: "https://node.example.com/api")

      serve(%{
        "node.example.com" => {:status, 503},
        "mempool.space" => {:chain, @tip},
        "blockstream.info" => {:chain, @tip}
      })

      assert {:error, [%{source: :own, host: "node.example.com", error: "http_503"}]} = read()
      assert requested() == [{"node.example.com", "blocks/tip/height"}]
    end

    for {url, code} <- [
          {"http://node.example.com/api", "url_not_allowed:scheme"},
          {"https://internal.test/api", "url_not_allowed:private_address"},
          {"https://loopback.test/api", "url_not_allowed:private_address"},
          {"https://192.168.1.20/api", "url_not_allowed:private_address"},
          {"https://v6loopback.test/api", "url_not_allowed:private_address"},
          {"https://user:secret@node.example.com/api", "url_not_allowed:userinfo"}
        ] do
      test "#{url} is refused before any request", %{saved: saved} do
        configure(saved, own_url: unquote(url))

        serve(%{
          "internal.test" => {:chain, @tip},
          "loopback.test" => {:chain, @tip},
          "node.example.com" => {:chain, @tip},
          "mempool.space" => {:chain, @tip},
          "blockstream.info" => {:chain, @tip}
        })

        host = URI.parse(unquote(url)).host

        assert read() == {:error, [%{source: :own, host: host, error: unquote(code)}]}
        assert requested() == []
      end
    end
  end

  # User story:
  # As the operator whose instance may reach only the hosts B2 registered,
  # I want each public source's client to carry its own registered host as
  # its allow-list,
  # so that a source whose base names another host is refused by the
  # chokepoint and reaches nothing.
  #
  # Acceptance criteria:
  # - A default source configured with a host its allow-list does not name
  #   is refused as `url_not_allowed:host_not_allowed`, with no request, and
  #   the fallback is asked.
  describe "each source reaches only its registered host" do
    test "a base on a host the allow-list does not name makes no request", %{saved: saved} do
      configure(saved,
        sources: [
          mempool: "https://api.llm-vendor.example/v1",
          blockstream: "https://blockstream.info/api"
        ]
      )

      serve(%{"api.llm-vendor.example" => {:chain, @tip}, "blockstream.info" => {:chain, @tip}})

      assert {:ok, reading} = read()
      assert reading.source == :blockstream

      assert reading.attempts == [
               %{
                 source: :mempool,
                 host: "api.llm-vendor.example",
                 error: "url_not_allowed:host_not_allowed"
               }
             ]

      refute Enum.any?(requested(), &match?({"api.llm-vendor.example", _}, &1))
    end
  end

  # User story:
  # As the maintainer,
  # I want the suite's chain reads to go to a fake source by default,
  # so that no test of the chain source ever opens a socket (ADR-0059 §10).
  describe "no network in the suite" do
    test "an unstubbed read opens no socket" do
      assert Keyword.fetch!(Application.get_env(:portfolixir, Esplora), :plug) ==
               Portfolixir.Chains.NoNetwork

      before = tcp_ports()

      assert {:error,
              [
                %{source: :mempool, error: "transport_error"},
                %{source: :blockstream, error: "transport_error"}
              ]} = read()

      assert MapSet.subset?(tcp_ports(), before)
    end
  end

  defp tcp_ports do
    for port <- Port.list(),
        {:name, ~c"tcp_inet"} == Port.info(port, :name),
        into: MapSet.new(),
        do: port
  end
end
