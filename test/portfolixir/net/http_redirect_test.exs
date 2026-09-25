defmodule Portfolixir.Net.HttpRedirectTest do
  # E25 S3, F27 (#888): the bounded client follows a redirect only through a
  # guard — every hop re-checks the URL policy against the client's own host
  # allow-list, a downgrade to plain http is refused, hops are capped, and a
  # header that could carry a credential never reaches another host. The
  # resolver in test config never touches DNS.
  use ExUnit.Case, async: true

  alias Portfolixir.Net.Http

  defp recording_plug(test_pid, answer) do
    fn conn ->
      send(test_pid, {:hop, conn.scheme, conn.host, conn.request_path, conn.req_headers})
      answer.(conn)
    end
  end

  defp redirect(conn, location) do
    conn
    |> Plug.Conn.put_resp_header("location", location)
    |> Plug.Conn.send_resp(302, "")
  end

  # User story:
  # As an operator whose instance fetches quotes, rates, search results and
  # logos from third parties,
  # I want a provider's redirect followed only when its target passes the same
  # URL policy a direct request would, on the provider's own hosts,
  # so that a hostile or impersonated provider cannot point my server at my
  # network, at another scheme or at a host of its choosing.
  #
  # Acceptance criteria:
  # - A redirect to a host outside the client's allow-list, to a non-public
  #   address or to plain http makes no second request and is an error value.
  # - A redirect to an allowed public https host is followed.
  # - A relative Location is resolved against the current hop.
  test "follows a redirect only to a target the policy allows" do
    test_pid = self()

    req = Http.new(max_bytes: 1_000, allowed_hosts: ["a.example.com", "b.example.com"])

    answer = fn target ->
      recording_plug(test_pid, fn conn ->
        case conn.request_path do
          "/start" -> redirect(conn, target)
          _ -> Plug.Conn.send_resp(conn, 200, "final")
        end
      end)
    end

    assert {:ok, %Req.Response{status: 200, body: "final"}} =
             Http.get(req,
               url: "https://a.example.com/start",
               plug: answer.("https://b.example.com/final")
             )

    assert_received {:hop, _, "a.example.com", "/start", _}
    assert_received {:hop, _, "b.example.com", "/final", _}

    assert {:ok, %Req.Response{status: 200}} =
             Http.get(req, url: "https://a.example.com/start", plug: answer.("/relative"))

    assert_received {:hop, _, "a.example.com", "/start", _}
    assert_received {:hop, _, "a.example.com", "/relative", _}

    for {target, reason} <- [
          {"https://evil.example.org/final", :host_not_allowed},
          {"http://a.example.com/final", :scheme},
          {"https://10.0.0.5/final", :host_not_allowed},
          {"https://user:pw@b.example.com/final", :userinfo}
        ] do
      assert {:error, {:url_not_allowed, ^reason}} =
               Http.get(req, url: "https://a.example.com/start", plug: answer.(target)),
             target

      assert_received {:hop, _, "a.example.com", "/start", _}
      refute_received {:hop, _, _, _, _}
    end
  end

  test "refuses a redirect to an allowed name that resolves to a non-public address" do
    test_pid = self()
    req = Http.new(max_bytes: 1_000, allowed_hosts: [".test"])

    plug =
      recording_plug(test_pid, fn conn ->
        case conn.request_path do
          "/start" -> redirect(conn, "https://internal.test/final")
          _ -> Plug.Conn.send_resp(conn, 200, "final")
        end
      end)

    assert {:error, {:url_not_allowed, :private_address}} =
             Http.get(req, url: "https://public.test/start", plug: plug)

    assert_received {:hop, _, "public.test", "/start", _}
    refute_received {:hop, _, _, _, _}
  end

  # User story:
  # As an operator,
  # I want a redirect chain capped at a few hops,
  # so that a looping upstream costs a bounded number of requests.
  #
  # Acceptance criteria:
  # - A chain longer than the cap is {:error, :too_many_redirects}.
  # - The first request goes only to a host on the client's allow-list.
  test "caps the hops and refuses a first request outside the allow-list" do
    test_pid = self()
    req = Http.new(max_bytes: 1_000, allowed_hosts: ["a.example.com"])

    loop = recording_plug(test_pid, &redirect(&1, "https://a.example.com/loop"))

    assert {:error, :too_many_redirects} =
             Http.get(req, url: "https://a.example.com/loop", plug: loop)

    hops = collect_hops()
    assert length(hops) == 4

    assert {:error, {:url_not_allowed, :host_not_allowed}} =
             Http.get(req, url: "https://evil.example.org/x", plug: loop)

    assert {:error, {:url_not_allowed, :scheme}} =
             Http.get(req, url: "http://a.example.com/x", plug: loop)

    refute_received {:hop, _, _, _, _}
  end

  # User story:
  # As an operator who configured a provider API key,
  # I want every header that could carry a credential dropped the moment a
  # redirect changes the host,
  # so that my key is only ever sent to the provider it belongs to.
  #
  # Acceptance criteria:
  # - A same-host hop keeps the client's headers.
  # - After a host change only the user agent and accept headers survive:
  #   authorization, cookies and any client-specific key header are gone, and
  #   they stay gone if a later hop returns to the first host.
  test "drops credential-bearing headers on a host change and never restores them" do
    test_pid = self()

    req =
      Http.new(
        max_bytes: 1_000,
        allowed_hosts: ["a.example.com", "b.example.com"],
        headers: [
          {"user-agent", "portfolixir-test"},
          {"authorization", "Bearer synthetic"},
          {"x-synthetic-api-key", "synthetic-key"},
          {"cookie", "session=synthetic"}
        ]
      )

    plug =
      recording_plug(test_pid, fn conn ->
        case {conn.host, conn.request_path} do
          {"a.example.com", "/start"} -> redirect(conn, "/same-host")
          {"a.example.com", "/same-host"} -> redirect(conn, "https://b.example.com/other")
          {"b.example.com", "/other"} -> redirect(conn, "https://a.example.com/back")
          _ -> Plug.Conn.send_resp(conn, 200, "final")
        end
      end)

    assert {:ok, %Req.Response{status: 200}} =
             Http.get(req, url: "https://a.example.com/start", plug: plug)

    [start, same_host, other, back] = collect_hops()

    for {_, _, _, _, headers} <- [start, same_host] do
      assert {"authorization", "Bearer synthetic"} in headers
      assert {"x-synthetic-api-key", "synthetic-key"} in headers
      assert {"cookie", "session=synthetic"} in headers
    end

    for {_, _, _, _, headers} <- [other, back] do
      names = Enum.map(headers, &elem(&1, 0))
      refute "authorization" in names
      refute "x-synthetic-api-key" in names
      refute "cookie" in names
      assert {"user-agent", "portfolixir-test"} in headers
    end
  end

  test "the whole chain runs under one deadline" do
    req = Http.new(max_bytes: 1_000, allowed_hosts: ["a.example.com"], deadline_ms: 100)

    plug = fn conn ->
      Process.sleep(40)
      redirect(conn, "https://a.example.com/next-#{System.unique_integer([:positive])}")
    end

    assert {:error, :deadline} = Http.get(req, url: "https://a.example.com/start", plug: plug)
  end

  defp collect_hops(acc \\ []) do
    receive do
      {:hop, _, _, _, _} = hop -> collect_hops([hop | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
