defmodule Portfolixir.News.FetcherNoNetworkTest do
  # ADR-0056 §5 (Sprint 27, N3): the suite registers a fake provider and
  # never touches the network. Not async: it counts the VM's TCP ports, so
  # no other test may open one meanwhile.
  use Portfolixir.DataCase, async: false

  import Portfolixir.NewsFixtures

  alias Portfolixir.News.Fetcher

  @now ~U[2026-11-07 10:00:00.000000Z]

  # User story:
  # As the maintainer,
  # I want the suite's fetches to go to a fake provider by default,
  # so that no test of the news layer ever opens a socket.
  #
  # Acceptance criteria:
  # - The test configuration routes the fetcher through a plug; a fetch no
  #   test stubbed answers as a refused connection and opens no TCP port.
  describe "no network in the suite" do
    test "an unstubbed fetch opens no socket" do
      feed = feed!(%{class: "issuer", security_id: security!().id})

      assert {:ok, req} = Fetcher.request(feed, [])
      assert req.options[:plug] == Portfolixir.News.NoNetwork

      before = tcp_ports()
      assert {:error, "transport_error"} = Fetcher.fetch(feed, now: @now)
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
