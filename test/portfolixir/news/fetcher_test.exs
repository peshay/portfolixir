defmodule Portfolixir.News.FetcherTest do
  # ADR-0056 §5, A1, A3, B2 (Sprint 27, N3): one feed's fetch. Every
  # answer comes from a plug through Req's test path and every name from
  # the test resolver; no test opens a socket or resolves a real name.
  use Portfolixir.DataCase, async: true

  import Ecto.Query
  import Portfolixir.NewsFixtures

  alias Portfolixir.Clock
  alias Portfolixir.News.Feed
  alias Portfolixir.News.FeedDay
  alias Portfolixir.News.Fetcher
  alias Portfolixir.News.Item
  alias Portfolixir.News.Pace
  alias Portfolixir.News.Parser
  alias Portfolixir.Repo

  @now ~U[2026-11-07 10:00:00.000000Z]

  defp serving(body, status \\ 200) do
    test_pid = self()

    fn conn ->
      send(test_pid, {:requested, conn.host, conn.request_path, conn.req_headers})
      Plug.Conn.send_resp(conn, status, body)
    end
  end

  defp redirecting(location) do
    test_pid = self()

    fn conn ->
      send(test_pid, {:requested, conn.host, conn.request_path, conn.req_headers})

      case conn.request_path do
        "/start.xml" ->
          conn |> Plug.Conn.put_resp_header("location", location) |> Plug.Conn.send_resp(302, "")

        _final ->
          Plug.Conn.send_resp(conn, 200, rss([]))
      end
    end
  end

  defp fetch(feed, plug, opts \\ []),
    do: Fetcher.fetch(feed, Keyword.merge([now: @now, req: [plug: plug]], opts))

  defp reload(feed), do: Repo.get!(Feed, feed.id)

  defp errors(feed) do
    case Repo.get_by(FeedDay, feed_id: feed.id, day: Clock.local_date(@now)) do
      nil -> 0
      day -> day.errors
    end
  end

  defp issuer_feed!(attrs \\ %{}),
    do: feed!(Map.merge(%{class: "issuer", security_id: security!().id}, attrs))

  # User story:
  # As the operator whose instance fetches the feeds I registered,
  # I want each fetch to store what is new and record how it went on the feed,
  # so that a working feed and a failing one read differently.
  #
  # Acceptance criteria:
  # - A 200 answer is parsed and ingested; `last_fetch_at` and `last_ok_at`
  #   are the clock, `last_error` is cleared, the backoff reset.
  # - The request carries the user agent and asks for a feed.
  describe "a successful fetch" do
    test "stores the items and records the success" do
      feed = issuer_feed!()

      body =
        rss([
          %{title: "Northwind opens a terminal", link: "https://newsroom.example.com/n/1"},
          %{title: "Northwind names a chair", link: "https://newsroom.example.com/n/2"}
        ])

      assert {:ok, %{stored: 2}} = fetch(feed, serving(body))

      assert_received {:requested, "newsroom.example.com", _path, headers}
      assert {"user-agent", agent} = List.keyfind(headers, "user-agent", 0)
      assert agent =~ "portfolixir"

      feed = reload(feed)
      assert feed.last_fetch_at == @now
      assert feed.last_ok_at == @now
      assert feed.last_error == nil
      assert feed.failures == 0
      assert feed.retry_at == nil

      assert Repo.aggregate(from(i in Item, where: i.feed_id == ^feed.id), :count) == 2
    end

    test "the operator's user agent is sent when set" do
      feed = issuer_feed!()
      fetch(feed, serving(rss([])), user_agent: "Example Operator ops@example.com")

      assert_received {:requested, _host, _path, headers}
      assert {"user-agent", "Example Operator ops@example.com"} in headers
    end
  end

  # User story:
  # As the operator,
  # I want a feed's URL checked with name resolution before every fetch and
  # its own host the only one a request may reach,
  # so that a registered URL, a changed DNS answer or a redirect cannot point
  # my server at my own network or at a host nobody registered (B2).
  #
  # Acceptance criteria:
  # - A feed whose name resolves to a private address makes no request and
  #   records `url_not_allowed:private_address`, counted in the day's errors.
  # - A redirect to another host makes no second request and records
  #   `url_not_allowed:host_not_allowed`; a redirect on the same host is
  #   followed.
  describe "the URL policy (B2)" do
    test "a feed whose name resolves privately makes no request" do
      for {host, reason} <- [
            {"internal.test", "private_address"},
            {"meta.test", "private_address"},
            {"unresolvable.test", "unresolvable"}
          ] do
        feed = issuer_feed!(%{url: "https://#{host}/feed.xml"})

        assert {:error, code} = fetch(feed, serving(rss([])))
        assert code == "url_not_allowed:" <> reason
        refute_received {:requested, _, _, _}

        feed = reload(feed)
        assert feed.last_error == code
        assert feed.last_fetch_at == @now
        assert feed.last_ok_at == nil
        assert errors(feed) == 1
      end
    end

    test "check_url/1 refuses what the registration must refuse" do
      assert :ok = Fetcher.check_url("https://newsroom.example.com/feed.xml")

      assert {:error, {:url_not_allowed, :private_address}} =
               Fetcher.check_url("https://lan.test/feed.xml")

      assert {:error, {:url_not_allowed, :scheme}} =
               Fetcher.check_url("http://newsroom.example.com/feed.xml")

      assert {:error, {:url_not_allowed, :userinfo}} =
               Fetcher.check_url("https://u:p@newsroom.example.com/feed.xml")
    end

    test "a redirect to another host makes no request; one on the same host is followed" do
      feed = issuer_feed!(%{url: "https://newsroom.example.com/start.xml"})

      assert {:error, "url_not_allowed:host_not_allowed"} =
               fetch(feed, redirecting("https://elsewhere.example.com/feed.xml"))

      assert_received {:requested, "newsroom.example.com", "/start.xml", _}
      refute_received {:requested, _, _, _}

      assert {:error, "url_not_allowed:host_not_allowed"} =
               fetch(feed, redirecting("https://10.0.0.5/feed.xml"))

      assert_received {:requested, "newsroom.example.com", "/start.xml", _}
      refute_received {:requested, _, _, _}

      assert {:ok, _summary} = fetch(feed, redirecting("/moved.xml"))
      assert_received {:requested, "newsroom.example.com", "/start.xml", _}
      assert_received {:requested, "newsroom.example.com", "/moved.xml", _}
    end
  end

  # User story:
  # As the operator,
  # I want a feed that fails to say why, back off when the host asks it to,
  # and never touch another feed,
  # so that one bad host costs nothing but its own feed's freshness.
  #
  # Acceptance criteria:
  # - 429 and 5xx count `failures` and set `retry_at` exponentially from the
  #   feed's interval; a success resets both.
  # - Another status, a timeout, a body over the cap and a parser refusal
  #   are recorded as their code, counted in the day's errors, without
  #   backoff; a parser refusal is `parse_refused:<reason>` (A1).
  describe "failures and backoff (§5)" do
    test "429 and 5xx back off exponentially and a success resets" do
      feed = issuer_feed!(%{interval_minutes: 15})

      assert {:error, "http_429"} = fetch(feed, serving("", 429))
      feed = reload(feed)
      assert feed.failures == 1
      assert feed.retry_at == DateTime.add(@now, 30, :minute)

      assert {:error, "http_503"} = fetch(feed, serving("", 503))
      feed = reload(feed)
      assert feed.failures == 2
      assert feed.retry_at == DateTime.add(@now, 60, :minute)
      assert feed.last_error == "http_503"

      assert {:ok, _} = fetch(feed, serving(rss([])))
      feed = reload(feed)
      assert feed.failures == 0
      assert feed.retry_at == nil
      assert feed.last_error == nil
      assert errors(feed) == 2
    end

    test "the backoff is capped at a day" do
      assert Fetcher.backoff_minutes(15, 1) == 30
      assert Fetcher.backoff_minutes(15, 3) == 120
      assert Fetcher.backoff_minutes(180, 4) == 1440
      assert Fetcher.backoff_minutes(10, 60) == 1440
    end

    test "other failures are recorded by code without backoff" do
      too_large = fn conn ->
        Plug.Conn.send_resp(conn, 200, :binary.copy("a", Parser.max_bytes() + 1))
      end

      stalled = fn conn ->
        Process.sleep(500)
        Plug.Conn.send_resp(conn, 200, rss([]))
      end

      cases = [
        {serving("", 404), [], "http_404"},
        {fn conn -> Req.Test.transport_error(conn, :timeout) end, [], "timeout"},
        {stalled, [deadline_ms: 50], "timeout"},
        {fn conn -> Req.Test.transport_error(conn, :econnrefused) end, [], "transport_error"},
        {too_large, [], "body_too_large"},
        {serving(~s(<?xml version="1.0"?><!DOCTYPE rss [<!ENTITY a "b">]><rss/>)), [],
         "parse_refused:dtd"},
        {serving("<html><body>not a feed</body></html>"), [], "parse_refused:not_a_feed"}
      ]

      for {plug, opts, code} <- cases do
        feed = issuer_feed!()
        assert {:error, ^code} = fetch(feed, plug, opts)

        feed = reload(feed)
        assert feed.last_error == code
        assert feed.failures == 0
        assert feed.retry_at == nil
        assert errors(feed) == 1
      end
    end
  end

  # User story:
  # As the operator whose regulatory feeds read the SEC's filings,
  # I want its fair-access rules kept: my contact in the user agent or no
  # request at all, at most ten requests a second, and IPv4,
  # so that the instance is never the one that gets blocked.
  #
  # Acceptance criteria:
  # - A feed on `sec.gov` or a subdomain without `PORTFOLIXIR_NEWS_USER_AGENT`
  #   makes no request and records `user_agent_missing`.
  # - Its request options do not set `inet6` (Mint then connects over IPv4).
  # - The pace hands one host's requests out at least 100 ms apart.
  describe "sec.gov (§5)" do
    test "without the operator's user agent no request is made" do
      feed = feed!(%{class: "regulatory", security_id: security!().id, url: sec_url()})

      assert {:error, "user_agent_missing"} =
               fetch(feed, serving(rss([])), user_agent: nil, pace: fn _ -> :ok end)

      refute_received {:requested, _, _, _}
      assert %{last_error: "user_agent_missing", failures: 0} = reload(feed)
      assert errors(feed) == 1

      assert {:ok, _} =
               fetch(feed, serving(rss([])),
                 user_agent: "Example Operator ops@example.com",
                 pace: fn _ -> :ok end
               )

      assert_received {:requested, "www.sec.gov", _, headers}
      assert {"user-agent", "Example Operator ops@example.com"} in headers
    end

    test "the request does not ask for IPv6" do
      feed = %Feed{class: :regulatory, url: sec_url(), interval_minutes: 10}

      assert {:ok, req} = Fetcher.request(feed, user_agent: "Example Operator ops@example.com")

      transport = get_in(req.options, [:finch, :conn_opts, :transport_opts]) || []
      refute Keyword.get(transport, :inet6)
      refute get_in(req.options, [:connect_options, :inet6])
      refute Map.has_key?(req.options, :inet6)
    end

    test "every sec.gov request goes through the pace, other hosts do not" do
      test_pid = self()
      pace = fn key -> send(test_pid, {:paced, key}) && :ok end
      agent = [user_agent: "Example Operator ops@example.com", pace: pace]

      feed = feed!(%{class: "regulatory", security_id: security!().id, url: sec_url()})
      fetch(feed, serving(rss([])), agent)
      assert_received {:paced, "sec.gov"}

      fetch(issuer_feed!(), serving(rss([])), agent)
      refute_received {:paced, _}
    end

    test "the pace spaces one host's requests at least 100 ms apart" do
      pace = start_supervised!({Pace, name: nil})

      delays = for _ <- 1..11, do: Pace.reserve(pace, "sec.gov", 1_000)
      assert delays == Enum.map(0..10, &(&1 * 100))

      # Another host has its own budget; a later start waits only for the queue.
      assert Pace.reserve(pace, "other.example.com", 1_000) == 0
      assert Pace.reserve(pace, "sec.gov", 3_000) == 0
      assert Pace.reserve(pace, "sec.gov", 3_050) == 50
    end
  end

  defp sec_url,
    do: "https://www.sec.gov/cgi-bin/browse-edgar?action=getcurrent&CIK=0000000001&output=atom"
end
